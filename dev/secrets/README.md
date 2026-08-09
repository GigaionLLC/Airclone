# 🔐 Developer profile — local account values

Where one developer's real account identifiers live so tooling and AI assistants can use them,
without any of it entering this public repository.

**When to read this:** you are setting up this repo on a new machine, you need a value an agent
says is "in the developer profile", you are syncing CI variables, or you cloned Airclone and want
your own store/signing identities wired up.

---

## ⚠️ These values belong to one builder

`dev-profile.env` describes the **Gigaion, LLC** accounts — the publisher identity, signing profile
and store registrations used to ship the official Airclone builds. **It is not part of the product
and it is not yours.**

If you cloned this repo, you will not have that file, and nothing here will produce it. Copy the
template and fill in your own values:

```bash
cp dev/secrets/dev-profile.example.env dev/secrets/dev-profile.env
```

Every key you leave blank simply means "I do not have that lane set up". No script may assume a
value is present — the sync helper skips blanks by design. You can build, run and test Airclone
with an entirely empty profile; these values are needed only for **signing, store submission and
release hosting**.

---

## 📁 What is in this directory

| File | Committed? | What it is |
| :--- | :--- | :--- |
| [`dev-profile.example.env`](dev-profile.example.env) | ✅ yes | The schema. Every key, what it means, whether it is PUBLIC / PRIVATE / SECRET, and how it reaches CI. **Never put a real value in it.** |
| `dev-profile.env` | 🚫 never | Your real values. The file tooling and agents actually read. |
| `.passphrase` | 🚫 never | A 32-character random passphrase (192 bits, `openssl rand -base64 24`) that encrypts the backup below. |
| `dev-profile.env.enc` | 🚫 never | AES-256-CBC + PBKDF2 encryption of `dev-profile.env`, for **private** backup or transfer between your own machines. |

`.gitignore` denies **everything** in this directory and then re-allows only this README and the
example file. That is default-deny on purpose: a new file dropped here is ignored automatically, so
you cannot leak a value by inventing a filename. Verify at any time:

```bash
git check-ignore -v dev/secrets/dev-profile.env
```

> **Note on the existing `.env` rules.** The repo-root `.gitignore` already had `.env` and `.env.*`,
> but those only match a *dotfile* basename — `dev-profile.env` was **not** covered by them. The
> `dev/secrets/*` rule is what actually protects this directory.

---

## 🤖 How AI assistants should use this

An agent working in this repo may **read `dev-profile.env`** when it genuinely needs a real value —
setting a CI variable, filling in a Partner Center field, constructing a release URL. Two rules:

1. **Never copy a PRIVATE or SECRET value into a committed file**, a commit message, a doc, a code
   comment, or a store listing. Reference it by key name instead: write "`MSIX_PUBLISHER`", not the
   GUID. This is the same rule as
   [17-docs-blueprint.md](../../wiki/core/17-docs-blueprint.md) §6, which is what keeps the public
   repo clean.
2. **Never print a SECRET into terminal output or a shared transcript.** Values marked SECRET are
   credentials. If you must prove one is correct, print a hash or a length, not the value.

If a value is blank, say so and ask — do not guess. A wrong identifier is worse than a missing one
because tooling will act on it. That failure has already cost this project real time: the Microsoft
Store rejected v0.6.0 four times because placeholder identity values had been left in the build
config, and each upload only revealed one error at a time.

---

## 🔄 Syncing to GitHub Actions

CI does not read this file — it reads GitHub **variables** and **secrets**. The profile is the
source of truth you sync *from*. The example file marks each key `sync -> variable` or
`sync -> secret`.

Variables are readable back through the API, so they are for identifiers CI needs but which are not
credentials. Secrets are write-only — once set, nobody (including you) can read them back, which is
why the profile keeps its own copy.

```bash
gh variable set MSIX_IDENTITY_NAME --repo GigaionLLC/Airclone --body "<value>"
gh secret   set STORE_CLIENT_SECRET --repo GigaionLLC/Airclone --body "<value>"
```

Org-wide values (the Azure signing lane) are set at the organisation with
`--org GigaionLLC --visibility selected --repos Airclone`. Which keys currently live where is
recorded in [`../windows-signing-and-store.md`](../windows-signing-and-store.md) §2e and
[`../README.md`](../README.md).

To see what is set today (values shown for variables, never for secrets):

```bash
gh variable list --repo GigaionLLC/Airclone
```

---

## 💾 Backup and transfer

`dev-profile.env.enc` lets you move the profile between **your own** machines without exposing it:

```bash
# encrypt (after editing dev-profile.env)
openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
  -in dev/secrets/dev-profile.env -out dev/secrets/dev-profile.env.enc \
  -pass file:dev/secrets/.passphrase

# decrypt on the other machine (needs .passphrase, transferred separately)
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in dev/secrets/dev-profile.env.enc -out dev/secrets/dev-profile.env \
  -pass file:dev/secrets/.passphrase
```

**Move the passphrase by a different channel than the ciphertext** — a password manager, not the
same drive or the same message. Sending both together provides no protection at all.

> **Do not commit the encrypted file to this public repo, even though it is encrypted.** Public
> ciphertext is permanently harvestable and can be attacked offline forever; the only thing standing
> between it and the plaintext is one passphrase that can never be un-leaked. The `.gitignore`
> blocks it. Keep it in private storage.

### Rotating the passphrase

```bash
openssl rand -base64 24 | tr -d '\r\n' > dev/secrets/.passphrase   # note: -d '\r\n', not '\n'
```

Then re-encrypt. Use `tr -d '\r\n'`: on Windows a lone `\n` strip leaves a carriage return in the
file, producing a passphrase that silently does not match the one you think you have.

Rotating the *passphrase* does not rotate the *credentials*. If a SECRET value itself leaked, rotate
it at its source (Partner Center, Entra, Apple, Google Play) and re-run the sync.

---

## 🔗 Related

- [`dev-profile.example.env`](dev-profile.example.env) — the schema and every key's meaning.
- [`../README.md`](../README.md) — the operational hub: releases, CI workflows, store lanes.
- [`../windows-signing-and-store.md`](../windows-signing-and-store.md) — where most of these values
  are actually used, and the one-time setup for each.
- [`../../docs/store/README.md`](../../docs/store/README.md) — per-store submission index.
- [`../../wiki/core/17-docs-blueprint.md`](../../wiki/core/17-docs-blueprint.md) §6 — what must never
  appear in a committed file.
- [`../../wiki/core/15-security.md`](../../wiki/core/15-security.md) — how the *application* handles
  the user's secrets, which is a separate concern from this file.
