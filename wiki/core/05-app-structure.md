---
type: "core"
name: "App Structure & Layouts"
status: "stable"
dependencies: ["06-design-system"]
description: "The application shell, navigation models, and screen layouts for desktop and mobile, with wireframes."
---

# 🏗️ App Structure & Layouts

Airclone is **one product in two form factors**. The same domain models, `RcloneClient`, and
component primitives back both; only the layout shell and navigation model differ. Mobile is **not** a
shrunken desktop — it drops the dual pane and adds system-storage integration.

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
  peers below a divider. Right-click → Mount, Browse, Serve, Edit, pinned Quick Actions.
- **Dual-pane browser (center stage):** two independent panes, each with **tabs** (open many remotes
  at once — a tab per remote+path), its own provider switcher + editable path bar + breadcrumb,
  sortable columns (Name / Size / Modified / Status), and a per-pane filter box. Panes/tabs retarget
  to any remote — Drive left, S3 right, cloud-to-cloud in one drag. A single-pane toggle exists for
  small windows; either pane can split into more tabs rather than forcing a second window.
- **Transfer / Job panel (bottom, dockable):** persistent. Live rows (type, source → dest, per-file
  progress, speed, ETA, status) with **Active / Scheduled / History** tabs (history searchable) and
  Stop / Stop-all / Clear-finished. The always-on observability surface.
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
│ JOBS  [Active] Scheduled  History                                   [Stop All] [⌫] │
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

**Sync dialog** (from the Sync verb, a remote Quick Action, or right-drag → Sync):

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
(first run shows a one-time "Initialize pairing" + conflict-strategy dropdown). **Dry-run preview** is
always present and opens the color-coded Compare diff; destructive mirrors require explicit confirm.

**Scheduler** lists saved jobs as rows (name, source→dest, direction chip, human-readable schedule
via cron→prose, last/next run, run/pause/edit). The editor offers Interval or Time builders with an
advanced raw-cron field and an optional **"watch a local folder"** (debounced FS watcher) trigger.

**Mount Manager** (a *secondary convenience*, not the primary file-work surface) lists active/saved
mounts (source, mount point, VFS cache mode, status) with a mount dialog (drive-letter/path, cache
mode default `writes`, cache dir/size/age, read-only, auto-mount, network-drive/volume-name behind
Advanced) and a **FUSE driver guard** that detects WinFsp/macFUSE/FUSE3 and offers one-click install
instead of a cryptic error. Mount exists so a remote is reachable *inside other apps*; for uploading
and moving files, the in-app explorer is faster (it avoids the VFS cache), and the UI gently nudges
users there for heavy file work.

**Onboarding (3 steps):** Welcome ("Airclone bundles rclone — nothing to install") → Add your first
remote (provider grid → dynamic form, Quick/OAuth default) → "You're set" (drops into the dual pane,
new remote left + Local right, with a "drag a file here→there to copy" coach-mark). Empty states are
illustrated and instructive.

---

## 📱 Mobile — Touch-First Browser + System Storage

Single-pane, touch-first. The headline feature is **system integration**: remotes appear in the
phone's own Files app (Android `DocumentsProvider` / iOS File Provider). No dual pane, no FUSE mount.

**Bottom nav (4 tabs):** **Remotes** (home) · **Files** (active browser) · **Transfers** (live +
scheduled + history) · **Settings**. A context-aware floating **+** (add remote on Remotes; upload on
Files).

**Remote cards** are large tap targets with a prominent per-remote **"Show in Files" toggle** — on =
registers that remote as a root in the system file explorer (SAF root / File Provider domain), with a
secondary line ("Available in Files app" / "Not shown in system files").

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

**Related:** [Design System](06-design-system.md) · [User Journey](03-user-journey.md) ·
[Core Architecture](08-core-architecture.md)
