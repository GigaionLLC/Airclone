---
type: "core"
name: "Security"
status: "stable"
dependencies: ["08-core-architecture", "19-enterprise-readiness"]
description: "Threat model, engine hardening, secrets, encryption, audit, and the honest guardrail boundary."
---

# 🔒 Security

Airclone holds cloud credentials and moves data, so security is a first-class design concern — for the
solo user *and* the enterprise. The guiding stance: **local-first, no phone-home, encryption always
within one step, and honest about what we can and cannot guarantee.** That last clause governs this
document too — §1 separates what is built from what is designed, and nothing here may state an
aspiration in the present tense.

**When to read this:** before you write code that stores, prompts for, logs or forwards a credential —
RC auth flags, config-encryption handling, `SecretStore`/keystore work, a new `serve` or mount
listener, an update/verification path. Also read it when a review flags a plaintext secret on disk, an
unauthenticated local port, or a fail-open verification step.

## 1. Threat Model (what we defend against)

**Read the two columns as two different things.** *Today* is what the shipped binary does and can be
checked against the source; *designed* is the intended end state. A security document that blurs them
is the most expensive kind of documentation error there is — it tells a reviewer a control exists that
does not, so this table never states an aspiration in the present tense.

| Threat | Defense today | Designed, not built |
| :--- | :--- | :--- |
| **Another local process hijacks the engine** (drives transfers, reads config) over the RC port | `rcd` binds `127.0.0.1:<free port>` — plain HTTP with **random per-session Basic credentials** (`--rc-user airclone`, 24 random bytes as the password), never persisted, and the user's own engine flags are placed *first* in the argv so they cannot shadow them. In-process (iOS / Mac App Store) there is **no listener at all**. | TLS on the RC surface (`--rc-cert`/`--rc-key`, `--rc-min-tls-version tls1.2`), a unix socket / named pipe instead of TCP, a narrowed `--rc-allow-origin`. None of these flags appear anywhere in `app/`. |
| **Credential theft at rest** (plaintext `rclone.conf`, reversible "obscure") | rclone's config encryption is **supported, not imposed**: Airclone detects an already-encrypted config out-of-band, gates startup on the password, and can set/change/remove encryption on request. The password is optionally held in the OS vault (opt-in, default off) and never written by Airclone in plaintext. | Encryption **on by default**, and per-remote secrets resolved from a `SecretStore` as references and injected at spawn so `rclone.conf` need never hold a literal. |
| **Credential theft in transit** | Backend traffic is rclone's own (HTTPS to each provider). The loopback RC channel is not TLS — see the row above. | TLS ≥ 1.2 on the RC and serve surfaces; optional mTLS; corporate CA bundle support. |
| **Locked-config deadlock / startup crash** | Encryption is detected **out-of-band before any RC call** by reading the config file header; `--ask-password=false` is never used (it crashes rclone); `RCLONE_CONFIG_PASS` travels by env, never argv. | *Nothing outstanding — this row is fully built.* |
| **Supply-chain tampering** (binary swap, MITM update) | The rclone version is pinned in one place and the download path is **fail-closed** — no fetchable, parseable, matching `SHA256SUMS` entry, no install. Windows artifacts are signed; macOS is Developer-ID signed + notarized; the bundled rclone is signed with them. | SBOM + build provenance; disabling rclone's own `selfupdate` by policy. |
| **Data exfiltration via the app** (cooperative-user guardrail) | Four kill-switch seams enforced **inside the controller**, not only in the UI — mount, serve, reveal-in-file-manager, archive ([07 §Mount, serve & policy](07-state-context.md)). `serve/start` additionally whitelists its params, defaults to loopback and forces auth on exposed auth-capable protocols. | Backend allow/deny lists, remote-pair rules, and an audit trail of every transfer. (See the honesty note in §6.) |
| **Accidental phone-home** | No telemetry, no analytics, no crash reporting; diagnostics never leave the device unless the user exports them. Airclone itself reaches exactly two destinations, both only on a user action: the **app** release check (`api.github.com`), where a store-managed install **short-circuits before the request** (§5.1 of [10](10-external-integrations.md)); and the **rclone engine** version check and download (`downloads.rclone.org`), which a packaged Store build refuses via `RcloneEngine.isStoreManaged()` (§5 of [14](14-performance-standards.md)) and which is only offered where that refusal does not apply. Nothing else leaves the device. | A CI test asserting zero outbound traffic on a clean config. No such test exists today. |

## 2. Engine & RC Hardening

- **Spawned `rcd` (desktop and Android), today:** loopback TCP on a free port, random per-session
  Basic credentials that are never persisted, and user engine flags placed **first** in the argv so
  the last-wins pflag rule cannot let a pasted flag shadow `--rc-addr`/`--rc-user`/`--rc-pass`.
  `--rc-no-auth` is never passed. A unix socket / named pipe (preferred over TCP to dodge localhost
  CSRF and DNS-rebinding), TLS with a minimum version, and a narrowed `--rc-allow-origin` are
  **designed, not implemented** — none of those flags exist in `app/`.
- **In-process `librclone` (iOS, Mac App Store):** no port, no listener, no network attack surface for
  the RC channel itself. The one exception is `LibrcloneObjectServer`, a loopback byte bridge on port
  0 with a per-session Bearer token, which exists only because `RcloneRPC` returns JSON and previews
  need bytes.
- **`operations/uploadfile` / `core/command`** are unavailable in `librclone`; upload via
  `operations/copyfile` / `sync/copy` and use the argv→RC translator instead of `core/command`. See
  [08-core-architecture.md](08-core-architecture.md).

## 3. Secrets

**What ships today** is narrower than the design below and is the part to build against: two
`flutter_secure_storage` keys — `airclone.configPassword` and `airclone.externalBackupPassphrase` —
both opt-in, both cleared when their feature is turned off, and both degrading to a manual prompt
rather than a crash when the vault is unavailable ([07-state-context.md](07-state-context.md)). Every
other credential lives in `rclone.conf`, which the engine owns.

**Biometric unlock also ships** ([`biometric_unlock.dart`](../../app/lib/src/state/biometric_unlock.dart),
`biometricUnlockOptInProvider`, default **off**), on every platform whose OS can answer `local_auth`
— not mobile only. Be precise about what it is, in the file's own words: it *"adds NO cryptography"*
and is *"an unlock-UX gate, not a security boundary"*. The config password is already in the OS vault
bound to device unlock; a successful prompt merely **releases** it during the engine's cold start
instead of showing the typing gate, and the prompt is required *before* the stored secret is read, so
a refusal never pulls the plaintext into memory. Anyone who can unlock the device can still reach the
keystore. It never hard-blocks startup: no hardware, no enrolment, a thrown platform call or a
cancelled prompt all fall back to the existing manual password gate.

The designed end state is a single **`SecretStore`** seam abstracting credential storage with
backends per environment. **No such class exists yet**; when it lands it must satisfy:

- **OS-native:** Windows DPAPI + Credential Manager (TPM-backed), macOS Keychain + Secure Enclave,
  Linux Secret Service / KWallet, Android Keystore + StrongBox (biometric-bound), iOS Keychain +
  Secure Enclave (device-only, never iCloud-synced).
- **Enterprise:** HashiCorp Vault, cloud KMS / Secrets Managers, CyberArk.
- **References, not literals:** secrets resolve as references (`vault://…`, `keyring://…`,
  `awssm://…`) and are injected at engine spawn via `RCLONE_CONFIG_*` + `--password-command`, so
  `rclone.conf` need not contain plaintext.
- The **config password** resolves through the same seam as every other secret rather than through
  its own vault call. It is **never persisted by Airclone** in plaintext and never sent anywhere —
  that much is already true today, as is the biometric gate in front of releasing it (above). The
  seam is the part that does not exist.

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

Do **not** "fix" this by enabling `allowBackup` or by writing a *plaintext* config to shared storage
by default: both put unencrypted cloud credentials somewhere other apps or a device backup can reach
them. The supported escape hatch is §3.2, which is opt-in and encrypted.

### 3.2 "Survive uninstall" — the opt-in copy outside the sandbox

[`external_config_backup.dart`](../../app/lib/src/state/external_config_backup.dart) mirrors the
config to `<shared storage>/Airclone/`, which the OS does **not** delete with the app (unlike
`Android/data/<pkg>/`). Settings → Config → **Survive uninstall**. Android-only: desktop needs none
of it, and iOS has no equivalent shared location.

The shape of the feature *is* the security design:

| Mode | File | Protection |
| :--- | :--- | :--- |
| `off` (**default**) | none | nothing exists outside the sandbox |
| `encrypted` | `airclone-config.acfg` | ACFG2 envelope — AES-256-GCM over Argon2id, the same format as the encrypted export |
| `plaintext` | `rclone.conf` | **none** — reachable only behind a danger confirmation |

Rules this code must keep:

- **The passphrase prompt is the enable flow.** There is no path to an unencrypted copy that does
  not pass an explicit second screen listing what it means (any app with file access can read it;
  device backups and phone-to-phone transfers copy it; anyone holding the unlocked phone can open
  it) plus a checkbox acknowledgement. Users who genuinely want a plain `rclone.conf` may have one —
  never by accident.
- **Only one file may exist.** Switching modes deletes the other, and a failure to delete a
  *plaintext* file is raised, not swallowed — leaving readable credentials behind while the UI says
  otherwise is the worst outcome available.
- **Turning it off deletes the file.** Opting out must not leave the credentials on disk.
- **Writes are atomic** (`.part` then rename). After an uninstall this is the user's only copy.
- **The seal runs in `compute()`.** Argon2id at 64 MiB is pure Dart; this path also runs
  automatically when remotes change, so it must not jank the UI isolate.
- **The passphrase lives in the OS vault** so the backup can refresh unattended. The vault dies with
  the app on uninstall, which is correct — a restore should require typing it.

Restore is deliberately **not** a second code path: the bytes are handed to the normal import wizard
(`showConfigImportDialog(initialBytes:)`), so a restore gets the same passphrase prompt, the same
mandatory preview with endpoint summaries, and the same collision handling as any other import.
`restorableBackupProvider` watches All Files Access as well as the remotes list — a fresh install has
no storage permission yet, so the offer must re-fire when the grant lands rather than only at launch.

**Collision handling has two modes, and only the safe one is the default.** A name already in the
live config is planned as a rename (`foo` → `foo-imported`, bumping `-2`, `-3`; `planImport` in
[config_io.dart](../../app/lib/src/state/config_io.dart)). That is always recoverable but it is not
always what was meant — re-importing a corrected config left the stale `foo` in place and the app
still using it. So the preview offers **"Replace the N existing remotes instead of renaming"**,
which sets `ImportDecision.replaceExisting` and lets the `config/create` land on the remote already
holding the name (rclone overwrites a section rather than refusing it — see also the guard on the
add-remote/encrypt paths, which is why this one had to become an explicit choice rather than an
accident). Rules:

- **Off by default, per import**, never remembered. The destructive reading of an ambiguous gesture
  must be chosen each time.
- **The warning names the encrypted case**, not just "this overwrites": a crypt remote replaced with
  a different password or salt still connects and still reports free space — it simply stops being
  able to decrypt the names of what it stored, and the folder lists as **empty**. That is a real
  incident, not a hypothetical (see §3.4 of
  [14-performance-standards](14-performance-standards.md)).
- **The backup still runs first**, before any create, exactly as for a plain merge.
- **The report separates `replaced` from `created`.** "Imported 6 remotes" and "imported 6 remotes
  over 6 of yours" are different outcomes and only one of them is worth re-reading.

One state to keep in mind: the *mode* lives in SharedPreferences (wiped by uninstall) while the
*file* does not, so straight after a reinstall the switch reads off beside a real backup. Settings
says so explicitly and offers to resume; a user who has just restored must not believe they are
still covered.

Verified end-to-end on Android 15 (2026-08-11): enable → uninstall (file survives, `ACFG2` header,
no plaintext secrets) → reinstall (app data gone) → automatic offer → passphrase → review → merge →
remotes back; deleting a remote rewrites the backup unprompted; turning it off removes the file.

### 3.3 Destructive config paths

Three paths can destroy credentials rather than files, so each one is gated in the code and not only
in the UI. The shared rule: **snapshot the config before mutating it, and refuse the operation when
the snapshot cannot be taken.**

| Path | Gate |
| :--- | :--- |
| **`config/create` on a name that already exists** | rclone REPLACES that section — exit 0, no warning, nothing in the response to distinguish it from a create. The add-remote and encrypt-remote wizards therefore read `existingRemoteNames(client)` ([remotes_provider.dart](../../app/lib/src/state/remotes_provider.dart)) first and refuse a taken name, **failing closed when the config cannot be read** — an unreadable config is not a free name. |
| **Import → "Replace the N existing remotes"** | The one path allowed to overwrite, and only as an explicit, per-import, never-remembered choice (§3.2). Backup first; the report separates `replaced` from `created`. |
| **Settings → Remove all remotes** ([remove_all_remotes.dart](../../app/lib/src/ui/remove_all_remotes.dart)) | The bulk form of a per-remote delete, because starting over otherwise meant a confirmation per remote in a list where names differ by two characters. It names every remote it will remove, requires an acknowledgement rather than just a red button, backs the config up first, and **throws rather than deleting anything if the active config file cannot be located to back up**. Deletes run one `config/delete` at a time and a failure is reported per remote, not swallowed. Any pane still pointing at a (non-local) remote is cleared afterwards, so nothing keeps showing a listing for a remote that no longer exists. |

Why the credential wording matters on all three: removing or replacing a remote does not touch the
files on it, but it does destroy the credentials, paths and — for a `crypt` remote — the password and
salt that make its contents readable. A crypt remote recreated with a different key still connects
and still reports free space; it simply stops being able to decrypt the names of what it stored, and
the folder lists as empty. The UI has to say that, because nothing in rclone's response does.

### 3.4 Unattended unlock — background runs

Scheduled runs move the vault outside the foreground app, and that is a trust-boundary statement
worth making plainly rather than leaving implied by §3.

A Windows Task Scheduler `--run-due` launch and an Android WorkManager wake both end up in the same
place: [`headless_runner.dart`](../../app/lib/src/headless/headless_runner.dart), whose `_startEngine`
reads the config password out of the OS vault and unlocks an encrypted config **with no user
present**. No biometric prompt is possible on that path — there is nobody to prompt — so the
release gate described above simply does not apply there. On Android this happens inside a *second*
Flutter engine in the app's own process, with no Activity and no widget tree
([`android_work_entrypoint.dart`](../../app/lib/src/state/android_work_entrypoint.dart)).

That is the price of a backup that runs while the app is closed, and it is gated by exactly one
thing: the user having opted into remembering the config password. A headless run that cannot obtain
one does **not** prompt, does not guess, and does not run — it exits `kExitCannotStart` (2) with a
message naming the setting that would allow it. Anything new on this path inherits the same rule:
an unattended runner may read a secret the user chose to store, and may never create one, persist
one, or write one anywhere.

## 4. Encryption

- **Config encryption** is rclone's own, and it is **user-initiated, not on by default**. Airclone
  detects an already-encrypted config out-of-band, gates startup behind the password, and can set,
  change or remove encryption on request (a real subprocess, run with the engine quiesced — rclone
  prompts on stdin). Encrypt-by-default is a design goal, not current behaviour; do not describe it
  as shipped anywhere.
- **`crypt` remotes** are first-class — wrap any remote for transparent E2E encryption, with a
  "wrap an existing remote" wizard and a live filename-transform preview.
- **In transit (designed):** TLS ≥ 1.2 everywhere a socket exists — RC, serve, control-plane
  enrollment. Today only the backend traffic rclone itself makes is TLS; the loopback RC channel is
  not (§1).
- **FIPS:** an optional FIPS build (Go FIPS module) forces TLS ≥ 1.2 and **labels `crypt` as
  non-FIPS** (it uses XSalsa20/scrypt); at-rest FIPS relies on backend server-side encryption. Scope:
  desktop/server. See [19-enterprise-readiness.md §6](19-enterprise-readiness.md).

## 5. Audit & Policy Enforcement

The audit bus below is **designed, not built** — what exists today is §5.1, the local diagnostics
ring, which is a debugging channel and not an audit log. Policy enforcement *is* real, in the narrow
form of the four kill-switch seams named in §1.

- **Audit (designed):** every security-relevant action (config change, transfer, mount, serve, policy change)
  emits a structured JSON event onto an internal bus. Default sink = a **local, append-only,
  hash-chained** log the user/admin can read. Export to SIEM is **opt-in** and additive (never blocks
  the local write).
- **Policy enforcement happens below the UI** — today inside the controller that performs the action
  (`MountController.mount`, `ServeController.start`, and the reveal/archive services), so hiding a
  button is never the only defence. Pushing the check down to the `RcloneClient` seam itself, and
  feeding it from OS-native managed config through a Policy Engine, is the designed end state; see
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
