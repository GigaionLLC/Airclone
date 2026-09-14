# The release signing key — what a person has to do, once

**Status: not done.** Until this is, Airclone publishes a `SHA256SUMS` manifest with every release
and the app **will not install an update**, because it would have nothing to check a download
against. That is the intended half-built state, not a bug: the app offers its release page, exactly
as it does today.

This key is the one thing in the update system that an agent must not do. It is a private key that
proves a build came from this project, and it belongs to a person: created on a machine they
control, backed up somewhere they choose, and never committed, pasted into a chat, or held by CI in
any form but a secret.

---

## 1. Make the key

On a machine you trust, with [minisign](https://jedisct1.github.io/minisign/) installed
(`brew install minisign`, `apt install minisign`, `winget install jedisct1.minisign`):

```bash
minisign -G -p airclone.pub -s airclone.key
```

It asks for a password twice. Use one, and put it in your password manager — an unencrypted signing
key is a key that leaks with a laptop.

You now have two files:

| File | What it is | Where it goes |
|---|---|---|
| `airclone.key` | the private key, password-protected | GitHub **secret**, plus an offline backup |
| `airclone.pub` | the public key, one base64 line | GitHub **variable**, and into every build |

**Back up `airclone.key` offline** — a password manager attachment, a printed copy, an encrypted USB
stick, ideally two of those in different places. If it is lost, every future release needs a new key
and §5 becomes necessary. If it is *stolen*, someone can sign a build that Airclone will install
without complaint.

## 2. Give CI the private half

Repository → Settings → Secrets and variables → Actions → **Secrets**:

| Secret | Value |
|---|---|
| `MINISIGN_SECRET_KEY` | the entire contents of `airclone.key`, both lines |
| `MINISIGN_PASSWORD` | the password you just chose |

```bash
gh secret set MINISIGN_SECRET_KEY --repo GigaionLLC/Airclone < airclone.key
gh secret set MINISIGN_PASSWORD  --repo GigaionLLC/Airclone   # prompts, nothing on screen
```

The `checksums` job in `release.yml` reads both. With them absent it publishes the manifest unsigned
and says so in the log; with them present it signs, puts the release tag in the signed comment, and
shreds the key file before the step ends.

## 3. Give the app the public half

The app needs the key **at build time**, so a released binary carries the key it trusts. Line 2 of
`airclone.pub` is the value — the base64, not the comment above it:

```bash
tail -1 airclone.pub
# RWQf6LRCGwopeJVOTZSLDPAjHt6kQrSL2eKxlAcXRLVN2QdgLyNpEYGK

gh variable set AIRCLONE_UPDATE_PUBKEY --repo GigaionLLC/Airclone --body "$(tail -1 airclone.pub)"
```

Then the platform build steps in `release.yml` need to pass it:

```
--dart-define=AIRCLONE_UPDATE_PUBKEY=${{ vars.AIRCLONE_UPDATE_PUBKEY }}
```

Until that define is added to the build commands, `kCanVerifyUpdates` is false and no build offers
to install anything — which is why this step and step 2 should happen together.

## 4. Check it worked

Tag a release, then:

```bash
gh release download vX.Y.Z --pattern 'SHA256SUMS*'
minisign -Vm SHA256SUMS -p airclone.pub
```

It should print `Signature and comment signature verified` and a trusted comment naming that tag. If
it verifies here, it verifies in the app: the same four-line format, the same two signatures, and
`app/test/minisign_test.dart` holds the Dart side to a fixture that the real `minisign` binary checks
in CI.

## 5. If the key is ever lost or stolen

`update_trust.dart` accepts **two** keys, which exists entirely for this:

1. Make a new key (§1).
2. Set `AIRCLONE_UPDATE_PUBKEY_NEXT` to the NEW public key and leave `AIRCLONE_UPDATE_PUBKEY` on the
   old one. Release once. Builds from that release trust both.
3. Once enough people are past that release, swap: the new key becomes `AIRCLONE_UPDATE_PUBKEY` and
   `MINISIGN_SECRET_KEY` becomes the new private key. Clear `..._NEXT`.

Anyone still running a build older than step 2 will stop being offered updates and keep seeing the
release page. That is the safe failure, and it is why rotation is worth doing before it is urgent.

**If the key was stolen rather than lost**, rotation is not enough on its own: say so publicly, in
the release notes of the first release signed with the new key. A signature is a claim about who
made a file, and a claim that might be false is worth retracting out loud.

---

## Why minisign and not something else

Considered and rejected, in `dev/plans/self-update-plan.md` §1: Sparkle/WinSparkle (no Linux, and
its Windows key sits in a bare file), electron-updater (verifies a code signature on two platforms
and a checksum from an unsigned feed on the third), Velopack (its own maintainer describes the trust
model as a hash from an unsigned feed), and signing each artifact separately (nine signatures where
one manifest does the same job and binds filenames to hashes as well).

GPG would also work and is worse to hold: a keyring, a web of trust and a subkey story, to do what
64 bytes of Ed25519 do here.
