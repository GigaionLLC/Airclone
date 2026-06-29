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

**Related:** [Core Architecture](08-core-architecture.md) · [Enterprise Readiness](19-enterprise-readiness.md) ·
[Persistence Index](../database/database-index.md)
