# 🔒 Encrypted notes vault

Working notes that belong in this repository's **history** but not in public view — store
account state, pricing and positioning, unreleased planning, anything commercially
sensitive.

`vault.enc` **is committed.** The decrypted `notes/` directory is gitignored, as is the
passphrase.

The point is that gitignoring the notes outright would mean they exist on one machine and
vanish with it. This way they are versioned, backed up and reviewable — just not readable
by anyone who clones Airclone.

## Use

```bash
python tool/vault.py status     # what is in the vault, WITHOUT decrypting
python tool/vault.py unlock     # vault.enc -> notes/
python tool/vault.py lock       # notes/ -> vault.enc, then commit vault.enc
```

Edit under `notes/`, run `lock`, commit `vault.enc`. The plaintext never enters git.

Needs `cryptography`; everything else is stdlib:

```bash
pip install cryptography
```

## The passphrase

`python tool/vault.py init` generates a 256-bit passphrase into
`dev/secrets/.vault-passphrase` and refuses to overwrite an existing one, because doing so
would make the current vault permanently unreadable. `AIRCLONE_VAULT_PASSPHRASE` in the
environment takes precedence, which is how CI would read it if it ever needs to.

**Keep a copy in a password manager, and share it with collaborators the same way.** There
is no recovery path — any recovery path would also be a bypass.

## ⚠️ What must NOT go in here

Anything that must never exist in git: **credentials, signing keys, API private keys,
customer data.** Those belong in [`../secrets/`](../secrets/README.md), which is gitignored
and never committed in any form, or in a secret manager.

This repository is **public**. A vault in a public repository is only as strong as its
passphrase, and a leaked passphrase exposes **every historical revision**, not just the
current one — you cannot un-publish ciphertext, and an offline attacker gets unlimited
attempts forever.

That is the whole reason the two directories exist and are different:

| | `dev/vault/` | `dev/secrets/` |
| :--- | :--- | :--- |
| Holds | sensitive **notes** | **credentials** and account identifiers |
| Committed? | ✅ ciphertext only (`vault.enc`) | 🚫 never, in any form — not even encrypted |
| If the passphrase leaks | notes are exposed, including history | n/a — nothing was ever pushed |
| Rotate by | changing the passphrase and re-locking | rotating the credential **at its source** |

If you are unsure which a given file is, ask whether its exposure would be *embarrassing*
or *exploitable*. Embarrassing goes in the vault. Exploitable goes in `dev/secrets/`.

## Rules that matter

- **Never `git add` anything under `notes/`.** `.gitignore` only governs *untracked* files,
  so `git mv`-ing an already-tracked file into `notes/` stages the **plaintext** as a
  rename. Check `git status` before committing whenever files move in.
- **Re-lock before committing.** An unlocked edit that is never re-locked is simply lost —
  the commit will not contain it. `status` will tell you if `notes/` is currently unlocked.
- **No passphrase, no access.** If the passphrase is absent, say so rather than guessing at
  the contents.
- **A failed unlock means "do not trust this file".** The GCM tag is verified, so a modified
  `vault.enc` fails loudly instead of producing plausible-looking garbage. AES-GCM cannot
  tell you whether the cause was a wrong passphrase or tampering, and treating both the same
  way is correct.

## Crypto

scrypt (N=2^16, r=8, p=1) derives a 256-bit key from the passphrase, then **AES-256-GCM**
with a fresh random salt and IV on every lock. Layout is
`"ACVAULT1" || salt(16) || iv(12) || tag(16) || ciphertext`; the header is authenticated
implicitly, because a changed salt or IV yields the wrong key or nonce and the tag check
fails.

The work factor is deliberately high — roughly 64 MiB and a visible fraction of a second per
unlock. The blob is public, so the passphrase is the only barrier.

The plaintext is a JSON manifest of `{path: base64}` plus a `lockedAt` timestamp, so the
vault holds a directory tree rather than a single document. Paths are validated on unlock; a
crafted manifest cannot write outside `notes/`.

## What is in the vault today

- `apple-appstore-setup-record.md` — the as-built Apple App Store / App Store Connect
  configuration: every choice made, the reasoning, and the console URLs. Its public,
  value-free counterpart is [`../plans/apple-appstore-plan.md`](../plans/apple-appstore-plan.md).

## 🔗 Related

- [`../secrets/README.md`](../secrets/README.md) — credentials and the developer profile.
- [`../README.md`](../README.md) — the operational hub.
- [`../../wiki/core/17-docs-blueprint.md`](../../wiki/core/17-docs-blueprint.md) §6 — what must
  never appear in a committed file.
