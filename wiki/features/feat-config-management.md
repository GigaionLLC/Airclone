---
type: "feature"
name: "Remote & Config Management"
status: "stable"
platforms: ["desktop", "mobile"]
dependencies: ["08-core-architecture", "11-validation-standards", "15-security"]
description: "Adding, editing, importing, replacing and removing remotes — and the guards that stand between an ordinary click and an unreadable crypt remote."
---

# 🔑 Remote & Config Management

Remotes live in rclone's own `rclone.conf`, not in an Airclone database — see the
[Persistence Index](../database/database-index.md). Everything here is therefore a controlled way of
editing *that* file, almost always through the engine's `config/*` RC methods.

The forms themselves are documented where they are used: the provider grid, the dynamic form
generated from `config/providers`, and the OAuth state machine are
[File Browser §3](feat-file-browser.md#3-add--configure-remotes-inline), with the schema/secret
details in [Core Architecture §5](../core/08-core-architecture.md). This page is about the surfaces
around them — the ones that create, overwrite or remove a remote in bulk.

---

## 1. Where these actions live

| Surface | Actions |
| :--- | :--- |
| **Sidebar** (a remote's ⋯ menu) | Test connection · Edit · Duplicate · Delete remote (a sidebar *location* offers "Remove from sidebar" instead — it is not in the config) |
| **+ Add remote** | The provider grid → dynamic form → `config/create` |
| **Settings → Config** | Import · Export · Import/Export QR · **Remove all remotes** · Restore a backup · **Use a different config file…** (desktop) · **Encrypt this config… / Change password… / Remove encryption…** (§6, desktop) · the opt-in **external config backup** (§7, Android) |

## 2. `config/create` overwrites. Nothing here may let that happen by accident

rclone's `config/create` on a name that **already exists silently REPLACES that remote**: exit 0, no
warning, no diff, nothing in the response that distinguishes it from creating a new one. On a `crypt`
remote that is data loss with no error message anywhere — the files stay exactly where they are, but
the new key cannot decrypt their names, so rclone skips them and the folder lists as empty. A real
user hit precisely this, and the app had not warned them. (The other half of that story is the pane
notice in [File Browser §6.1](feat-file-browser.md#61-empty-folder-is-a-claim-and-sometimes-a-false-one),
which now names the condition instead of saying "Empty folder".)

So every create path has to decide what to do about a taken name, and they do not all decide it the
same way:

| Path | Guard |
| :--- | :--- |
| **Add remote** wizard | Re-reads the live config (`existingRemoteNames` → `config/dump`) on submit and refuses a taken name, pointing at Edit instead |
| **Encrypt a remote** wizard | The same check, with a blunter message: re-creating a populated `crypt` remote under a new password or salt orphans everything already in it |
| **Duplicate** | Checks the sidebar's cached remote list, not a fresh dump |
| **Import merge** | A collision is renamed by default, or overwritten **only** when the user ticks the replace box (§3) |

Both wizard checks **fail closed**: if the existing names cannot be read at all, nothing is created
and the message says so. That is the point of
[`existingRemoteNames`](../../app/lib/src/state/remotes_provider.dart) returning `null` rather than an
empty set — an unreadable config must never read as "that name is free".

> **Verified against the code, and not uniform.** `existingRemoteNames` says every `config/create`
> caller must consult it; Duplicate instead compares against `remotesProvider`'s cached list and
> proceeds if that list is empty for any reason. It is the narrowest of the three paths (a name the
> user types over a source remote they can see), but it is not the same guard, and a future change
> that makes Duplicate reachable from somewhere colder should move it onto the shared check.

## 3. Import: preview first, rename by default, replace only on request

The import wizard ([`config_import_dialog.dart`](../../app/lib/src/ui/config_import_dialog.dart))
accepts an `rclone.conf`, a config dump, or an Airclone encrypted export; an encrypted source prompts
for its passphrase (envelope) or config password (rclone-native) first. **The preview step is
mandatory for the paths that reach it** — importing a file, and restoring the *external*
(shared-storage) backup, which re-enters the wizard with `initialBytes`
(`external_backup_dialogs.dart`). The in-app backup **ring** restore is a different path: it
replaces the active config from a snapshot Airclone itself wrote, so there is no untrusted file to
review. Nothing is written before the review on the paths that have one. Each incoming remote shows its type and its endpoint (host/url/account, never a
secret), so a swapped or poisoned file cannot silently re-point a remote at somebody else's server.

Two ways to finish, and they are different sizes of action:

- **Merge** brings the incoming remotes in beside yours. A name clash is renamed by default
  (`foo` → `foo-imported`, bumping `-2`, `-3`…), validated against rclone's remote-name charset, and
  checked so two decisions can never land on the same final name.
- **Merge, replacing the collisions** — the v0.7.6 addition. Merge's only answer to a clash used to
  be a rename, so re-importing a *corrected* config left `foo` and `foo-imported` side by side with
  the app still using the stale `foo`. The checkbox appears only when something actually collides,
  sits with the Merge button it modifies, is per-import and never remembered, names how many remotes
  it would land on, turns that button into "Replace + merge", marks each affected row *"Replaces your
  existing …"*, and only once ticked shows what it costs — including the crypt case in as many words.
  The outcome report then lists
  **Replaced** apart from **Merged**, because "imported 6 remotes" and "imported 6 remotes over 6 of
  yours" are not the same result and only one of them is worth re-reading.
- **Replace instead…** is the whole-config form, behind its own confirm step: it overwrites the
  entire active config with the imported remotes and restarts the engine, so every remote *not* in
  that file disappears until a restore. If the active config is rclone-encrypted the replacement is
  re-encrypted with the held password rather than written as plaintext, and the confirm says so.

Whichever path runs, **the config is snapshotted first** and a partial apply is reported honestly:
every remote is attempted independently, a `config/create` that errors *or* comes back wanting an
interactive answer counts as a failure, and the report names the ones that did not land.

**The mobile QR-scan review is deliberately narrower.** It mirrors the wizard's preview and rename
rules but offers **no** replace option — a phone-camera handoff is the wrong place to discover you
have overwritten a working remote. Verified in
[`scan_from_desktop_sheet.dart`](../../app/lib/src/ui/scan_from_desktop_sheet.dart), which has no
replace path at all.

## 4. Remove all remotes

The sidebar's per-remote delete is right for a mistake and hopeless for a clean slate: starting over
meant sixteen separate confirmations in a list where several names differed only in their last two
characters. [`remove_all_remotes.dart`](../../app/lib/src/ui/remove_all_remotes.dart) is the bulk
form, and it is deliberately the most guarded action in Settings:

- It **lists the remotes by name** in the confirm, and says up front that a backup is taken.
- A red button is not a decision, so the button stays **inert until "I understand this removes every
  remote" is ticked**.
- The config is **backed up first**, and if the live config file cannot be located there is no backup
  to be had — so it **refuses rather than proceeding**. Unrecoverable is not a state this action is
  allowed to reach.
- Each remote is deleted independently and the result reports both halves: how many went, and by name
  which ones could not.
- Both panes are cleared if they were showing a remote, since a pane pointing at a deleted remote
  would keep rendering its last listing and fail every action taken on it.

Files in the cloud are untouched. What is removed is credentials, paths and encryption settings — and
the confirm says plainly that for an encrypted remote those settings are what make its contents
readable.

One detail worth knowing when reading the code: the list you *confirm* comes from the sidebar's
remotes (minus the synthetic local peer, which is not in the config and cannot be deleted from it),
while the deletes iterate the **config file's own sections** from a fresh `config/dump`. If those two
ever disagree, the dump wins.

## 5. Backups are the substrate under all of it

Every mutating config path — import merge, import replace, restore, remove-all — snapshots the active
file into `<app support>/config-backups/rclone-<UTC stamp>.conf` before it touches anything, keeping
the ten newest. That backup is why the destructive options above are offerable at all, and
**Settings → Config → Restore a backup…** is the way back. The ring's own rules (POSIX-tightened
permissions, collision-suffixed stamps, restore-then-restart) live with
[`config_backups.dart`](../../app/lib/src/state/config_backups.dart) and
[Security](../core/15-security.md).

**One path deliberately does not snapshot: first-time encryption.** Its source is the plaintext
config, so a snapshot would leave a readable copy of every secret sitting in the ring — the exact
thing the user just asked to stop existing. **Change password** and **Remove encryption** both
snapshot as normal, because there the file being replaced was already encrypted. So of the three
encryption operations, encrypting is the one the ring cannot undo.

## 6. Config encryption is rclone's own, and it is CLI-only

The three operations in Settings → Config — **Encrypt this config…**, then **Change password…** and
**Remove encryption…** once it is encrypted — drive rclone's native `config encryption` subcommands
([`config_encryption.dart`](../../app/lib/src/state/config_encryption.dart)). They are not an
Airclone format: an encrypted `rclone.conf` is readable by the rclone CLI on any machine.

Two consequences worth stating plainly:

- **There is no RC method for this** (verified against `rc/list` on rclone v1.74), and setting
  `RCLONE_CONFIG_PASS` on a plaintext config does *not* encrypt it on save. The only mechanism is the
  binary subcommand — so the controls need a real rclone binary and are absent on the pure-FFI
  engine, which can *use* an encrypted config but not change its state.
- **The password never reaches a command line.** The new password is written to the child's stdin
  (twice, as rclone asks); the current one rides in `RCLONE_CONFIG_PASS` in the child's environment,
  so it is not in the process list.

This is a different thing from the **Airclone encrypted export** — an ACFG2 envelope over a config
you are moving between devices. Encrypting the *active* config is a state of the file rclone itself
reads; the envelope is a transport wrapper. The two are easy to confuse and do not substitute for
each other.

## 7. The Android copy that survives uninstall

On a phone the config lives in the app's private sandbox and the manifest sets
`allowBackup="false"` — both deliberate, so cloud credentials cannot ride along in an ADB or cloud
backup. The cost is that uninstalling is total loss of every remote.
[`external_config_backup.dart`](../../app/lib/src/state/external_config_backup.dart) is the opt-in
way out: one file under `<shared storage>/Airclone/`, which the OS does not delete with the app.

- **Off by default.** Nothing exists outside the sandbox until asked for.
- **Encrypted is the real answer** — an ACFG2 envelope under a passphrase, the same format as the
  encrypted export. Shared storage is readable by any app holding storage permission, which is what
  makes the passphrase the price of putting the file there at all.
- **Plaintext is available and never quiet**, behind a second confirmation that says what it means.
- Restoring it re-enters the import wizard with `initialBytes`, so it gets the same mandatory
  preview as any other untrusted file (§3).

Desktop needs none of this — its config already lives outside the app — and iOS has no equivalent
shared location. The files-side sibling, backing up *your data* rather than your remotes, is
[Backup & Restore](feat-backup.md).

---

**Related:** [File Browser](feat-file-browser.md) · [Validation Standards](../core/11-validation-standards.md) ·
[State & Context](../core/07-state-context.md) · [External Integrations](../core/10-external-integrations.md) ·
[Security](../core/15-security.md) · [Features Index](features-index.md)
