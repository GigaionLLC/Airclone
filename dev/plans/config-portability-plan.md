---
type: "plan"
name: "Config Portability & Unlock Plan"
status: "planned"
description: "Config path control, import/export (encrypted by default), desktop→phone QR/LAN handoff, and biometric unlock — the serverless profile-sync on-ramp."
---

# 🔑 Config Portability & Unlock

User ask (2026-07-09, expanded): config-path control, import/export (conf/JSON), encrypted-config
support with an OS-vault/biometric unlock, and QR transfer desktop→phone. This is the on-ramp to the
serverless [profile-sync vision](cross-platform-architecture-plan.md) — everything here works with
zero servers and zero Airclone accounts.

## Already in place (don't rebuild)

- Encrypted rclone configs prompt on launch (`EnginePhase.needsPassword`, alpha-era).
- **OS-vault opt-in** (this week): `ConfigPasswordVault` (flutter_secure_storage → DPAPI/Keychain/
  Secret Service) + silent vault unlock before the password gate.
- At-rest AES-256-GCM crypto utilities (`cache_crypto.dart`) — reuse for encrypted exports.
- Android config already runs at a known private path via `--config`; desktop uses rclone's default.

## The batch (in build order)

### 1. Config section in Settings (visibility + path override)
Show the ACTIVE config: resolved path (desktop: rclone default or override; Android: app-private),
encrypted?, remote count, last-modified. Actions: **Open containing folder** (desktop), **Use a
different config file…** (file picker → validate by running `rclone config dump --config <f>` via a
short-lived subprocess — prompts for that file's password if encrypted → persist override → engine
restart), **Back to default**. Engine spawn honors the override via `--config` on all platforms
(today `_platformSetup` only sets it on Android).

### 2. Automatic config backups (trust substrate)
Before ANY mutating operation this plan introduces (import-merge, replace, path switch): copy the
active config to `<appSupport>/config-backups/rclone-<utc-stamp>.conf`, keep the last 10. A
"Restore a backup…" row lists them. Quiet, always-on, no setting.

### 3. Import wizard (file → preview → merge/replace)
Sources, sniffed automatically: rclone.conf INI · `rclone config dump` JSON · our encrypted
`.airclone-config` (prompts passphrase) · a password-encrypted rclone.conf (prompts that password,
decrypts via `rclone config dump --config` subprocess).
Then a **preview step** — remote names + types, collision badges — then apply:
- **Merge** (default): `config/create` per remote through the existing RC seam; collisions get
  `-imported` suffix rename (user-editable in preview).
- **Replace**: auto-backup → overwrite file → engine restart. Destructive-confirm styled like the
  sync/crypt guards.

### 4. Export (scoped; encrypted by default; rclone-native encryption preserved)
**Scope picker first**: All remotes (default) or a checklist of specific remotes. Scoped exports
compute the **dependency closure** — a `crypt`/`alias`/`chunker`-style remote whose `remote =`
points at another remote auto-includes its base (shown in the preview: "`drive-secret` needs
`Google-Drive` — included"), otherwise the export would be broken on arrival.

Three envelopes:
- **Airclone encrypted export** (default): passphrase → AES-256-GCM envelope (reuse cache_crypto
  primitives; versioned header magic `ACFG1`) → `airclone-config.enc`. Import (step 3) understands it.
- **rclone-native encrypted config**: stays first-class — a full export of an already-encrypted
  config is a raw copy (still opens with plain `rclone` + its password anywhere); a SCOPED export
  can be re-encrypted rclone-natively by driving `rclone config encryption set` on the temp file via
  stdin. Use this when the target is the rclone CLI rather than another Airclone.
- **Plaintext export** (INI, or JSON via `config/dump`): behind an explicit destructive-style
  confirm — *"this file contains the keys to your cloud accounts (OAuth tokens, secrets) in
  recoverable form."*

The QR/LAN handoff (step 5) gets the same scope picker — sending a single remote to the phone is
the everyday case; the pairing-code channel is unchanged. And to be explicit: none of this replaces
rclone's own config encryption for the ACTIVE config — the launch password gate, vault opt-in, and
(step 6) biometric release all keep working against a natively-encrypted rclone.conf.

### 5. Send to phone (QR/LAN handoff with pairing code) — the flagship
A whole config does NOT fit in a QR (OAuth tokens; QR v40 ≈ 2.9 KB), and a key embedded in the QR
dies to a single photo/screen-share capture. Design (v2, pairing-code model — user-proposed
direction, hardened):

**Two-channel split**: the QR (desktop screen) and the pairing code (phone screen) are never visible
on the same device. An attacker needs both.

1. Desktop (Settings → "Send to phone…"): generate a random 128-bit session salt; start a one-shot
   LAN HTTP endpoint (tiny Dart HttpServer, 5-min TTL, dies after one successful transfer); render a
   QR of `airclone-cfg:v2|<lan-url>|<base45 salt>` — **no key, no payload in the QR**.
2. Phone (Import from QR): scan → connect → phone GENERATES and DISPLAYS a short pairing code
   (6–8 chars, Crockford base32: uppercase, no 0/O/1/I ambiguity) — e.g. `K7WX-4PMB`.
3. User types the code on the DESKTOP prompt ("enter the code your phone is showing"). Both sides
   derive `key = HKDF(salt ∥ code)`; the config blob is AES-256-GCM-encrypted under it.
4. **QR-pinned TLS 1.3 channel** (v3 — the load-bearing fix from the 2026-07-09 security review):
   the desktop generates an ephemeral self-signed cert per session; its SHA-256 fingerprint rides in
   the QR next to the salt, and the phone connects over TLS pinning exactly that fingerprint.
   WITHOUT this, a QR photo (salt) + cleartext wire = an offline brute-force oracle on the short
   code (via the HMAC — or the GCM tag itself), i.e. the exact shoulder-surf threat the two-channel
   split advertises against. With it, sniffers see nothing and MITM fails the pin; the pairing code
   is then honestly just anti-race authorization.
5. **Authenticate-before-serve** (inside the TLS channel): per-CONNECTION random challenge; the
   ciphertext is delivered ONLY on the connection that answered its own challenge (no bearer
   tokens, no global "released" flag). Failed proofs are counted GLOBALLY per session — 3 total
   kills it (per-connection counting would void the cap via parallel connections). Persistent
   lockouts surface as "someone may be interfering on your network", not just "wrong code".
6. Phone decrypts, hash-checks, and lands in the SAME preview/merge wizard as step 3.

- Codes/salts/keys are per-session, never persisted, never logged, zeroized after use. The salt
  (and anything derived from it) NEVER travels on the wire — correlation uses a separate random
  session-id. Server binds to the specific advertised LAN interface (never 0.0.0.0), rejects
  non-private source addresses, caps concurrent connections, and tears down on TTL, first success,
  lockout, or app background/exit. Phone-side QR parsing enforces `airclone-cfg:v2`, a
  private/link-local URL host, exact salt length, and the cert fingerprint. HMAC comparisons are
  constant-time. If the pinned-TLS channel is ever dropped in favor of the bare scheme, the design
  REQUIRES Argon2id (m=256MiB,t=3) over (salt ∥ code) and ≥8-char codes — but prefer keeping TLS.
- The preview/merge review stays MANDATORY on QR imports and shows each remote's type + endpoint
  (a swapped/overlay QR must not be able to silently poison a remote's target).
- **Offline fallback**: per-remote compact QR (single remote's section fits QR when non-OAuth),
  passphrase-wrapped, same scanner path.
- Failure honesty: different networks → show hostname + IP variants; timeout says "phone never
  connected", wrong-code lockout says which side to restart.
Deps: `qr_flutter` (render), `mobile_scanner` (scan; camera permission requested in-flow).
Encoding: base45 for QR fields (QR alphanumeric-mode native), Crockford base32 for the human code.

### 6. Biometric unlock (phone-first)
`local_auth`: opt-in **"Unlock with fingerprint/face"** (Android/iOS; Windows Hello later via
local_auth_windows). Semantics: the config password stays in the vault (step already shipped);
biometric success *releases* it at startup instead of showing the typing gate. Falls back to the
password prompt on failure/lockout. No new crypto — the OS keystore already binds the secret; this
is an unlock-UX gate, honestly labeled ("protects against casual access on an unlocked device, not
against someone with your device PIN").

## Sequencing & risks

Build 1→2→3→4 as one reviewed batch (they share the config-IO seam); 5 and 6 as a second batch
(new deps, camera permission, mobile testing on the emulator rig). Risks to watch in review:
plaintext secrets ending up in logs/temp files (forbid; encrypted temp only), the one-shot server
binding scope (LAN iface only, never 0.0.0.0 without TTL+single-use), collision-rename correctness,
and `--config` override interaction with the headless runner (it must honor the same override).

## Deliberately not doing

- QR-animating the full config (multi-part QR) — LAN handoff covers it with less failure surface.
- Cloud-relay transfer — violates the no-phone-home principle; the user's own LAN/remote is the
  channel (profile-sync's encrypted-blob-on-own-remote remains the roadmap for cross-network sync).
