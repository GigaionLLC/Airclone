---
type: "core"
name: "Utility Standards"
status: "stable"
dependencies: ["08-core-architecture", "11-validation-standards"]
description: "Inventory of the shared formatters, path helpers and small pure functions that already exist, with their precision rules — so agents reuse rather than reinvent."
---

# 🧰 Utility Standards

The small shared helpers Airclone already has — byte/rate/duration formatting, path joining, sorting,
cache keys — and the precision rules they encode.

**When to read this:** you are about to write a `String` formatter, a path join, a size or duration
renderer, a comparator, or any other "tiny helper". Check here first; most of them exist.

---

## 1. 🗂️ Where helpers live

There is **no `lib/src/util/` directory**. Helpers live next to their first consumer and get promoted
to a shared file only when a second consumer appears. The current inventory:

| File | Owns |
| :--- | :--- |
| [ui/format.dart](../../app/lib/src/ui/format.dart) | `humanSize`, `relativeTime` — the shared display formatters |
| [ui/pane_drag.dart](../../app/lib/src/ui/pane_drag.dart) | `joinPath`, the `PaneDragData` drag payload |
| [state/file_ops.dart](../../app/lib/src/state/file_ops.dart) | `join` (same implementation as `joinPath`), `CompareResult` |
| [state/name_conflict.dart](../../app/lib/src/state/name_conflict.dart) | `planPaste`, `uniqueName` |
| [state/remote_summary.dart](../../app/lib/src/state/remote_summary.dart) | `remoteEndpointSummary` |
| [state/archive_command.dart](../../app/lib/src/state/archive_command.dart) | `escapeRcloneGlob`, `archiveFormatForName`, `looksLikeArchive`, `defaultArchiveName`, `buildArchiveCommand` |
| [ui/file_icon.dart](../../app/lib/src/ui/file_icon.dart) | `kindOf`, `isImageThumbnailable`, `isVideoThumbnailable`, `isThumbnailable`, `isGalleryMedia`, `iconFor`, `iconColorFor` |
| [ui/column_header.dart](../../app/lib/src/ui/column_header.dart) | `compareRcloneFiles`, `SortKey` |
| [state/local_locations.dart](../../app/lib/src/state/local_locations.dart) | `fsRoot`, `buildDefaultUserFolders` |
| [state/cloud_placeholder.dart](../../app/lib/src/state/cloud_placeholder.dart) | `localAbsolutePath`, `isOnlineOnlyPlaceholder`, `wouldHydrateOnRead` |
| [state/engine_flags.dart](../../app/lib/src/state/engine_flags.dart) | `parseEngineFlags`, `hasEngineFlag`, `toggleEngineFlag` |
| [state/console/console_command.dart](../../app/lib/src/state/console/console_command.dart) | `flagName` |
| [state/console/console_rc_translate.dart](../../app/lib/src/state/console/console_rc_translate.dart) | `splitFsRemote` |
| [state/config_io.dart](../../app/lib/src/state/config_io.dart) | `remotePrefix`, `remoteDependencies`, `dependencyClosure`, `parseIni`, `serializeIni` |
| [state/thumbnail_service.dart](../../app/lib/src/state/thumbnail_service.dart) · [state/folder_preview.dart](../../app/lib/src/state/folder_preview.dart) | `thumbCacheKey`, `folderThumbCacheKey` |
| [state/task_schedule.dart](../../app/lib/src/state/task_schedule.dart) · [state/bw_schedule.dart](../../app/lib/src/state/bw_schedule.dart) | `TaskSchedule.describe`, `isDue`, `nextRun`, `activeRate` |

---

## 2. 📏 Bytes and rates — the precision rules

**Canonical:** [`humanSize(int bytes)`](../../app/lib/src/ui/format.dart#L3).

| Input | Output | Rule |
| :--- | :--- | :--- |
| `< 0` | `—` | negative means "unknown" (dirs, unfetched sizes) |
| `< 1024` | `1023 B` | exact integer, no decimal |
| otherwise | `9.8 MB`, `12 MB`, `1.4 TB` | binary steps of **1024** with decimal-style unit labels (`KB MB GB TB PB`) — deliberate, matches how the rest of the app and rclone read |
| ≥ 10 in the chosen unit | `12 MB` | **0 decimals** |
| `< 10` in the chosen unit | `9.8 MB` | **1 decimal** |

**Rates** are `humanSize` plus a suffix: `'${humanSize(bps.round())}/s'`
([jobs_panel.dart#L352](../../app/lib/src/ui/jobs_panel.dart#L352)). **Totals** with a known target
render as `done / total` ([jobs_panel.dart#L346](../../app/lib/src/ui/jobs_panel.dart#L346)).

### Known duplicates — do not add a fourth

| Copy | File | How it differs |
| :--- | :--- | :--- |
| `_size` / `_rate` | [stats_panel.dart#L143](../../app/lib/src/ui/stats_panel.dart#L143) | always 1 decimal (no ≥10 rule); units stop at TB |
| `_humanSpeed` | [android_transfer_service.dart#L73](../../app/lib/src/state/android_transfer_service.dart#L73) | formats the rate itself with `B/s … GB/s` units, for the Android foreground-service notification (same ≥10 rounding rule as `humanSize`) |

New UI uses `humanSize`. If you need a rate string, write `'${humanSize(x)}/s'` rather than adding
another private size formatter.

---

## 3. ⏱️ Durations

All duration formatters are currently private to their file. Reuse the shape, not a copy-paste:

| Helper | Output | File |
| :--- | :--- | :--- |
| `_fmt(Duration)` | `m:ss`, or `h:mm:ss` past an hour; negative-aware (`-0:05` for remaining time) | [media_preview.dart#L510](../../app/lib/src/ui/media_preview.dart#L510) |
| `_fmtRunDuration(Duration)` | `1.2s` / `3m 05s` / `1h 04m` — a measured wall-clock run | [tasks_panel.dart#L708](../../app/lib/src/ui/tasks_panel.dart#L708) |
| `_eta(double seconds)` | `45s` / `3m 20s` / `1h 4m` — a live estimate, not zero-padded | [stats_panel.dart#L157](../../app/lib/src/ui/stats_panel.dart#L157) |

Conventions these encode:

- **Units cut over at the natural boundary** — seconds below a minute, `Xm Ys` below an hour, `Xh Ym`
  above; never a bare seconds count for a multi-hour value.
- **A stable, after-the-fact display zero-pads** the trailing component (`3m 05s`, `1h 04m`, `0:07`)
  so the string doesn't jitter in width; a live-updating estimate (`_eta`) does not.
- **Only a measured elapsed time keeps a decimal**, and only below a minute (`1.2s`). Estimates and
  coarse ages round to whole units.

---

## 4. 📅 Dates and times

**There is no `intl` dependency.** The app is single-locale today; format dates with the local helpers
and keep them local.

| Helper | Output | File |
| :--- | :--- | :--- |
| `relativeTime(DateTime?)` | `''` (null) · `now` · `5m` · `3h` · `2d` · `6w` · `1y` — coarse, no "ago" suffix | [format.dart#L16](../../app/lib/src/ui/format.dart#L16) |
| `_lastRanLabel(DateTime?)` | `never` · `just now` · `5 min ago` · `2 h ago` · `3 d ago` — the prose variant for the task schedule line | [tasks_panel.dart#L697](../../app/lib/src/ui/tasks_panel.dart#L697) |
| `_fmtNext(DateTime)` | `today 09:00` · `tomorrow 09:00` · `Wed 18:30` | [tasks_panel.dart#L718](../../app/lib/src/ui/tasks_panel.dart#L718) |
| `_dayLabel(DateTime)` | `Aug 7, 2026` — gallery day headers, from a local month-name table | [media_gallery.dart#L80](../../app/lib/src/ui/media_gallery.dart#L80) |
| `TaskSchedule.describe()` | `Every 6 hours` · `Daily at 09:00` · `Mon, Wed at 18:30` | [task_schedule.dart#L53](../../app/lib/src/state/task_schedule.dart#L53) |

Rules:

- **Display times are local; machine-readable stamps are UTC.** Config backups are named
  `rclone-yyyyMMdd-HHmmss[-n].conf` in UTC — sortable, timezone-stable, filesystem-safe
  ([config_backups.dart#L157](../../app/lib/src/state/config_backups.dart#L157)) — and rendered back
  to a readable label with an explicit `UTC` suffix
  ([settings_screen.dart#L849](../../app/lib/src/ui/settings_screen.dart#L849)).
- **A lexical sort over formatted names is not a chronological sort.** `ConfigBackups._sortKey`
  exists because the bare `rclone-<stamp>.conf` written first in a second would otherwise rank as the
  newest (`.` > `-`). Build an explicit ordering key when timestamps can collide.
- **`modTime` may be absent.** [`RcloneFile.fromJson`](../../app/lib/src/rclone/models/rclone_file.dart)
  uses `DateTime.tryParse` on the lsjson `ModTime` and leaves `null` when it is missing or
  unparseable; `compareRcloneFiles` sorts `null` modTimes **last** regardless of direction.

---

## 5. 🧵 Path helpers

| Helper | Purpose | File |
| :--- | :--- | :--- |
| `joinPath(parent, name)` | remote-relative join; empty parent → the bare name (remote root) | [pane_drag.dart#L6](../../app/lib/src/ui/pane_drag.dart#L6) |
| `join(parent, name)` | identical implementation, used inside `FileOps` | [file_ops.dart#L10](../../app/lib/src/state/file_ops.dart#L10) |
| `BrowserState.segments` | split the current path on `/`, dropping empties | [browser_controller.dart](../../app/lib/src/state/browser_controller.dart) |
| `fsRoot(path)` | forward-slash a local path and append a trailing `/` — the shape rclone's `local` backend wants as an `fs` | [local_locations.dart#L56](../../app/lib/src/state/local_locations.dart#L56) |
| `localAbsolutePath(remote, path)` | resolve a browse entry to a real OS path, or `null` when the remote isn't local | [cloud_placeholder.dart#L74](../../app/lib/src/state/cloud_placeholder.dart#L74) |
| `splitFsRemote(token)` | `remote:path` → `(fs, remote)`; connection-string aware, refuses `C:/…` | [console_rc_translate.dart#L71](../../app/lib/src/state/console/console_rc_translate.dart#L71) |
| `remotePrefix(value)` | the remote name a config value references, or `null` when it's a path | [config_io.dart#L475](../../app/lib/src/state/config_io.dart#L475) |

Rules:

- **Remote paths always use `/`** — never `Platform.pathSeparator`. Only helpers that touch the real
  filesystem (`fsRoot`, `_safeLeaf`, backup basenames) normalise `\`.
- **A full rclone target is `remote.fs + joinPath(path, name)`** — `Remote.fs` already carries the
  trailing `:` or `/` ([remote.dart](../../app/lib/src/rclone/models/remote.dart)), so never insert
  another separator.
- Building a path from `state.path` plus a possibly-stale entry list is the known browser-listing
  race; see [14-performance-standards.md](14-performance-standards.md).

---

## 6. 🔤 Sorting and file classification

- [`compareRcloneFiles(a, b, key, ascending)`](../../app/lib/src/ui/column_header.dart#L22) — the one
  comparator for file lists. **Folders always sort before files**, regardless of key or direction;
  `null` modTimes go last; a case-insensitive ascending name comparison is the final tie-break so the
  order is stable.
- `RcloneFile.size == -1` means unknown (directories, backends that don't report it). Render it as
  `—`, never as `0 B` — that is what `humanSize`'s negative branch is for.
- [`kindOf(file)`](../../app/lib/src/ui/file_icon.dart#L107) classifies by extension first, then by
  MIME-type prefix. `isThumbnailable` / `isGalleryMedia` are derived from it and are the **single
  source of truth** for those filters — `isGalleryMedia` in particular is shared by the gallery grid
  and by "Select all", so the two can never disagree about what is selected.

---

## 7. 🧾 Summary and preview strings

| Helper | Use | File |
| :--- | :--- | :--- |
| `remoteEndpointSummary(section)` | first location-ish key (`host`, `url`, `endpoint`, `remote`, `account`, `region`, `provider`) as `key: value`; the key list is location-only so it can **never** print a secret. Shared by both config-import reviews | [remote_summary.dart](../../app/lib/src/state/remote_summary.dart) |
| `rcloneCmdPreview(options, src, dst)` | display-only CLI rendering of a `TransferOptions`, mirroring what `buildRcCall` sends | [transfer_options.dart#L283](../../app/lib/src/state/transfer_options.dart#L283) |
| `ConsoleCommand.preview()` | the exact command, quoted — **not** display-safe on its own | [console_command.dart](../../app/lib/src/state/console/console_command.dart) |
| `redactedPreview(cmd)` | the same preview with secret flag values and connection-string secrets replaced by `‹redacted›` — **use this anywhere a user sees a command** | [console_redaction.dart#L96](../../app/lib/src/state/console/console_redaction.dart#L96) |
| `blockedMessage(verb, flags)` | the console's refusal text, including the in-app alternative | [rclone_commands.dart#L205](../../app/lib/src/state/console/rclone_commands.dart#L205) |

`defaultArchiveName(leaf, format)` and `archiveFormatForName(name)` play the same role for archive
names — longest-extension-wins matching so `.tar.gz` beats `.gz`
([archive_command.dart](../../app/lib/src/state/archive_command.dart)).

---

## 8. 🔑 Cache keys

`thumbCacheKey(fs, path, modTime, size, px)` and `folderThumbCacheKey(fs, path, modTime, childCount)`
are both **SHA-1 hex over pipe-joined components**, with a missing `modTime` rendered as an empty
string ([thumbnail_service.dart#L54](../../app/lib/src/state/thumbnail_service.dart#L54),
[folder_preview.dart#L212](../../app/lib/src/state/folder_preview.dart#L212)).

**Rule:** a cache key must include *every* input that changes the output. A thumbnail's key includes
the pixel size because a 64px and a 256px render of the same object are different blobs; a folder
preview's includes the child count because adding a file changes the collage.

---

## 9. ➕ Adding a helper

- [ ] Grep first — `humanSize`, `joinPath`, `relativeTime`, `compareRcloneFiles`, `uniqueName` and
      `escapeRcloneGlob` already cover most cases.
- [ ] Keep it **pure and total**: plain data in, plain data out, no `BuildContext`, no I/O. That is
      what makes it testable in `app/test/` without an engine.
- [ ] Put it in the file of its first consumer, top-level and documented. Promote it to a shared file
      only when a second consumer appears — and when you do, migrate the original rather than leaving
      both.
- [ ] Document the *rule*, not just the behaviour ("1 decimal below 10", "folders always first") — the
      dartdoc is the spec, and this page links to it.
- [ ] Add a unit test in `app/test/` covering the boundary cases the rule names.
- [ ] Run `dart format` and `flutter analyze` before committing — CI fails on any info-level lint and
      on unformatted files.

---

## Related

[Core Architecture](08-core-architecture.md) · [State & Context](07-state-context.md) ·
[Design System](06-design-system.md) · [Validation Standards](11-validation-standards.md) ·
[Performance Standards](14-performance-standards.md) · [Glossary](16-glossary-of-terms.md) ·
[System Index](00-system-index.md)
