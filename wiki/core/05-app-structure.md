---
type: "core"
name: "App Structure & Layouts"
status: "stable"
dependencies: ["06-design-system"]
description: "The application shell, navigation models, and screen layouts for desktop and mobile, with wireframes."
---

# 🏗️ App Structure & Layouts

Airclone is **one product in two layouts and three input models**. The same domain models,
`RcloneClient`, and component primitives back all of them; only the shell and the navigation model
differ. Mobile is **not** a shrunken desktop — it drops the dual pane; and a television is the mobile
shell wrapped for a five-key remote, not a fourth design.

**When to read this:** you are adding or moving a surface in the app shell — a toolbar verb, a
sidebar entry, a pane or tab, the job panel, a bottom-nav tab or the FAB — and need to know where it
belongs on desktop versus mobile versus a television, and which form factor the change must not
break.

---

## 🖥️ Desktop — Dual-Pane File Commander

A **rebuilt file explorer purpose-built for rclone** — this in-app browser is the **primary, hero
surface** of Airclone, not a fallback for the OS mount. It is a dual-pane commander wrapped in a
modern, themeable shell: *two browsable locations plus an action between them.* It opens **many
remotes at once** (each pane has tabs; any tab targets any remote + path), lets you **add and
configure remotes inline**, and supports **full in-app drag-and-drop** — including dropping OS files
directly **onto a folder row**, exactly like dragging into a folder in a native explorer.

> **Why the in-app explorer is the performant path (and mount is the convenience).** In-app actions
> call the rclone RC surface **directly** — server-side `copyfile`/`movefile` within a remote (no
> bytes leave the cloud), streamed `sync/copy` across remotes — so uploads/moves **bypass the VFS
> cache** entirely. The OS mount is offered as a convenience for using a remote inside other apps, but
> its VFS write-back/cache layer makes uploads and moves slower; Airclone steers everyday file work to
> the in-app explorer and treats mount as secondary. See
> [08-core-architecture.md §4](08-core-architecture.md).

**Anatomy**

- **Global toolbar (top, 44px):** app identity, global verbs (New Remote, Copy, Move, Sync, Compare),
  Jobs / Mounts / Scheduler toggles, global bandwidth-throttle slider, theme + settings. Verbs are
  redundant with drag and right-click so novices and pros each have a path.
- **Left sidebar (240px, collapsible):** vertical list of **remote cards** (provider icon, name,
  connection dot, thin storage-usage bar) with "+ Add remote" pinned at top. Local disks appear as
  peers below a divider. Right-click → Mount, Browse, Serve, Edit, pinned Quick Actions. A name too
  long for its row is **not** ellipsised: line one stays at full size and the overflow continues on a
  second line in smaller text (`OverflowName`), because remotes whose names differ only in the last
  two characters otherwise render as identical rows. A name that fits is untouched — nearly every
  row. Removing every remote at once is deliberately **not** here: it lives in Settings, behind a
  named list and an acknowledgement ([15-security.md §3.3](15-security.md)).
- **Dual-pane browser (center stage):** two independent panes, each with **tabs** (open many remotes
  at once — a tab per remote+path), its own provider switcher + editable path bar + breadcrumb,
  sortable columns (Name / Size / Modified / Status), and a per-pane filter box. Panes/tabs retarget
  to any remote — Drive left, S3 right, cloud-to-cloud in one drag. A single-pane toggle exists for
  small windows; either pane can split into more tabs rather than forcing a second window. A pane
  never says "Empty folder" over a listing rclone shortened: when a `crypt` remote's key does not
  match its data, rclone drops the entries it cannot decrypt and still answers 200, so the pane
  counts those notices across its own request and reports **"N items hidden"** instead
  ([07-state-context.md](07-state-context.md), `hiddenUndecryptable`).
- **Transfer / Job panel (bottom, dockable):** persistent, and the always-on observability surface.
  Two tabs, not three: **Transfers** (the live per-file strip over the job list — type, source → dest,
  per-file progress, speed, ETA, status, with Stop / Stop-all / Clear-finished) and **Recent
  activity**, which reads `core/transferred` from the engine rather than keeping a history of its own.
  There is no search. *Scheduled* work is not a dock tab — saved transfers live in the Tasks dialog,
  backed by `tasksProvider` and run by `schedulerProvider`. See
  [jobs_dock.dart](../../app/lib/src/ui/jobs_dock.dart).
  **Resizable, and everything in it has to grow with it:** drag its top edge, double-click that
  edge, or use the chevron in its tab strip. The live per-file strip (`StatsPanel`) takes up to half
  the dock's height rather than a fixed box — a dock the user made taller that still shows three
  in-flight files is the bug report "the transfers list is compacted … I couldn't resize it". A job
  moving more files than its row shows offers a tappable expander, never a dead "+N more".
- **Status bar (bottom, 24px):** Mount Manager + CLI buttons, engine-health dot; center aggregate
  (`↑ 12.4 MB/s · 3 jobs · ETA 2m`); right item-count (tabular-nums).

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ ◉ Airclone   [+New Remote] [Copy][Move][Sync][Compare] │ [Jobs][Mounts][Sched] ⚙ │
├──────────────┬────────────────────────────────────────────────────────────────────┤
│ REMOTES   +  │ ┌── PANE A ───────────────┐  ┌── PANE B ────────────────────────┐ │
│              │ │ ⊞gdrive ⊞dropbox      + │  │ ⊞s3:backups ⊞gdrive          + │ │
│              │ │ [gdrive ▾]  ⌂ > Work > Q1 │  │ [s3:backups ▾]  ⌂ > 2026         │ │
│ ▣ Google Drv │ │ 🔎 filter…        ⇅ Name  │  │ 🔎 filter…             ⇅ Modified │ │
│   ▓▓▓▓░ 64%  │ ├───────────────────────────┤  ├──────────────────────────────────┤ │
│ ▣ S3 backups │ │ 📁 designs/        —  2d   │  │ 📁 jan/           —      5 Jan    │ │
│   ▓▓░░░ 31%  │ │ 📁 contracts/      —  1w   │  │ 📁 feb/           —      3 Feb    │ │
│ ▣ OneDrive ● │ │ 📄 plan.pdf     2.1MB 3h   │═▶│ 📄 plan.pdf    2.1MB    today    │ │
│ ─────────────│ │ 📄 budget.xlsx  140KB 1d   │  │ 📄 notes.md     4KB     today    │ │
│ 💽 Local C:  │ │ 🖼 hero.png     8.4MB 2h   │  │                                  │ │
│ 💽 SD card   │ │                           │  │       (drag A→B = copy)          │ │
├──────────────┴───┴───────────────────────────┴──┴──────────────────────────────────┤
│ [Transfers] Recent activity                                    ⌃ [Stop All] [⌫]    │
│ ▸ Copy  gdrive:/Q1/hero.png → s3:backups/2026   ▓▓▓▓▓▓░░  73%  8.4MB/s  ETA 0:03   │
│ ▸ Sync  Local C:/Photos → onedrive:/Photos      ▓▓░░░░░░  18%  2.1MB/s  ETA 4:21   │
├────────────────────────────────────────────────────────────────────────────────────┤
│ ⛁ Mounts  ⌨ CLI   ● engine ok          ↑12.4MB/s · 2 jobs · ETA 4:21    | 5 items  │
└────────────────────────────────────────────────────────────────────────────────────┘
```

**Drag-and-drop**

| Gesture | Result |
| :--- | :--- |
| OS file → empty pane area | Upload to the current pane path (border glows; ghost row in Jobs) |
| **OS file → a folder row** | Upload **into that folder** (row highlights on hover — like dropping into a folder in a native explorer) |
| Pane row → OS | Download to OS location (real file payload, drag-out) |
| Pane row → a folder row (same or other pane) | **Copy into that folder** (server-side within a remote; streamed across remotes) |
| Pane A → Pane B (empty area) | **Copy** to the other pane's path (default; animated arrow) |
| Shift + drag | **Move** (source rows dim) |
| Alt / right-drag → drop menu | Choose Copy / Move / Sync at the drop target |
| Multi-select + drag | Batch transfer (onto a folder or pane) |

Drag *default is copy* (safest); move/sync need an explicit modifier or menu choice. Drops are
**target-aware**: hovering a folder row drops *into* that folder, hovering empty pane space drops at
the pane path. Every drag produces a real `_async` job in the Job panel — never a silent operation —
and within a single remote uses **server-side** copy/move so no bytes round-trip through your machine.

**Nothing here overwrites silently.** Every drop, paste and "Copy/Move to…" goes through the one
conflict-aware routine (`transferNamesIntoFolder` in
[paste_action.dart](../../app/lib/src/ui/paste_action.dart)): it reads the destination's names
first, and when any collide it asks Skip / Replace / Keep both before dispatching. "Keep both"
renames the way a desktop file manager does (`report.pdf` → `report (2).pdf`). Two properties are
load-bearing and must survive any refactor: a re-entrancy latch, so a double drop cannot stack two
dialogs or dispatch the same move twice; and a **fail-closed** probe — a destination that cannot be
listed copies *nothing* and says so, because an unreadable folder used to read as "no collisions"
and dispatch a plain overwrite.

**Sync dialog** (from the Sync verb, a remote Quick Action, or right-drag → Sync). The sketch below
is the *intended* shape and is ahead of the code: the shipped
[`transfer_options_dialog.dart`](../../app/lib/src/ui/transfer_options_dialog.dart) has three tabs —
**Settings** (Mode, Options, Compare by, Performance, plus the two-way-only conflict rows), **Filters**,
**rclone cmd** (the exact command the run will produce) — and a Cancel / Dry run / Run footer. There is no job-name field, no
second destination, and no "Save as Job" here; saved transfers are named and stored from the Tasks
panel instead. Treat the wireframe as direction, not as the current UI:

```
┌──────────────────────── New Sync Job ─────────────────────────┐
│  Job name:  [ Nightly-Photos-Backup___________ ]              │
├───────────────────────────────────────────────────────────────┤
│  SOURCE                          DESTINATION      [+ Add dest] │
│  [Local C: ▾] /Users/me/Photos   [onedrive ▾] /Photos         │
│  DIRECTION                                                    │
│   ( ) Mirror →   make dest match source  ⚠ deletes extras    │
│   (•) Backup new only   copy new/changed, never delete        │
│   ( ) Two-way ⇄   sync both directions (needs pairing)        │
├───────────────────────────────────────────────────────────────┤
│  ▸ Filters         Media · Docs · Code   max 0 · age any      │
│  ▸ Advanced tuning  4 transfers · 8 checkers · 3 retries      │
│  ▸ Bandwidth        unlimited                                 │
├───────────────────────────────────────────────────────────────┤
│  [ 🔍 Dry-run preview ]            [ Save as Job ]  [ Run ▶ ]  │
└───────────────────────────────────────────────────────────────┘
```

Direction is plain-language: **Mirror →** (destructive, labeled), **Backup new only**, **Two-way ⇄**
(first run shows a one-time "Initialize pairing" + conflict-strategy dropdown). Destructive mirrors
require an explicit confirm, which also offers "Dry run first".

**What "dry run" actually does depends on which flow you are in, and only one of them answers the
question a Sync raises.** A plain dry run dispatches the *real* job with `DryRun` set, so it lands in
the Transfers dock as a row reading "Done" and a byte count — the number that matters, how many
files would be **deleted** at the destination, appears nowhere. The marked-source flow below
instead computes the answer up front with `operations/check` and shows it as counts with expandable
file lists — **deletions first**, then overwrites, then copies, plus "already identical" and
"couldn't be compared" — before anything runs
([sync_preview.dart](../../app/lib/src/state/sync_preview.dart),
[sync_preview_dialog.dart](../../app/lib/src/ui/sync_preview_dialog.dart)). Going ahead from that
preview runs the real thing — the preview *was* the dry run. The pane-to-pane Sync verb has not been
moved onto it yet. Separately, **Compare with other pane** is its own tool over the same RC method
([folder_tools.dart](../../app/lib/src/ui/folder_tools.dart)); it reports differences and transfers
nothing.

**Mark-then-sync ("Set as sync source" → "Sync … to here").** A sync's two endpoints no longer have
to be on screen together: right-click a folder to mark it, navigate anywhere — another folder,
another remote — and the destination's context menu offers to sync the marked folder into it, named
so the row itself says what is about to overwrite this folder. Advanced mode only, folders only.
The gesture's hazard is the gap between its halves, so it preflights before offering any options:
an **overlapping** source/destination pair is refused outright (either direction, compared
case-insensitively), and an **unreadable or empty source** is refused too — a one-way sync from an
empty folder deletes everything at the destination, and "0 files" is indistinguishable from
"everything here is surplus" once rclone is running.
[sync_source.dart](../../app/lib/src/state/sync_source.dart) ·
[sync_here_action.dart](../../app/lib/src/ui/sync_here_action.dart).

**Scheduler** lists saved jobs as rows (name, source→dest, direction chip, human-readable schedule
via cron→prose, last/next run, run/pause/edit). The editor offers Interval or Time builders with an
advanced raw-cron field and an optional **"watch a local folder"** (debounced FS watcher) trigger.

**Mount Manager** (a *secondary convenience*, not the primary file-work surface) lists active mounts
(source, mount point, status) with a mount dialog whose options come from the shared
`MountOptionsEditor` — the same widget Settings uses to edit the persisted defaults, so the two can
never drift. Its fields are cache mode, cache size, keep-cached-for, directory cache, read chunk,
chunk-grows-to, attribute cache, fast change detection and (Windows only) mount-as-a-network-drive.
The defaults and the reasoning behind each are owned by
[14-performance-standards.md §6](14-performance-standards.md) and
[`mount_options.dart`](../../app/lib/src/rclone/models/mount_options.dart); do not repeat a value
here. A mount point can also be **pinned per fs**: rclone's `*` picks the next free letter, which is right
for a one-off and wrong for a drive you have shortcuts and muscle memory pointed at, so ticking the
box records the letter the mount actually got and re-uses it next time
([mount_letters.dart](../../app/lib/src/state/mount_letters.dart)). The dialog also carries a
**FUSE driver guard** that detects WinFsp/macFUSE/FUSE3 and offers one-click install instead of a
cryptic error. Mount exists so a remote is reachable *inside other
apps*; for uploading and moving files, the in-app explorer is faster (it avoids the VFS cache), and
the UI gently nudges users there for heavy file work.

**Onboarding (3 steps):** Welcome ("Airclone bundles rclone — nothing to install") → Add your first
remote (provider grid → dynamic form, Quick/OAuth default) → "You're set" (drops into the dual pane,
new remote left + Local right, with a "drag a file here→there to copy" coach-mark). Empty states are
illustrated and instructive.

---

## 📱 Mobile — Touch-First Browser + System Storage

Single-pane, touch-first. No dual pane, no FUSE mount. The shell is chosen by **width**, not by
platform: `< 700px` (or a television) gets `MobileHomeScreen`, so an Android tablet in landscape runs
the desktop shell — see [06-design-system.md](06-design-system.md) for the one real breakpoint.

The intended headline feature is **system integration**: remotes appearing in the phone's own Files
app via an Android `DocumentsProvider` / iOS File Provider, toggled per remote. **Neither bridge is
built** — there is no `DocumentsProvider` in `app/android/` and no File Provider target in
`app/ios/`, so the "Show in Files" toggle and its secondary line ("Available in Files app" / "Not
shown in system files") are design, not shipped UI.
[02-product-context.md](02-product-context.md) owns that status; the wireframe below is a sketch of
the intended shell and shows the toggle for that reason.

**Bottom nav:** **Remotes** (home) · **Files** (active browser) · **Transfers** · **Settings**, with a
context-aware floating **+** (add remote on Remotes; upload on Files) that opens a bottom sheet rather
than a dropdown.

**Remote cards** are large tap targets carrying the provider icon, name, connection dot and storage
bar.

**Touch browser:** full-width 56px rows, horizontally-scrolling breadcrumb, long-press multi-select →
contextual action bar (Copy, Move, Download, Share link, Delete), `+` FAB upload (background job with
notification), on-demand **materialization** (open → download-then-open with progress; "still
uploading" state surfaced after edits).

```
   Home (Remotes)              Browser (Files)
┌─────────────────────────┐  ┌─────────────────────────┐
│  Airclone          ⚙    │  │ ‹  gdrive › Work › Q1   │
│  Your remotes           │  │ ⌂  Work  Q1            🔎│
├─────────────────────────┤  ├─────────────────────────┤
│ ┌─────────────────────┐ │  │ 📁 designs/         2d › │
│ │ ▣  Google Drive   ● │ │  │ 📁 contracts/       1w › │
│ │ ▓▓▓▓▓▓░░░  64% used │ │  │ 📄 plan.pdf  2.1MB  3h ⋯ │
│ │ ☁ Available in Files │ │  │ 📄 budget.xlsx 140KB 1d ⋯│
│ │ Show in Files  [ ●○]│ │  │ 🖼 hero.png  8.4MB  2h ⋯ │
│ └─────────────────────┘ │  │                         │
│ ┌─────────────────────┐ │  │  (long-press to select) │
│ │ ▣  S3 backups     ● │ │  │                         │
│ │ Not shown in files  │ │  │                     (+) │
│ │ Show in Files  [○ ○]│ │  ├─────────────────────────┤
│ └─────────────────────┘ │  │ ▤    📁    ⇅    ⚙        │
│                     (+) │  │Remotes Files Transf Set │
└─────────────────────────┘  └─────────────────────────┘
```

**Background sync** is honestly framed: the Transfers tab shows a "Background sync" card (last/next
run + best-effort disclaimer). Active foreground transfers mirror to a system notification; scheduled
runs (WorkManager / BGTaskScheduler) are best-effort. Live, user-initiated transfers are reliable.

---

## 📺 Television — the mobile shell, wrapped

Android TV and Google TV run the **same APK and the same `MobileHomeScreen`**, wrapped in `TvShell`.
It is a wrapper rather than a third layout on purpose: a television is a phone-shaped, single-pane
browser operated with a five-key remote, so what changes is *input*, not structure. Everything TV-
specific lives in one file, [`ui/tv.dart`](../../app/lib/src/ui/tv.dart), so the affordances can be
audited against Google's TV requirements in one read rather than chased through `if (tv)` branches.

**INVARIANT — every TV branch gates on `androidIsTelevision`, and nothing in `tv.dart` may run off a
television.** That flag is a plain `bool` resolved once by `initAndroidIsTelevision()` in `main()`
**before `runApp`** — the shell is chosen inside a synchronous `build()`, so it cannot be a future.
It is `false` on every other platform *and* until that call returns, so a channel failure degrades a
TV to the touch shell instead of handing a phone the TV one.
[`android_native.dart`](../../app/lib/src/state/android_native.dart) ·
[`home_screen.dart`](../../app/lib/src/ui/home_screen.dart) (`androidIsTelevision || width < 700`) ·
[`app.dart`](../../app/lib/src/ui/app.dart) (the `TvShell` wrap, width-independent).

**INVARIANT — Airclone draws the focus ring itself, once, from outside the widget tree.** With no
pointer the ring *is* the cursor. Material's default focus overlay is a ~10% wash designed for
someone whose finger is already on the control, and across a room it reads as nothing; worse, several
widgets this app is built from decline to draw one at all — `NavigationRail` ignores
`ThemeData.focusColor` outright, and file rows rendered nothing while focus was demonstrably
travelling through them (pressing centre after two arrow presses activated a different tab, while the
screenshots either side were byte-identical). Setting a theme colour and assuming it took looks
exactly like success, which is the trap. The **refuted alternative** was to chase it widget by
widget: that re-opens the question on every screen added afterwards. `TvFocusOverlay` instead tracks
`FocusManager` and paints one ring over whatever holds focus, re-measuring post-frame and on every
scroll notification, so a screen written later is covered without knowing it exists.

`TvShell` composes four things, and the placement of the wrap is itself the fix — it is installed
from `MaterialApp.builder`, **above the Navigator**, because a `showDialog` route is a sibling of the
home screen and not a descendant. Wrapping the home `Scaffold` gave dialogs none of this, and the
field report was exactly that: a passphrase could be typed but Unlock could never be reached.

| Part | What it does |
| :--- | :--- |
| `TvFocusTheme` | Raises `focusColor` to the app accent at 34% for the TV subtree only — read from `AircloneTheme`, not `colorScheme`, which handed the ring Material's default purple. |
| `TvFocusOverlay` | The ring, above. |
| `TvDpadEscape` | Rebinds bare ArrowUp/ArrowDown to `DirectionalFocusIntent(ignoreTextFields: false)`. Flutter binds those to a text-editing intent on Android, and `EditableText` enables it whenever the selection is valid — always — so the key is consumed to move the caret and never reaches traversal. Vertical only: LEFT/RIGHT stay with the caret so a typo is still fixable. |
| `TvFocusSeed` | Directional traversal needs an *origin*; with only a bare `FocusScopeNode` focused (what a freshly pushed route leaves) every arrow press is a no-op. This re-seeds whenever the primary focus is a scope, and settles by itself because a real widget is not a scope. |

Inside the shell, `MobileHomeScreen` swaps its bottom bar for `TvNavRail` and wraps itself in
`TvInitialFocus` — **a side rail, because a bottom bar is the wrong shape for a D-pad**: reaching a
bottom bar means pressing DOWN through every row of the file list first, where one LEFT press reaches
a side rail from anywhere. The rail is hand-built for the `NavigationRail` reason above.
`TvInitialFocus` is the home shell's counterpart to `TvFocusSeed` — it owns its own `FocusScopeNode`
rather than looking one up, because the ambient route scope can already report a focused child for
reasons that have nothing to do with the file list, which made the "is anything focused?" guard read
yes and the seed never run. The whole frame sits inside `tvOverscan` (48dp across, 27dp down —
Google's 5% guidance at 1080p), because a television crops the edge of the picture by an amount an app
cannot query; without it the wordmark and the settings button sat hard against the bezel.

---

## 🔗 Related

- [06-design-system.md](06-design-system.md) — the tokens, components and breakpoints every surface
  described here is built from; read it before touching UI.
- [20-explorer-design.md](20-explorer-design.md) — the explorer direction behind the dual pane: view
  modes, inspector, thumbnails, Quick Look, native feel.
- [03-user-journey.md](03-user-journey.md) — these shells walked per platform
  (Windows/macOS/Linux/Android/Android TV/iOS) with the feature matrix.
- [dev/android-tv.md](../../dev/android-tv.md) — how to actually drive a TV build with a D-pad, and
  what an Android TV image does not have.
- [07-state-context.md](07-state-context.md) — which Riverpod provider owns pane, tab, job and mount
  state behind these layouts.
- [08-core-architecture.md](08-core-architecture.md) — why in-app explorer actions bypass the VFS and
  mount is the secondary convenience.
- [../components/components-index.md](../components/components-index.md) — the reusable primitives
  (remote card, file row, transfer row) these layouts compose.
- [../features/features-index.md](../features/features-index.md) — the per-screen specs for the
  browser, sync, mount and preview surfaces named above.
- [00-system-index.md](00-system-index.md) — the master router.
