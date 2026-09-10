---
type: "feature"
name: "Backup & Restore"
status: "partial"
platforms: ["desktop"]
dependencies: ["07-state-context", "11-validation-standards", "15-security"]
description: "A folder copied somewhere safe on a schedule, with old versions kept and prunable — and a restore that is just the file browser, so it inherits every guard rather than growing its own."
---

# 🗄️ Backup & Restore

A **backup** is a saved task with its dangerous options taken away.

That is the whole design, and it is deliberate: there is no parallel backup
engine, no manifest format, and no second scheduler. A backup runs through the
same [scheduler](feat-scheduling.md), lands in the same run history, and is
covered by the same safety guards — which means one place for a bug to live
instead of two.

> **Do not confuse this with config backup.** `state/external_config_backup.dart`
> is an opt-in encrypted copy of **`rclone.conf`** so a reinstall does not cost
> you every remote. That is "back up your remotes". This page is "back up your
> files".

---

## 1. What makes it a backup rather than a transfer

Three constraints, in `state/task_kind.dart`, each closing a specific way a
backup stops being one:

| Constraint | Why |
| :--- | :--- |
| **`copy`, never `sync` or `move`** | A sync deletes at the destination to match the source — so a backup that syncs deletes your history the moment the source loses a file, which is exactly when you need it. A move deletes the original, so a "backup" that moves is not one at all. |
| **`keepReplaced`** | An overwritten file is renamed aside with a `.replaced` marker rather than lost. This is what makes a version history exist to restore *from*. |
| **Never a dry run** | The worst failure available: it looks like it worked every night. |

They are applied when the task is created **and enforced again when it runs**, so
a task edited through the raw advanced dialog cannot run as something other than
what its name says. A test feeds `buildBackupTask` a hostile base carrying
`sync` + `dryRun` + `keepReplaced: false` and asserts none of it survives.

`TaskKind` is a discriminator — `{transfer, backup, photos}` — defaulting to
`transfer` and omitted from JSON at that value, so every task saved before this
existed round-trips byte-identical. An unknown kind from a newer build degrades
to `transfer` rather than throwing, because throwing would lose the whole task
list on a downgrade.

## 2. Where a backup lands

```
<destination>/Airclone/Backups/<device>/<source folder>
```

The **device** segment because two machines backing up to one remote would
otherwise merge — and the first sign of that is a restore putting a laptop's
files on a phone. The **source folder** segment so several folders from one
machine stay apart; it is the folder's own name, so backing up
`D:\Projects\Airclone` gives you a folder called `Airclone` rather than one named
after the whole path.

A device name is user-controlled and ends up in a path, so it is sanitised. A
name carrying no letters or digits at all — `///` sanitises to `---` — falls back
to `device`, because a folder that identifies nothing is no better than an empty
segment.

**Photo backups skip the source-folder segment** and use `Airclone/Photos/<device>`.
Several source folders mirror into one per-device tree, which is what "mirror the
source structure" means when the source is a *set* rather than one path.

## 3. Setting one up

**Settings → Automation → Back up a folder.** Three answers — what, where, how
often — and deliberately **not** the advanced transfer dialog. Mode, dry-run and
version-keeping are not reachable from it at all.

It is **not advanced-gated**. "Back up a folder" is a concept an ordinary user
has; "a saved transfer task with a `TransferOptions` payload" is not, and that
split is the whole reason the wizard exists separately from the task editor.

Two details worth knowing:

- **It shows you the destination before creating anything**, so you do not have
  to go browsing afterwards to find out where your files went.
- **Weekly is not offered.** A backup that runs once a week is six days stale
  when you need it. The raw task editor is still there for someone who genuinely
  wants one.

## 4. Versions, and pruning them

An overwritten file is kept beside the new one with a `.replaced` marker.
`report.pdf` becomes `report.replaced.pdf` — or `report.pdf.replaced` on a config
written by an older build; both shapes are recognised.

**Retention defaults to 30 days and is configurable** (0, 7, 14, 30, 60, 90 or
365). Zero means "keep nothing beyond the current file", which is a legitimate
choice for someone short on space. There is deliberately **no "forever"**: a
version history that only grows is a bill nobody agreed to.

### 4.1 The prune is the most destructive thing this app does

It is a delete loop over a remote, so it is built the way that deserves. The
decision about *what* to delete is pure, separate and tested without a network
(`state/backup_retention.dart`); the executor only lists, asks and deletes
(`state/backup_prune.dart`).

The bias is explicit and runs through every rule: **a false negative costs disk
space, a false positive destroys data**, so anything ambiguous is kept.

| Rule | What it prevents |
| :--- | :--- |
| The `.replaced` marker must be a whole dot-separated segment, and never the first one | `my.replacedparts.txt` is not a version, and a file someone simply named `replaced.txt` is theirs |
| A version is kept when its **live file no longer exists** | That version is then the only copy left — the current file was deleted at the source and the backup carried it forward — and is exactly what someone comes looking for |
| A version with **no modification time** is kept | Unknown age is not "old enough"; a backend that omits `ModTime` must not cost you your history |
| A recursive listing is **grouped by folder first** | Otherwise `a/report.pdf` vouches for `b/report.replaced.pdf`, and a version in a different folder is judged redundant and deleted |
| **Dry run by default** | Every caller opts in, and the UI can show what is about to happen using exactly the code that will do it |
| Over `kMaxPrunePerPass` (500) it **refuses entirely** | A pass that large is more likely a bug than a real backlog; truncating would destroy data while hiding the reason |
| A **failed listing deletes nothing** | Not knowing what is there is the one state in which deleting is indefensible |

Each of those was confirmed by breaking it deliberately and watching a test go
red — see `test/backup_retention_test.dart` and `test/backup_prune_test.dart`.

## 5. Restore

**A backup destination is an ordinary remote folder.** So restoring is opening
that folder in a pane and copying out of it — through the conflict preflight that
every transfer got in v0.7.6.

That inheritance is the point rather than a shortcut. Restoring *over* live files
is a write and it must ask before overwriting; a bespoke restore path would have
had to grow its own version of that guard, and would have grown it later and
worse.

`state/backup_restore.dart` holds what is left: splitting `remote:path` (on the
**first** colon — a path may legitimately contain one), finding the remote a task
writes to and saying so plainly when it has since been deleted, and grouping a
folder listing into restore points so a wall of `.replaced` files reads as
"report.pdf, and 2 older versions".

Restore is offered for backups and photo backups only. A plain transfer's
destination has no version history and nothing promises the source is
recoverable, so offering "restore" there would claim something untrue.

## 6. What this is not, yet

- **No scheduled prune.** The prune exists and is safe; nothing runs it on a
  timer yet, so retention is currently a thing you invoke rather than a thing
  that happens.
- **No "versions are using X GB" figure in the UI.** `versionBytes()` computes
  it; nothing displays it.
- **iOS photo backup.** Assets there are not files — they must be exported
  through `PHAssetResourceManager` first, doubling storage during a backup. Out
  of scope for v0.8.

## 7. Where the code is

| Piece | File |
| :--- | :--- |
| `TaskKind`, the three constraints, device folder naming | `state/task_kind.dart` |
| Destination convention, task construction | `state/backup_task.dart` |
| Version recognition, retention window, prune decision | `state/backup_retention.dart` |
| Prune executor (lists, asks, deletes) | `state/backup_prune.dart` |
| Restore addressing and grouping | `state/backup_restore.dart` |
| The wizard | `ui/backup_wizard.dart` |

Tests: `test/task_kind_test.dart`, `test/backup_task_test.dart`,
`test/backup_retention_test.dart`, `test/backup_prune_test.dart`,
`test/backup_restore_test.dart`.
