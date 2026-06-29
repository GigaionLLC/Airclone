---
type: "feature"
name: "File Browser (Rebuilt rclone Explorer)"
status: "stable"
platforms: ["desktop", "mobile"]
dependencies: ["08-core-architecture", "05-app-structure", "06-design-system"]
description: "Airclone's hero feature: a file explorer purpose-built for rclone — multi-remote, drag-and-drop, inline config, and a direct (non-VFS) transfer engine."
---

# 🗂️ File Browser — the Rebuilt rclone Explorer

This is **the hero feature** of Airclone. It is a file explorer rebuilt specifically for rclone: it
opens and configures **many remotes at once**, supports **full in-app drag-and-drop** (including
dropping files *onto a folder*), and moves data through a **direct, non-VFS transfer engine** that is
faster than operating on an OS mount. Everything else (mount, serve, scheduler) orbits this surface.

> The OS mount is a *secondary convenience* for using a remote inside other apps. For everyday
> browsing, uploading, and moving, the in-app explorer is the primary and more performant path — see
> [08-core-architecture.md §4](../core/08-core-architecture.md).

---

## 1. Why a rebuilt explorer (not just a mount)

Mounting a remote routes every read/write through rclone's **VFS cache** (write-back, chunking,
eviction) plus the kernel FUSE/SAF layer — which makes uploads and moves slow and occasionally
fragile. The in-app explorer instead drives the rclone **RC surface directly**, so it can:

- **Move/copy server-side** within a remote (`operations/movefile` / `operations/copyfile`) — bytes
  never leave the cloud; a "move" is near-instant.
- **Stream cross-remote** transfers (`sync/copy`) without staging through a local VFS cache.
- **Upload from a local path** straight into a target folder, with a real progress job.

Result: the same actions that feel sluggish on a mounted drive are fast in the explorer, and they
appear as first-class, cancellable jobs.

## 2. Multiple remotes, open at once

- **Sidebar** — every configured remote + local disks as peers (provider icon, connection dot,
  storage bar). Click to open; right-click for Mount / Serve / Edit / Quick Actions.
- **Dual pane** (desktop) — two independent browsers side by side; target any remote in either. The
  classic "source on the left, destination on the right, action between them" model.
- **Tabs per pane** (desktop) — each pane holds multiple tabs, each pinned to a remote + path, so you
  can have Drive, S3, Dropbox, and a local folder all open simultaneously without extra windows.
- **Single pane** (mobile, and a desktop toggle) — one browser with fast remote-switching.

## 3. Add & configure remotes inline

Adding/editing a remote never leaves the explorer:

- **+ Add remote** → provider grid → a **dynamic form generated from `config/providers`** (field types
  mapped to widgets, `Examples`/`Exclusive` selects, conditional fields, Advanced expander,
  `IsPassword`/`Sensitive` redaction).
- **OAuth / interactive** backends run the `opt.nonInteractive` + `continue`/`state`/`result` state
  machine (system browser → loopback callback) without dropping to a terminal.
- **Edit** is atomic (`config/update`), not delete-and-recreate. Capability-gating from
  `operations/fsinfo` hides actions a backend can't do (public links, about, empty dirs).

See [Core Architecture §5](../core/08-core-architecture.md) for the form/secrets details.

## 4. In-app drag-and-drop (target-aware)

Drag-and-drop works **inside the app**, not only via the OS mount — exactly like dragging files into a
folder in a native explorer:

| Gesture | Result |
| :--- | :--- |
| OS file → empty pane area | Upload to the current pane path |
| **OS file → a folder row** | Upload **into that folder** (row highlights on hover) |
| Pane row → OS | Download to the OS (real drag-out payload) |
| Row → a folder row (same/other pane/tab) | **Copy into that folder** (server-side within a remote) |
| Pane/tab A → Pane/tab B | **Copy** to the other location (default) |
| Shift + drag | **Move** |
| Alt / right-drag → drop menu | Choose Copy / Move / Sync at the target |
| Multi-select + drag | Batch transfer |

Rules: **default is copy** (safest); move/sync require a modifier or the drop menu; drops are
**target-aware** (hovering a folder drops *into* it; empty space drops at the pane path); every drag
becomes a visible `_async` job — never a silent operation. (Mobile uses long-press multi-select + an
action bar instead of drag, since touch drag is unreliable.)

Implementation note (desktop/Flutter): use a Rust-backed drag plugin that exchanges **real OS file
payloads** so drag-out produces actual files and drag-in receives them, plus an in-app drag channel
for row→folder and pane→pane moves.

## 5. The transfer engine (stat-then-dispatch)

1. **Stat the source** (`operations/stat` / list metadata) to learn `IsDir`.
2. **Dispatch the right RC call:**
   - File, same remote → `operations/copyfile` / `operations/movefile` (**server-side**).
   - Dir, or cross-remote → `sync/copy` / `sync/move` (streamed).
   - OS → remote → upload from local path; remote → OS → streamed download.
3. **Run async** with `_async:true` + a `_group`; a **single shared ~1 Hz poller** reads
   `core/stats {group}` + `job/status` and feeds per-file + aggregate progress/ETA into the Job panel.
4. **Cancel** via `job/stop` / `core/stats` group; **bandwidth** via a live `core/bwlimit` slider.

Destructive operations (mirror-delete, overwrite) always offer a **dry-run preview** and a color diff
before committing, with a `--max-delete` guard.

## 6. Browsing & viewing

- Navigation: editable path bar + breadcrumb, back/forward/up, per-tab history.
- Views: list (sortable Name/Size/Modified/Status columns) and grid/thumbnails; per-pane filter box;
  server-side search where supported.
- Selection: multi-select (Ctrl/Cmd-click, Shift-range, Ctrl+A), keyboard ops (`F2` rename, `Del`
  delete, `Ctrl+C/X/V` across panes).
- Preview: inline image/audio/video/PDF/text, streamed via the engine (no full download); pop-out
  viewers for media.
- File ops: new folder, rename, delete (with confirm), copy/cut/paste across remotes, public link
  (capability-gated), get size/about.

## 7. Relationship to the OS mount

The explorer and the mount are **complementary**:

- **Explorer** = primary, fast, in-app file work (drag-drop, server-side moves, jobs).
- **Mount / system Files** = a convenience so the remote is reachable in *other* apps; slower for
  upload/move due to VFS. The UI nudges heavy file work back into the explorer.

On **mobile**, the equivalent of "mount" is the per-remote **"Show in Files"** toggle
(`DocumentsProvider` / File Provider); the in-app explorer remains the primary surface there too.

---

## RC surface used (quick map)

`config/providers · config/create · config/update · config/delete · operations/list · operations/stat
· operations/mkdir · operations/copyfile · operations/movefile · operations/deletefile ·
operations/purge · operations/publiclink · operations/fsinfo · operations/about · sync/copy ·
sync/move · core/stats · core/bwlimit · job/status · job/stop`

**Related:** [App Structure & Layouts](../core/05-app-structure.md) ·
[Core Architecture](../core/08-core-architecture.md) · [Design System](../core/06-design-system.md) ·
[Features Index](features-index.md)
