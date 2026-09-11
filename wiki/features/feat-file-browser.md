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
  storage bar). Click to open (clicking the open one closes it); each tile's **⋯ menu** holds Test
  connection · Edit · Duplicate · Delete remote — see
  [Remote & Config Management §1](feat-config-management.md#1-where-these-actions-live). Mount and
  Serve are toolbar buttons, Advanced-gated, not tile actions; a sidebar tile is also a **drop
  target** (§4).
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
| OS files → the pane body | Upload into the pane's current folder. One drop can carry paths from several source folders, so it is split into one checked transfer per source folder |
| Row/tile → a folder row or tile | **Copy into that folder** (it highlights on hover). In-app drags only: a folder row registers no OS-file format, so dropping a file from Explorer *onto a folder row* is not an upload into that folder |
| Row/tile → the other pane | **Copy** into that pane's folder |
| Row/tile → a sidebar remote or location | **Copy into that remote's root** |
| Row/tile → the OS (Explorer/Finder) | Copies the file out — but only from a **local** location, and only the first item of a multi-selection carries a real file URI |
| Multi-select + drag | Dragging a *selected* row carries the whole selection; dragging an unselected one carries just it |
| OS folder → the sidebar's Locations section | Adds that folder to the sidebar. Not an upload |

Rules: **every drop is a copy.** The drag advertises `DropOperation.copy` and nothing else, so there
is no drop-time Move or Sync — those are menu actions (cut/paste, "Move to…", or the marked source in
§5.2). Drops are **target-aware** (hovering a folder drops *into* it; empty space drops at the pane
path), a drop onto a name that already exists **stops and asks** (§5.1), and every drop becomes a
visible `_async` job — never a silent operation.

Dragging is **desktop-only**: on a touch-primary device both the draggable and the drop region opt
out entirely (they would swallow the long-press that opens the context menu), so the phone uses
long-press multi-select + the action sheet instead.

> **Corrected against the code (0.7.6 doc pass).** This table used to promise `Shift`+drag for Move,
> an `Alt`/right-drag menu offering Copy / Move / Sync at the target, and a drag-out to the OS from
> any row. None of it is implemented: [`native_drag.dart`](../../app/lib/src/ui/native_drag.dart)
> allows exactly one operation, reads no modifier keys, and attaches an OS file payload only for a
> local remote. Said out loud rather than quietly deleted, because the gap is the interesting part —
> those gestures are a fair backlog item, but a doc that lists them as shipped is how someone
> concludes the modifiers are broken and goes looking for the bug.

Implementation note (desktop/Flutter): the Rust-backed `super_drag_and_drop` plugin carries the
in-app [`PaneDragData`](../../app/lib/src/ui/pane_drag.dart) as `localData` and, for local files, a
real `Formats.fileUri` — one gesture serving both an in-app drop and an OS drag-out. Plain text rides
along as the in-app marker, which is how a drop region tells our own drag from an OS one.

## 5. The transfer engine (stat-then-dispatch)

1. **Stat the source** (`operations/stat` / list metadata) to learn `IsDir`.
2. **Dispatch on that answer** (the source's shape, not the pair of ends):
   - A file → `operations/copyfile` / `operations/movefile`. Within one remote that is the
     **server-side** copy; across two remotes the same call streams.
   - A directory → `sync/copy` / `sync/move`. A `stat` that *failed* also takes this branch — the
     directory-safe fallback, because treating a folder as a file is the worse mistake.
   - OS → remote is the same call with a `local` fs on one side; a download is its mirror.
3. **Run async** with `_async:true` + a `_group`; a **single shared ~1 Hz poller** reads
   `core/stats {group}` + `job/status` and feeds per-file + aggregate progress/ETA into the Job panel.
4. **Cancel** via `job/stop` / `core/stats` group; **bandwidth** via a live `core/bwlimit` slider.

Destructive operations are gated — but not uniformly, and the difference is worth knowing before you
rely on it:

- **Overwrites** are caught by the collision preflight in §5.1 on the paths that route through
  `transferNamesIntoFolder`: paste, Copy/Move to…, Copy/Move to the other pane, Download, and a
  drag in from Explorer or Finder.
  **Two paths do NOT reach it**, and saying "every path" here was wrong: the advanced
  Copy/Move/Sync dialog run WITH a selection loops `transferAdvanced` per entry
  (`browser_pane.dart` `runAdvancedTransfer`), and Upload-from-URL writes straight to the
  destination name. The advanced dialog has its own confirmation, dry run and *keep replaced*
  option, so it is a deliberate path rather than a silent one — but it does not ask about a name
  collision, and a reader planning work off this page needs that stated rather than assumed.
- **A one-way Sync** started from the transfer options dialog confirms first (Cancel / *Dry run
  first* / Run) and carries a Sync-only **`--max-delete`** field — empty by default, which means no
  cap.
- **A change-set preview** — what would be deleted, overwritten and created, by name — exists in the
  marked-source flow (§5.2) and nowhere else yet. Everywhere else "Dry run" still dispatches the real
  job with `DryRun` set and leaves the answer in the Transfers dock. There is no color diff anywhere;
  [01-vision](../core/01-vision-north-star.md) states the destination, and this is how far the code
  has actually got.

### 5.1 Nothing lands on an existing name without asking

One routine owns every "put these named items into that folder" transfer:
[`transferNamesIntoFolder`](../../app/lib/src/ui/paste_action.dart). It exists because **rclone
overwrites by default** — a same-named file at the destination is replaced with no prompt, no warning
and no undo.

What it does, in order: take the destination's names (from a pane whose listing is already loaded, or
by listing it with `operations/list`), intersect them with the incoming names, and if anything
collides, ask — *"N of M already exist here"*, with the colliding names listed, and four answers:
**Cancel · Skip these · Replace · Keep both**. "Keep both" renames through `uniqueName`, which puts
the counter before the extension the way desktop file managers do (`report.pdf` → `report (2).pdf`;
a dotfile or an extension-less name gets it at the end) and counts up against names it has already
assigned in the same batch, so a plan never collides with itself.

Three properties hold the whole thing together:

- **It fails closed.** A destination that cannot be listed used to become an empty name set, which
  reads as "no collisions" and dispatches a plain overwrite — the one path here that could destroy a
  file without ever asking. Now it transfers nothing and says so.
- **It is re-entrant-safe.** A latch blocks a second paste or drop while one is resolving, so a
  double gesture cannot stack two conflict dialogs or dispatch the same move twice.
- **It reports whether anything actually ran**, so a cut clipboard is cleared, and a selection
  dropped, only on a real dispatch — cancelling a prompt used to be indistinguishable from
  succeeding.

**v0.7.6 finished the job.** Paste, "Copy to…" and "Move to…" already went through it; five paths
went straight at the transfer service and so overwrote silently — **Download** from the pane's
context menu, from the [inspector](../../app/lib/src/ui/inspector_panel.dart) and from the
[selection action bar](../../app/lib/src/ui/selection_actions.dart), the **OS drag-and-drop upload**,
and the **"Copy / Move to other pane" buttons**. Downloading a file you already have, and dragging one
into a folder that holds that name, are ordinary actions, not exotic edges. All five now share the
helper.
Two details of that fix are load-bearing: the pane-to-pane transfer hands over the *other pane's*
loaded listing, so the check costs no extra round trip; and an OS drop that carries paths from
several source folders is grouped by folder and checked once per group (a drag out of a single
Explorer window — the normal case — is still one prompt). The two pickers pass no listing on purpose:
"Copy to…" can land anywhere, so its destination has to be read rather than assumed.

**What this does not cover**, so nobody assumes more than is there: the prompt guards transfers of
*named items into a folder*. A whole-folder Copy/Move/**Sync** from the options dialog is a different
shape of operation and is governed by its own confirm and by the §5.2 preview — a sync has no list of
incoming names to intersect, which is exactly why it needs a change-set instead. Archive extraction
sidesteps the question differently: *Extract here* creates a new subfolder named after the archive, so
members can never land on top of what is already in the folder.

The confirmation catalogue that this belongs to lives in
[Validation Standards](../core/11-validation-standards.md) — the rule there is that anything which
can delete or overwrite names the consequence before it happens.

### 5.2 Marked sync source ("sync to here")

The two-pane transfer needs both endpoints open at once. The **marked source** is the one-pane form:
right-click a folder (or empty pane space) → **Set as sync source**, navigate anywhere — another
folder, another remote — then right-click → **Sync … to here…**, which opens the same transfer
options dialog pre-aimed at Sync. Both rows are Advanced-mode only (Settings → Advanced), because a
one-way sync deletes. Marking raises a snackbar naming what was marked, with a **Clear** action on
it — a mark that produced no visible change is indistinguishable from a menu item that did nothing,
and this one arms a destructive action several clicks later.

The mark lives in `syncSourceProvider` ([sync_source.dart](../../app/lib/src/state/sync_source.dart)),
deliberately NOT on the copy/cut clipboard: the clipboard is a list of names inside a folder, this is
the folder itself, `isNotEmpty` there already drives whether Paste appears, and the two gestures are
orthogonal. Session-only — a mark that survived a restart would be a forgotten pointer attached to an
operation that deletes.

**The gap between the two halves is the hazard**, and is what
[sync_here_action.dart](../../app/lib/src/ui/sync_here_action.dart) exists to close. The source was
chosen minutes ago and may since have been renamed, emptied or deleted, and a one-way sync from an
empty source deletes everything at the destination. So before any options are offered:

- **Overlapping paths are refused**, not warned about — `syncTargetRefusal` rejects identical and
  nested pairs in both directions (case-insensitively, `\` normalized). The marked flow is the first
  one where "sync a remote's root into a folder inside it" is two clicks with nothing on screen to
  make the overlap obvious. A shared name *prefix* (`Photos` vs `Photos-old`) is not containment.
- **An unreadable or empty source is refused**, fail-closed, on the same rule `paste_action.dart`
  applies to an unreadable destination: if we cannot see what is there, we do not write over it. The
  check is an `operations/size` on the marked fs, and a count of zero refuses — including the zero
  that comes back when the engine is not ready, which is the fail-closed half.
- The refusal is a **dialog, not a snackbar** — each one means "the sync you asked for would have
  destroyed something".

**The dry run now answers the question it exists for.** Choosing "Dry run" in the options dialog used
to dispatch the real job with `DryRun` set, which arrives in the Transfers dock as a row reading
"Done" beside a byte count — for a Sync, the one number a dry run is for (how many files it would
DELETE on the destination) appeared nowhere. It now runs a comparison first and shows
[sync_preview_dialog.dart](../../app/lib/src/ui/sync_preview_dialog.dart): deletions first and in
the error colour, then overwrites, then new files, each with its file list one click away, and "Run
it, deleting N" as the commit button.

Built on **`operations/check`**, not on a dry run's transfer log — an evidence-based choice, from
running both against a throwaway `rcd`. `core/transferred` does carry the deletions (`what:
"deleting"`) and its numbers match the real run exactly, but it is a ring buffer capped at ~100
entries per group and returned in completion order: a 300-file dry run comes back as 104 entries,
all deletions, with the transfers evicted. A preview built on it would quietly lie on any sync big
enough to need one. `operations/check` is uncapped and sorted, and `missingOnSrc` **is** the delete
list.

Two correctness rules for that comparison, both load-bearing:

- **It must compare under the transfer's own `_filter`** (hence `filterBlock` being public).
  `operations/check` honours filters, so a preview given different rules than the run reports a
  different set of deletions than the run performs.
- **It must compare the transfer's way** — `--size-only` / `--checksum` decide whether two files
  count as equal, so `previewConfig` carries those and nothing else. Everything else in a transfer's
  config changes what happens to a difference, not whether there is one, and belongs in
  `previewFrom`.

`previewFrom` is where "how the sides differ" becomes "what this would do": only Sync turns
`missingOnSrc` into deletions (Copy and Move report none — reporting them would invent a threat),
`--ignore-existing` means nothing is overwritten, `--suffix` means the overwrites are recoverable,
and `--update` means some overwrites may not happen after all, which is stated as "some" because
rclone decides per file at run time. If the deletions alone would trip `--max-delete`, the preview
says the run would **abort** — worth knowing before starting rather than after.

The menu row names the source (`Sync gdrive:Photos to here…` on empty pane space, `Sync gdrive:Photos
into this folder…` on a folder row, truncated from the left when long) rather than saying "Sync to
here", because the thing about to overwrite this folder was chosen somewhere else entirely. It is
offered even when the paths overlap, so the refusal can explain; a row that is silently absent teaches
nothing. bisync re-uses the existing baseline confirm — an ad-hoc pair has no baseline, so
`TransferService` would otherwise fire `--resync` silently.

## 6. Browsing & viewing

- Navigation: editable path bar + breadcrumb, back/forward/up, per-tab history.
- Views: four `ViewMode`s per pane tab — **list** (sortable Name/Size/Modified/Status columns),
  **icons** (grid/thumbnails), **gallery** (`ViewMode.media`) and **tree** (§6.2, desktop only —
  the switcher hides it on a touch-primary shell). Plus a per-pane filter box, which narrows the
  folder you are standing in and nothing else.
- **Find (`Ctrl+Shift+F`) is not a backend search.** It is one `operations/list` with
  `recurse: true` over everything below the pane's current folder, filtered in Dart by name and
  path, keeping at most 500 matches while still counting the true total. No backend query API is
  involved and there is no capability gate, so on a large remote this costs a full recursive
  listing of the subtree — worth knowing before running it at the root of something enormous.
- Selection: multi-select (Ctrl/Cmd-click, Shift-range, Ctrl+A), keyboard ops (`F2` rename, `Del`
  delete, `Ctrl+C/X/V` across panes).
- Preview: inline image/audio/video/PDF/text, streamed via the engine (no full download); pop-out
  viewers for media.
- File ops: new folder, rename, delete (with confirm), copy/cut/paste across remotes, public link
  (capability-gated), get size/about, **checksums** (per file, from the context menu), **compare two
  panes** (`operations/check` between them, bucketed into match / differ / missing either side) and
  the **duplicate finder** (same-content copies grouped, each deleted by its own unique path, so
  same-name Drive duplicates stay unambiguous).
- **The archive actions are build-gated.** *Compress…*, and on an archive *Extract here* /
  *Extract to…* / *List contents…*, shell out to the `rclone archive` CLI, so they appear only where
  this build may spawn a subprocess (`subprocessAllowedHere`). A store build bundles no binary, and
  the rows are absent there rather than present and dead.
- **Recent folders are opt-in and never written to disk.** Off by default; the switch is in Settings
  and *it* persists, while the trail itself is session-only (capped at 12, newest first) and feeds
  the Home screen's "Recent" row and the Ctrl+K palette. Turning it off drops what was already
  collected rather than merely hiding it, and while it is off nothing is recorded at all. The reason
  is that a trail nobody asked for puts remote and folder names on the first screen of the app, where
  anyone glancing at the window can read them.

### 6.1 "Empty folder" is a claim, and sometimes a false one

A `crypt` remote whose password or salt does not match the data it wraps behaves perfectly in every
way a UI can see: it constructs, it reports quota, `operations/list` returns 200. Only the **names**
fail to decrypt — rclone skips those entries, logs a `NOTICE: … Skipping undecryptable file name: …`
per entry, and returns the listing minus them. Six directories therefore arrive as an empty list, and
a pane that trusts the response renders a confident "Empty folder" over a full one. That reached a
real user, who reasonably concluded their backups had vanished.

So the pane no longer says "Empty folder" when it can tell the difference. It samples the engine
log's notice counter either side of its own listing and, for a `crypt` pane, reports the delta as
**"N items hidden"** with the likely cause (a padlock, not a spinner) — or, when *some* entries did
come back, as a strip above the listing saying the same thing. Attribution is deliberately a miss
rather than a false alarm: the notice carries the encrypted name and no remote, so a crypt reached
*through* an alias or union is not attributed and keeps the old, silent behaviour. The counter, the
regex that feeds it and the sampling rule are owned by
[Performance & Reliability Standards §3.4](../core/14-performance-standards.md); the browser only
decides how to say it.

### 6.2 The tree view

The fourth view mode ([`tree_view.dart`](../../app/lib/src/ui/tree_view.dart), state in
[`tree_state.dart`](../../app/lib/src/state/tree_state.dart)) is an expandable hierarchy inside one
pane, with the Details columns and keyboard expand/collapse. It is **one flat `ListView` over a
flattened forest** rather than a scrollable per level, so a deep tree costs what any other long
listing costs. The view-mode comparison table lives with
[Explorer design § View Modes](../core/20-explorer-design.md#-view-modes).

Two properties are worth knowing here because they are the opposite of how the flat listing works:

- **A folder's listing is fetched on first expand and kept across collapse**, so re-opening costs
  nothing. The set of open folders is session-only on purpose — a tree that reopened forty folders
  at launch would issue forty listings. Selection likewise spans folders, which the flat pane's
  per-folder selection cannot express, so the tree carries its own.
- **Every row resolves its path from the folder it was listed from, never from `state.path`.** The
  tree holds many listings at once, so "the pane's current path" is not an answer to "where is this
  row" — in this view `state.path` is only the root the tree hangs from. That is the v0.5.0
  stale-listing race written down as an invariant rather than re-fixed, and it is the thing to
  preserve when adding an operation to this view.

## 7. Relationship to the OS mount

The explorer and the mount are **complementary**:

- **Explorer** = primary, fast, in-app file work (drag-drop, server-side moves, jobs).
- **Mount / system Files** = a convenience so the remote is reachable in *other* apps; slower for
  upload/move due to VFS. The UI nudges heavy file work back into the explorer.

**A mount can keep its letter.** rclone's `*` takes the next free drive letter, which is right for a
one-off and wrong for a drive you have shortcuts, scripts or muscle memory pointed at — mount two
remotes in the other order and yesterday's `K:` is today's `L:`. The mount dialog therefore offers
*"Always mount this on K:"* (or, with Auto selected, *"Reuse whichever letter this mount gets, next
time"*), and a ticked box pins the mount point in
[`mount_letters.dart`](../../app/lib/src/state/mount_letters.dart). Three details are deliberate: the
pin is keyed by the **full fs** (`gdrive:` and `gdrive:work` hold different letters instead of
fighting over one), it is written **after** the mount succeeds and to the letter rclone *actually*
used — so ticking the box with **Auto** selected means "put it back where it landed" — and unticking
forgets the pin rather than leaving a stale one behind. Opening the dialog preselects a pinned letter,
and stays silent when there is none rather than resetting your last choice to Auto.

On **mobile** there is no equivalent of mount yet: the per-remote **"Show in Files"** toggle
(`DocumentsProvider` / File Provider) is designed but not built — see
[02-product-context](../core/02-product-context.md), which owns that status. The in-app explorer is
therefore the *only* surface on a phone, as well as the primary one.

---

## RC surface used (quick map)

`config/providers · config/create · config/update · config/delete · operations/list · operations/stat
· operations/mkdir · operations/copyfile · operations/movefile · operations/deletefile ·
operations/copyurl · operations/purge · operations/publiclink · operations/fsinfo · operations/about
· operations/size · operations/check · sync/copy · sync/move · sync/sync · sync/bisync · core/stats ·
core/bwlimit · job/status · job/stop`

`operations/list` is also the collision probe behind §5.1, and `operations/check` is what makes the
§5.2 preview trustworthy — `core/transferred` would have been the obvious source and is a capped ring
that silently loses entries. [External Integrations](../core/10-external-integrations.md) owns the
per-method contracts and that trap.

**Related:** [App Structure & Layouts](../core/05-app-structure.md) ·
[Core Architecture](../core/08-core-architecture.md) · [Design System](../core/06-design-system.md) ·
[Features Index](features-index.md)
