# Copying, moving and syncing

Moving files between a folder on your machine and a cloud remote — or between two
remotes — is what Airclone is for. This page explains the four transfer modes, the
prompts that stand between you and a mistake, and the transfers list that shows you
what is happening.

One of the four modes deletes files. Read [The four modes](#the-four-modes) before
using Sync.

## The four modes

These are the four radio buttons in the transfer dialog, with the one-line
description the app prints under each.

| Mode | What the app says | What it deletes |
|---|---|---|
| `Copy` | "Add source files to the destination." | Nothing. |
| `Move` | "Copy, then delete from the source." | The **source** files, after they land. |
| `Sync` | "Make destination match source (deletes extras)." | Anything on the **destination** that is not on the source. |
| `Two-way sync` | "Keep both locations mirrored — changes flow both directions." | Either side, to match the other. Advanced mode only. |

The difference that matters:

- **Copy** only ever adds. A file that exists at the destination and not at the
  source is left alone. This is the safe default, and it is what the dialog opens
  on.
- **Move** is a copy followed by a delete at the source. Nothing at the destination
  is removed, but the source folder is emptied of what moved.
- **Sync** makes the destination *identical* to the source. Files that exist only
  at the destination are deleted permanently. If you point a Sync at the wrong
  source — or at a source that is empty because a drive is offline — it will empty
  the destination. This is the mode that can lose data.
- **Two-way sync** keeps two folders mirrored, with changes flowing both ways. Its
  first run is different from every run after it: see
  [Two-way sync](#two-way-sync-and-its-baseline).

Airclone will not let a one-way Sync run without saying this to you first. See
[The Sync confirmation](#the-sync-confirmation).

## The quick ways to move files

For everyday copying you do not need the transfer dialog at all.

**Copy, cut and paste.** Select files, `Copy` or `Cut`, open the destination
folder, `Paste`. On the desktop shell those are `Ctrl + C`, `Ctrl + X` and
`Ctrl + V`, and they are also in the pane's command row and the right-click menu.
On a phone, long-press to select, use `Copy` or `Cut` in the selection bar that
replaces the pane header, then open the destination and use the `+` button →
`Paste here` (it only appears when the clipboard holds something).

**Copy to… / Move to…** In the right-click menu on any file or folder. Both open a
destination picker rather than using the clipboard.

**Copy to other pane / Move to other pane.** In the pane's command row once you
have a selection, in the dual-pane (commander) layout. These are the two-pane
equivalent of the above.

**Drag and drop.** On Windows, macOS and Linux you can drag rows from one pane to
the other, and drag local files in from — or out to — the operating system. An
in-app drag between panes is always a **copy**, never a move. Drag and drop is
**not available on Android or iOS**, including an Android tablet running the
desktop layout: the long-press gesture a drag would need is the one that opens the
context menu.

All of these run through the same conflict check described in
[When a name already exists](#when-a-name-already-exists).

## The transfer dialog

The dialog titled `Transfer options` is where Sync, filters and dry runs live. It
shows `From` and `To` at the top so you can check the direction before anything
runs, and it has three tabs: `Settings`, `Filters` and `rclone cmd`.

Where to open it:

| Platform | Path |
|---|---|
| Desktop shell (Windows, macOS, Linux, and any window 700px or wider) | Pane `Tools` menu → `Copy / Move / Sync this folder…` |
| Desktop shell, with files selected | The command row's `Copy / Move / Sync selection… (filters · dry-run)` button |
| Phone shell (below 700px, and Android TV) | Pane header `⋯` → the collapsed `ADVANCED` group → `Copy / Move / Sync this folder…` |

With nothing selected it transfers the **whole current folder**. With a selection it
transfers **the selected items**. The destination is the other pane when one has a
location open; otherwise you are asked to pick one.

You do **not** need Advanced mode to reach this dialog, or to use Sync, filters or
dry runs in it. Advanced mode's own description says otherwise; the only thing it
actually hides here is the `Two-way sync` mode.

### Settings tab

For Copy, Move and Sync:

| Option | What it does |
|---|---|
| `Skip newer files` | Leaves a destination file alone when it is newer than the source. |
| `Skip existing files` | Leaves anything that already exists untouched. |
| `Keep replaced files` | Renames a file that would be overwritten or deleted with a `.replaced` suffix instead of losing it. This is what makes a Move or Sync recoverable. |
| `Dry run` | Reports what would happen and changes nothing. |
| `Abort if more than N files would be deleted` | Sync only. Leave it empty for no cap. |
| `Compare by` | `(default) — size + mod-time`, `Size only`, or `Checksum`. Checksum is slower and certain. |
| `Parallel transfers` / `Parallel checkers` | Blank means rclone's own default. |
| `Sort order` | Default order, name, size or modification time, ascending or descending. |
| `Track renames` | Detects a file that was only renamed instead of transferring it again. |
| `Immutable` | Aborts rather than modify any file that already exists. |

The delete cap deserves a note. It is a safety guard, not a tuning knob: it aborts
the whole run rather than exceed the number you set, so a source that has gone
missing cannot quietly empty the destination. An empty field means no cap. A
negative number is treated as no cap too, because a negative value means *unlimited*
to rclone — the opposite of what typing one would suggest.

### Filters tab

Three fields, one glob pattern per line; blank lines are ignored.

| Field | Effect |
|---|---|
| `Include` | Only transfer files matching these patterns. |
| `Exclude` | Skip files matching these patterns. |
| `Filter` | Combined rules, each line prefixed `+` to include or `-` to exclude. |

Patterns look like this:

```
*.jpg
photos/**
```

### rclone cmd tab

Shows the exact rclone command your current choices amount to, with a `Copy`
button. Nothing on this tab changes the transfer; it exists so you can run the same
thing yourself from a terminal, or check what the options add up to before running
them.

## Dry runs

A dry run reports what would happen and changes nothing. There are two ways to get
one, and they show you different things.

**The `Dry run` button in the dialog** (and the `Dry run` checkbox) starts a real
run with dry-run set. It appears in the transfers list like any other transfer,
with `(dry run)` after the source name, and finishes as `Done`. You get the totals,
not a list of what would have been deleted.

**The preview dialog** shows the deletions explicitly, and it appears on one path
only: the mark-then-sync gesture described below. It is headed
`What this Sync would do` and breaks the result into buckets — how many files would
be deleted at the destination, how many overwritten, how many copied across, how
many are already identical, and how many could not be compared at all. Each bucket
opens to show the file names. If the deletions alone would trip your delete cap, it
says so, because that means the sync would abort rather than run. Its go-ahead
button is labelled `Run it, deleting N` when there are deletions, and the preview
itself counts as the dry run — choosing to go ahead runs the real thing.

When nothing would change, the dialog says so and the run button is disabled.

## Syncing into a folder you are standing in

In Advanced mode, right-click (long-press on a touch screen) a folder and choose
`Set as sync source`. Navigate anywhere else — another folder, another remote — and
the right-click menu there offers `Sync <source> into this folder…`, or
`Sync <source> to here…` on empty space. The item names the source, in red, because
what is about to overwrite the folder was chosen somewhere else, possibly minutes
ago.

Before offering you any options, Airclone checks the marked source, and refuses
outright under a dialog titled `Nothing was synced` when:

- the source and destination are the same folder, or one is inside the other;
- the source cannot be read — it may be offline, renamed or deleted;
- the source is empty, which would delete everything at the destination.

That last refusal also runs the slow way if you decline a preview: Airclone counts
what is actually in the source before a real Sync, because a tree of empty folders
lists as "not empty" and would still wipe the destination. Both checks are
deliberately fail-closed. If Airclone cannot see what is there, it does not write
over it.

## The Sync confirmation

A real, non-dry one-way `Sync` started from the dialog always raises a confirmation
first, titled `Sync deletes destination files`. It offers three choices:

- `Cancel`
- `Dry run first` — turns this run into a preview
- `Run sync` — in red

Copy and Move do not raise it; they do not delete at the destination.

This confirmation appears only when you press Run on a transfer that is about to
happen. **Defining a saved task does not raise it**, deliberately: nothing runs at
the moment you save a task, and the `Dry run first` nudge would otherwise be baked
into the saved task, turning every future scheduled run into a silent no-op. Saved
and scheduled tasks have their own guards — see [scheduling](scheduling.md).

## Two-way sync and its baseline

`Two-way sync` appears in the mode list only in Advanced mode.

Its first run for a given pair of folders is not an ordinary sync. It establishes a
baseline, and where the two sides differ, one side's file overwrites the other's.
That cannot be undone. So an ad-hoc two-way sync started from the browser raises its
own confirmation, `Establish two-way baseline`, naming `Path1` and `Path2` and
offering `Cancel`, `Dry run first` or `Establish baseline`.

Two settings decide who wins:

- `First-run baseline winner` — which side wins during that one-time baseline.
  `path1` is the "From" / active side; the alternatives are the other side, or
  newer, older, larger or smaller.
- `When both sides changed` — how a later conflict is settled. The default keeps
  both versions, numbered; you can also prefer newer, older, larger, smaller,
  path1 or path2.

There is also a `Max delete` percentage slider — a run that would delete more than
that share of files aborts — plus `Check access first` (requires marker files on
both sides before running) and `Create empty directories`.

If a two-way sync later fails complaining about a prior listing, its baseline has
been lost. The transfers list recognises that error and says so, pointing at
`Saved tasks` → `Re-establish baseline…`. The tip inside the confirmation dialog is
worth taking: save a two-way pair as a task, and Airclone tracks the baseline for
you, so later runs are ordinary two-way syncs.

## When a name already exists

When you paste, drop or `Copy to…` something whose name already exists in the
destination folder, Airclone stops and asks. The dialog is headed
`N of M already exist here` and lists the colliding names. Your choices:

| Button | Result |
|---|---|
| `Cancel` | Nothing is transferred. Your selection is kept, so you can retry. |
| `Skip these` | The colliding names are dropped; everything else transfers. |
| `Replace` | The existing files are overwritten. |
| `Keep both` | The incoming files are renamed — `report.pdf` becomes `report (2).pdf`. |

Nothing is overwritten silently on these paths. If Airclone cannot read the
destination folder to check for collisions, it transfers nothing and tells you so
rather than assuming the folder is empty.

This prompt does **not** appear for a run started from the transfer dialog. There,
reconciliation is the mode's job: Copy and Sync overwrite differing files unless you
tick `Skip existing files` or `Skip newer files`, and `Keep replaced files` is what
preserves the version being replaced.

## Watching transfers

Every transfer, however it was started, appears in the same list.

| Platform | Where |
|---|---|
| Desktop shell | The dock across the bottom. Toggle it from the top bar (`Show transfers` / `Hide transfers`). It is open when the app starts. |
| Phone shell and Android TV | The `Transfers` tab. |

The header reads `Transfers` followed by counts — `N active · N queued · N done` —
and holds the pause button and `Clear finished`. While anything is moving, a strip
above the list shows the live rate, the total transferred, how many files are in
flight and an ETA.

Each row shows a type pill (`Copy`, `Move`, `Sync`, `Delete`, `Upload`, `Download`,
`Command` or `Archive`), the source and destination, a progress bar, bytes, speed
and remaining time, and a status chip: `Queued`, `Running`, `Done`, `Failed` or
`Canceled`. A row moving several files at once lists three of them and offers
`+N more — show all`.

Row controls:

- While it is queued or running, a stop button — tooltip `Cancel` for a queued
  transfer, `Stop` for a running one. Cancelling a queued transfer simply drops it;
  stopping a running one asks the engine to stop the transfer. Files already transferred
  stay transferred.
- Once it has finished, `Dismiss` removes the row. A failed or cancelled transfer
  also gets `Retry`, which runs the same transfer again as a fresh row.
- `Clear finished` in the header removes every finished row at once.

On the desktop the dock is resizable: drag its top edge, or double-click the handle
(or use the chevron at its right) to expand it and put it back. The second tab,
`Recent activity`, is a read-only list of recently completed files reported by the
engine, with a `Refresh` button.

### What pause actually does

The pause button's tooltip states it exactly:
`Pause queue (queued transfers wait; running ones finish)`.

So:

- **Queued** transfers are held until you press resume.
- A transfer that is already **running is not interrupted**. It is not suspended,
  and there is no way to resume a half-finished transfer — it simply runs to
  completion. If you want a running transfer to stop, use its `Stop` button.
- The pause is for this session only. It is not remembered across a restart, on
  purpose: a queue that came back paused after launch would be a trap.
- Pause has visible effect only when transfers are actually queueing. Out of the
  box, `Concurrent transfers` is `Unlimited`, so everything dispatches at once and
  there is rarely anything in the queue to hold.

### Limiting how many run at once

Settings → `Transfers` → `Concurrent transfers`: "Run a limited number of transfers
at once; the rest wait in the queue." The choices are `Unlimited` (the default),
then `1 at a time` through `8 at a time`.

This setting requires **Advanced mode**. On a phone the whole `Transfers` group in
Settings only appears in Advanced mode; on the desktop the group is always there
(for the downloads folder) but this row is not.

Raising the limit immediately releases whatever is waiting. Console commands and
archive operations do not occupy a transfer slot, so a long-running command cannot
stall your copies.

## Bandwidth limits

The speed control sits in the **desktop** top bar — the icon showing `∞` or the
current rate, tooltip `Bandwidth limit`. Its menu offers `Unlimited`, `1M/s`,
`5M/s`, `10M/s`, `50M/s` and `100M/s`, plus `Schedule…`.

The limit is global. It applies to everything the engine is doing, not to one
transfer, and it takes effect immediately on transfers already running.

`Schedule…` opens `Bandwidth schedule`, a daily timetable: switch on
`Apply a daily bandwidth schedule`, then add windows, each a time of day and a rate
(the schedule offers finer rates than the menu, down to `256k/s`). A window applies
from its time until the next one — for example `08:00 → 512k`, `18:00 → Unlimited`.
The dialog states its own limit plainly: **limits apply only while Airclone is
open.**

There is no bandwidth control in the phone shell. On Android, a scheduled task can
be restricted to Wi-Fi instead — see [scheduling](scheduling.md).

## What is not here

- **Resuming a transfer you stopped.** Stopping is a stop, not a pause. Start it
  again (or use `Retry`) and rclone skips what already matches at the destination,
  so the second run is usually much shorter — but it is a new run.
- **An undo.** Nothing Airclone deletes goes to a recycle bin. The protection
  against a bad Sync is the confirmation, the dry run, the delete cap and
  `Keep replaced files`, applied before the run, not after.
- **A transfer that survives the app on macOS, Linux or iOS.** Only Windows and
  Android can run saved tasks with Airclone closed; see [scheduling](scheduling.md).
  An ad-hoc transfer started from the browser needs the app running on every
  platform.

## Related pages

- [Getting started](getting-started.md) — installing, adding your first remote
- [Browsing your files](browsing.md) — panes, tabs, selection and the clipboard
- [Backing up a folder](backup.md) — copy-only transfers that keep old versions
- [Scheduled and saved tasks](scheduling.md) — running transfers on a timer, and
  the guards that stop an unattended Sync
- [Troubleshooting](troubleshooting.md) — when a transfer fails
