# Backing up a folder

A backup in Airclone is one folder copied somewhere else, on a schedule, in a way
that cannot delete anything at the destination. You answer three questions once,
and the app keeps a copy of that folder for you.

This page covers the **Back up a folder** wizard, where the files land, what a
backup will and will not do, how replaced files are kept as versions, and how to
restore.

It does not cover the Android camera roll — that is a separate feature, **Back up
your photos**, described in [Photo backup on Android](photos-android.md). It also
has nothing to do with the automatic copies of your rclone config, which are
covered in [Config and devices](config-and-devices.md).

## Where to find it

Open **Settings**, scroll to the **Automation** group, and press **Back up a
folder**.

That is the only way in. There is no toolbar button and no context-menu item for
it, on any platform.

| Platform | How Settings opens | Path |
|---|---|---|
| Windows, macOS, Linux | a dialog, from the gear in the top bar | Settings → Automation → **Back up a folder** |
| Android tablet, iPad, or any window 700px wide or more | a dialog, from the gear in the top bar | the same |
| Android phone, iPhone, Android TV | a tab at the bottom of the screen (a side rail on TV) | Settings → Automation → **Back up a folder** |

Automation is not hidden behind **Advanced mode**. You can create and run a backup
with Advanced mode switched off, which is the default.

## The three questions

The wizard is a single dialog with three numbered steps, a **Cancel** button and a
**Start backing up** button. Nothing happens until you press **Start backing up**.

### 1. What to back up

Press **Choose…**. A folder picker opens with the title **Which folder to back
up**. It lists the same places the sidebar does — **LOCATIONS** (folders you have
added), **DISKS** (drives it found) and **CLOUD** (your remotes) — then lets you
browse into folders. When you are standing in the folder you want, press **Select
this folder**. **Back to remotes** at the top left goes back to the list.

Once chosen, the button becomes **Change**.

### 2. Where to keep it

The same picker, with the title **Where to keep the backup**. This can be a cloud
remote, an external drive, or any other folder — the picker does not care which.

As soon as both folders are chosen, the wizard shows a faint line under this step:

```
Files will go to gdrive:Airclone/Backups/laptop/Projects
```

That is the real destination, shown before anything is created, so you are not
discovering it later by browsing.

### 3. How often

Two choices, as chips:

| Chip | What it means | Options |
|---|---|---|
| **Daily** (default) | once a day at a time you pick | **At** opens a time picker; 02:00 to start with |
| **Hourly** | at a fixed interval | **Every** → `hour`, `6 hours`, `12 hours` |

**Weekly is deliberately not offered here.** A backup that runs once a week is six
days stale by the time you need it. If you genuinely want a weekly backup, create
it here and then change its schedule in **Saved tasks** — the full schedule editor
does offer **Weekly**. See [Scheduled tasks](scheduling.md).

On **Windows** and **Android** there is one more control: a checkbox, **Also run
while Airclone is closed**, ticked by default. It appears nowhere else, because
nowhere else can honour it.

Underneath, the wizard states its own promise and what a schedule means on the
device you are holding:

> Backups only ever copy — they never delete anything at the destination. A file
> that gets overwritten is kept as an older version you can restore.

## What "on a schedule" means on your platform

| Platform | Runs automatically | With Airclone closed |
|---|---|---|
| Windows | yes | yes, while **Also run while Airclone is closed** is ticked |
| Android | yes | yes, ticked by default — but Android decides when to wake the app, so a run can start late |
| macOS | while Airclone is open; a run missed while it was closed starts once on next launch | no |
| Linux | same as macOS | no |
| iOS | the app states that scheduling is not available on this device yet | no — run it by hand from **Saved tasks** |

The wizard still asks "How often" on iPhone and iPad, and the schedule is saved,
but do not plan around it firing there. Open **Saved tasks** and press **Run**.

On Android, an hourly backup is not hourly to the minute. Android's own floor for
waking a background app is 15 minutes, and it will stretch further when the phone
is asleep, on battery saver, or off Wi-Fi. [Scheduled tasks](scheduling.md) goes
into this properly.

## Where the files land

```
<the folder you chose>/Airclone/Backups/<this device>/<the folder's name>
```

So backing up `D:\Projects` to a Google Drive remote from a machine called
`laptop` writes to `gdrive:Airclone/Backups/laptop/Projects`.

Three things are worth knowing about that path.

**`Airclone/Backups` is fixed.** Every backup from every device goes under the
same root, so a restore knows where to look and you can tell at a glance what put
those files in your cloud. Camera-roll backups sit beside it under
`Airclone/Photos`.

**The device segment is not decoration.** Without it, two machines backing up a
folder called `Documents` to the same remote would write into each other's files,
and the first sign of it would be a restore putting your laptop's files on your
desktop. The name comes from the machine's own host name on desktop, and from
Android's device name (falling back to make and model) on a phone — Android
reports the host name as `localhost` for everybody, which would have merged every
Android device into one folder. Characters a path cannot hold (`\ / : * ? " < >
|`) become `-`.

**The last segment is the folder's own name**, not its whole path — `Projects`,
not `D--Projects`. Back up a whole remote at its root and the remote's name is
used instead. Two folders from one machine therefore stay apart, unless they have
the same name, in which case they do not.

## What makes this a backup rather than a transfer

Airclone can already copy, move and sync folders, and it can save those as tasks.
A backup is a saved task with the dangerous options taken away — and taken away
for good. Three constraints are applied when the backup is created, and applied
again on every scheduled run, so a task edited by hand cannot come back as
something else under a backup's name.

| Constraint | Why |
|---|---|
| **Copy only** — never Sync, never Move | A sync deletes at the destination to match the source, so it would erase your history the moment the source lost a file, which is exactly when you need it. A move deletes the original, which is not a backup at all. |
| **Replaced files are kept** | An overwritten file is renamed aside rather than lost. This is what creates something to restore *from*. |
| **Never a dry run** | A backup that quietly reports instead of copying is the worst failure there is: it looks like it worked every night. |

Two consequences follow, and both surprise people:

- **Deleting a file on your computer does not delete it from the backup.** The
  backup keeps growing. That is intended; cleaning up is a separate, manual act
  described below.
- **A backup will never ask you to confirm a deletion**, because it never
  proposes one. The Sync warning you may have seen elsewhere in Airclone does not
  apply here. See [Copying, moving and syncing](transferring.md).

## While it runs, and afterwards

A backup run is an ordinary transfer. It appears in the **Transfers** dock at the
bottom of the desktop window, or the **Transfers** tab on a phone, with the same
progress and the same speed figures as anything else you copy.

The backup itself lives in **Saved tasks** (Settings → Automation → **Saved
tasks**), named `Back up <folder>`, with its schedule, when it is next due, and
how the last few runs went. From that row you can press **Run** to start it now,
**Edit schedule**, or **Delete** it. Deleting the task does not delete any backed-
up files.

One shared safety behaviour is worth knowing: if a *different* scheduled task
aborts because it would have deleted too much, Airclone stops **every** scheduled
task until a person presses resume, and that includes your backups. It shows as a
banner in **Saved tasks** and in Settings → Automation. This is explained in
[Scheduled tasks](scheduling.md).

If your rclone config is encrypted and still locked when a run comes due, the run
is skipped rather than failed, and the **Saved tasks** dialog says so.

## Versions

When a backup copies a file over one that is already at the destination, the old
one is not overwritten. It is renamed beside the new one with `.replaced` before
the extension:

```
report.pdf          <- the current file
report.replaced.pdf <- what was there before
```

They sit in the same folder, so you can find an old version by browsing to it and
copying it out like any other file.

### The retention window

Settings → Automation grows one extra row once you have at least one backup:

> **Keep replaced file versions for** — `no versions` · `7 days` · `14 days` ·
> `30 days` · `60 days` · `90 days` · `365 days`

The default is **30 days**. There is no "forever" option on purpose: a version
history that only grows is a bill nobody agreed to. `no versions` is a legitimate
choice if you are short on space — it means a cleanup may remove every version
whose current file is still there.

Two things this setting does *not* do:

- **Nothing is deleted on a timer.** The window only decides what a cleanup is
  allowed to consider. If you never press the cleanup button, nothing is ever
  removed.
- **It is one setting for all backups on this device**, not one per backup. The
  cleanup itself is per backup.

## Cleaning up old versions

In **Saved tasks**, a backup's row carries a broom icon, **Clean up old
versions…**. Pressing it lists the backup folder, works out what could go, and
opens a dialog titled **Clean up old versions** showing you the answer first.

**The dialog is the dry run.** The list you are looking at was produced by exactly
the code that will do the deleting, not by a separate preview that could disagree
with it. Nothing is deleted until you press **Delete them**. **Cancel** closes it
with everything intact.

What it will never delete:

- **A current file.** Only files carrying the `.replaced` marker are ever
  candidates, and the marker has to be a whole segment of the name — a file you
  genuinely called `replaced.txt` is not a version.
- **A version whose current file is no longer there.** That version is not a
  redundant old copy any more; it is the last copy in existence, so it stays. The
  dialog says this too.
- **Anything, if it could not read the folder.** If the listing fails you get
  "Could not read the backup folder, so nothing will be deleted." Deleting on a
  guess is precisely what must not happen.
- **Anything at all, if more than 500 versions come up at once.** It refuses the
  whole pass rather than deleting the first 500, tells you the count, and suggests
  you look at the folder yourself. A pass that large is more often a mistake than
  a real backlog.

After a successful cleanup, a message tells you how many versions were deleted and
how much space that freed. If the engine fails part-way through, it stops at the
first failure and tells you how many it had already deleted.

The cleanup reads the whole backup folder, including subfolders, before it can
show you anything. On a large backup over a slow connection that takes a moment.
It only lists — it does not download your files.

## Restoring

There is no separate restore engine, and that is deliberate. A backup destination
is an ordinary folder on an ordinary remote, so restoring is browsing to it and
copying back — which means it inherits the conflict prompt, the transfer options
and the progress display everything else already has.

In **Saved tasks**, press the restore icon on the backup's row, **Restore from
this backup…**. Airclone opens the backup's destination in the *other* pane and
says "Backup opened in the other pane. Copy from it to restore." The other pane,
not the one you are standing in, because the pane you are in is where you are
restoring *to*.

That means you need two panes visible:

| Platform | Do this first |
|---|---|
| Desktop (and any window 700px or wider) | Airclone opens in single-pane view. Turn on **Dual-pane view (commander)** in the top bar, or the second pane is loaded but not on screen. |
| Phone | Open the pane's **⋯** menu and choose **Split view** under **Layout**. |

Then browse the backup to the file or folder you want, select it, and copy it
across — `Copy to other pane`, drag and drop, or Copy and Paste. See
[Copying, moving and syncing](transferring.md) for the mechanics.

If anything you are copying back has the same name as something already in the
destination, Airclone stops and asks, with a dialog headed **N of M already exist
here** and four choices: **Cancel**, **Skip these**, **Replace**, **Keep both**.
Restoring over live files is a write, and it asks before overwriting them.

To restore a specific old version, copy the `.replaced` file out and rename it
afterwards — Airclone does not rename it back for you.

If the remote a backup was written to has since been deleted from your config, the
restore button tells you which remote is missing by name instead of opening an
empty pane.

The restore and cleanup buttons appear on camera-roll backups as well, and behave
the same way — see [Photo backup on Android](photos-android.md).

## If something looks wrong

- **The backup has never run.** Check the platform table above. On macOS and
  Linux nothing runs while the app is closed; on iOS nothing runs automatically at
  all. On Windows and Android, check that **Also run while Airclone is closed** is
  ticked on the task's schedule.
- **Everything scheduled has stopped.** Look for the paused banner in **Saved
  tasks** — one task tripping the delete guard stops them all until you resume.
- **The backup folder keeps growing.** It is meant to. Deletions at the source are
  never copied forward, and versions are only removed when you ask. Use **Clean up
  old versions…**.
- **A cleanup refused.** Read which refusal it was: unreadable folder, or more
  than 500 candidates. Neither deletes anything.

More in [Troubleshooting](troubleshooting.md).
