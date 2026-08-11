---
type: "core"
name: "Security"
status: "stable"
dependencies: ["08-core-architecture", "19-enterprise-readiness"]
description: "Threat model, engine hardening, secrets, encryption, audit, and the honest guardrail boundary."
---

# 🔒 Security

Airclone holds cloud credentials and moves data, so security is a first-class design concern — for the
solo user *and* the enterprise. The guiding stance: **local-first, no phone-home, encrypted by
default, and honest about what we can and cannot guarantee.**

**When to read this:** before you write code that stores, prompts for, logs or forwards a credential —
RC auth flags, config-encryption handling, `SecretStore`/keystore work, a new `serve` or mount
listener, an update/verification path. Also read it when a review flags a plaintext secret on disk, an
unauthenticated local port, or a fail-open verification step.

## 1. Threat Model (what we defend against)

| Threat | Defense |
| :--- | :--- |
| **Another local process hijacks the engine** (drives transfers, reads config) over the RC port | Bind `rcd` to **loopback / unix socket / named pipe**; random per-session `--rc-user`/`--rc-pass`; TLS (`--rc-cert/--rc-key`, `--rc-min-tls-version tls1.2`). Mobile uses in-process `librclone` — **no network surface at all**. |
| **Credential theft at rest** (plaintext `rclone.conf`, reversible "obscure") | Config encrypted by default; passphrase in the OS keystore; per-remote secrets resolved from a `SecretStore` and injected at spawn — plaintext need never hit disk. |
| **Credential theft in transit** | TLS ≥ 1.2 on RC + serve surfaces; optional mTLS; corporate CA bundle support. |
| **Locked-config deadlock / startup crash** | Detect encryption **out-of-band before any RC call**; never `--ask-password=false`; feed `RCLONE_CONFIG_PASS` via env. |
| **Supply-chain tampering** (binary swap, MITM update) | Sign + notarize all artifacts incl. the bundled rclone; pin + **fail-closed** verify the rclone binary; SBOM + provenance; disable `selfupdate` by policy. |
| **Data exfiltration via the app** (cooperative-user guardrail) | Policy kill-switches + backend allow/deny + remote-pair rules enforced **in the seam**; audit trail of every transfer. (See the honesty note in §6.) |
| **Accidental phone-home** | All egress default-OFF; no hardcoded remote endpoints; a CI test asserts zero outbound on a clean config. |

## 2. Engine & RC Hardening

- **Desktop `rcd`:** loopback or unix-socket/named-pipe binding (preferred over TCP to dodge
  localhost CSRF / DNS-rebinding); random per-session credentials, never persisted; TLS with a
  minimum version; narrow `--rc-allow-origin`; **never** `--rc-no-auth` on a TCP listener.
- **Mobile `librclone`:** in-process; no port, no listener, no network attack surface.
- **`operations/uploadfile` / `core/command`** are unavailable in `librclone` — on mobile, upload via
  `operations/copyfile` / `sync/copy` and never call `core/command`. See
  [08-core-architecture.md](08-core-architecture.md).

## 3. Secrets

A single **`SecretStore`** seam abstracts credential storage with backends per environment:

- **OS-native:** Windows DPAPI + Credential Manager (TPM-backed), macOS Keychain + Secure Enclave,
  Linux Secret Service / KWallet, Android Keystore + StrongBox (biometric-bound), iOS Keychain +
  Secure Enclave (device-only, never iCloud-synced).
- **Enterprise:** HashiCorp Vault, cloud KMS / Secrets Managers, CyberArk.
- **References, not literals:** secrets resolve as references (`vault://…`, `keyring://…`,
  `awssm://…`) and are injected at engine spawn via `RCLONE_CONFIG_*` + `--password-command`, so
  `rclone.conf` need not contain plaintext.
- The **config password** lives in the keystore; on mobile, decryption is gated behind biometric /
  device unlock. The password is **never persisted by Airclone** in plaintext and never sent anywhere.

### 3.1 Mobile config lifetime — uninstall is destructive, by design

On phones `rclone.conf` lives in the app's private sandbox (`/data/user/0/<pkg>/files` on Android,
the app container on iOS), and Android's manifest sets **`allowBackup="false"`** so the file can
never ride along in an ADB or cloud backup where it could be read off-device.

The cost of that choice is unavoidable and worth stating plainly: **uninstalling the app destroys
the config, and no automatic backup restores it.** Verified on Android 15 (2026-08-11) —
uninstall + reinstall leaves no `files/` directory at all. Desktop is unaffected; its config lives
outside the app in rclone's own directory and survives reinstalling.

The supported way across an uninstall or a new phone is therefore an explicit export — Settings →
Import & export (encrypted file export, or the Offline QR handoff). The Config section says so
in-app on mobile, above the export buttons, rather than leaving the user to find out afterwards.

Do **not** "fix" this by enabling `allowBackup` or by writing the config to shared storage: both put
unencrypted cloud credentials somewhere other apps or a device backup can reach them. If an
automatic escape hatch is ever wanted, it has to be an opt-in, passphrase-encrypted export written
outside the sandbox — a design decision, not a default.

## 4. Encryption

- **Config encryption** on by default (rclone's encrypted config).
- **`crypt` remotes** are first-class — wrap any remote for transparent E2E encryption, with a
  "wrap an existing remote" wizard and a live filename-transform preview.
- **In transit:** TLS ≥ 1.2 everywhere a socket exists (RC, serve, control-plane enrollment).
- **FIPS:** an optional FIPS build (Go FIPS module) forces TLS ≥ 1.2 and **labels `crypt` as
  non-FIPS** (it uses XSalsa20/scrypt); at-rest FIPS relies on backend server-side encryption. Scope:
  desktop/server. See [19-enterprise-readiness.md §6](19-enterprise-readiness.md).

## 5. Audit & Policy Enforcement

- **Audit:** every security-relevant action (config change, transfer, mount, serve, policy change)
  emits a structured JSON event onto an internal bus. Default sink = a **local, append-only,
  hash-chained** log the user/admin can read. Export to SIEM is **opt-in** and additive (never blocks
  the local write).
- **Policy enforcement happens at the `RcloneClient` seam**, not in the UI — a disallowed action is
  refused at the call boundary, so it can't be bypassed by editing the UI or scripting around it. The
  Policy Engine reads OS-native managed config; see
  [19-enterprise-readiness.md §2](19-enterprise-readiness.md).

### 5.1 Diagnostics — evidence without telemetry

Airclone sends **no** crash reports, analytics, or error telemetry. That leaves a real gap: a bug
report with no evidence is a bug that never gets fixed. The answer is a local, user-driven log
([`diagnostics.dart`](../../app/lib/src/state/diagnostics.dart)), surfaced at
**Settings → Diagnostics → Problem report**:

- A **bounded in-memory ring** (`kDiagnosticsCapacity = 300`). Nothing is written to disk unless the
  user saves or shares a report; nothing is ever transmitted.
- **Redaction runs at INGEST, not at export.** `redactSensitive` is applied inside
  `DiagnosticsLog.record`, so a secret rclone echoed into an error never enters the ring — an export
  path that forgot to sanitise therefore cannot leak. It strips secret-named config keys
  (`secret_access_key`, `client_secret`, `…_pass`), OAuth token blobs, `Bearer`/`Basic` headers,
  URL-embedded credentials, email addresses, and home-directory names (keeping the rest of the path,
  which is what makes a report useful).
- The report **header carries versions, platform and install channel only** — never a remote name,
  account, or hostname.
- Uncaught framework and async errors are routed in from the app root, so a crash leaves a trace.

When adding a new failure path, log it here rather than only showing a SnackBar: the SnackBar is
gone in three seconds, and this is the only channel by which a user can hand a maintainer the detail.

## 6. Honest Guardrail Boundary

> Airclone is a **strong guardrail for cooperative users** and an **audit trail for everyone** — not
> an unbypassable DLP appliance. A determined local administrator who can run the `rclone` binary
> directly, with the same config, can do anything the OS permits.

We state this plainly rather than overselling "DLP." Real containment for hostile insiders comes from
OS-level controls (egress filtering, managed devices, least-privilege credentials) layered *with*
Airclone's guardrails — Airclone makes the right thing easy, the wrong thing logged, and the
policy-forbidden thing refused at the seam.

## 7. Disclosure & Response

- Publish `/.well-known/security.txt` (RFC 9116) and a coordinated-vulnerability-disclosure policy;
  route issues through a CVE Numbering Authority path for real CVE IDs.
- Maintain an LTS line patched 18–24 months.
- Treat an **unauthenticated localhost RC port** and **fail-open artifact verification** as P0 bug
  classes.

---

## 🔗 Related

- [08-core-architecture.md](08-core-architecture.md) — the `RcloneClient` seam these controls are
  enforced at, the librclone constraints in §2, and out-of-band encryption detection.
- [07-state-context.md](07-state-context.md) — where the config password, credential vault and cached
  crypto actually live in state, and what is persisted.
- [11-validation-standards.md](11-validation-standards.md) — how a refused or failed action is gated
  and surfaced, so a policy denial reads as a real error rather than a silent no-op.
- [19-enterprise-readiness.md](19-enterprise-readiness.md) — the managed-config Policy Engine (§2) and
  FIPS scope (§6) that §4 and §5 defer to.
- [10-external-integrations.md](10-external-integrations.md) — the RC, serve and mount surfaces whose
  exposure this doc constrains.
- [../database/database-index.md](../database/database-index.md) — what Airclone persists locally, and
  what is deliberately left to the engine.
- [00-system-index.md](00-system-index.md) — master router.
