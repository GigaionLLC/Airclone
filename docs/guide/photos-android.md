# Backing up your photos (Android)

Airclone can copy your camera roll to a cloud remote on a schedule, in the background,
without you opening the app. This page covers that feature end to end.

It is **Android only**. The section does not exist on Windows, macOS, Linux or iOS. On
those platforms, use [Back up a folder](backup.md) instead — it does the same job for a
folder you choose, with the same copy-only promise.

| Platform | Photo backup |
| --- | --- |
| Android phone | Yes |
| Android tablet | Yes |
| Android TV | The section is shown, but a television has no camera roll to copy |
| Windows, macOS, Linux | Not shown — use [Back up a folder](backup.md) |
| iOS | Not shown |

## What it does, and what it will not do

The section's own description, in the app, is:

> Copies your camera roll (and any folders you add) to a remote, on a schedule. Copy only
> — nothing on the phone is ever moved or deleted.

That is the whole promise, and it is enforced in code rather than left to the settings you
happen to have:

- **It only ever copies.** A photo backup cannot be a move or a sync. The copy-only
  setting is applied when the backup is saved, and applied again every single time it
  runs — so even a task edited by hand through the advanced dialog still runs as a copy.
- **It never deletes on the phone.** Nothing is moved out of the camera roll, and nothing
  is removed once it has been copied. Your phone's storage is not freed by this feature.
- **It does not delete at the destination either.** If you remove a photo from the phone,
  the copy on the remote stays. That is the point of a backup.
- **A replaced file is kept.** If a file at the destination is overwritten by a newer file
  with the same name, the old one is renamed aside rather than lost, so you can still get
  it back.

What it is *not*: it is not [Survive uninstall](config-and-devices.md), which is about
your rclone config rather than your photos, and it is not the config's own automatic
backups. Three different things, deliberately given three different names.

## Before you start

You need two things.

**A remote to copy to.** Photos go to a cloud remote you have already added. If you have
not added one, do that first — see [Getting started](getting-started.md).

**File access, granted to Airclone by Android.** Airclone reads your camera roll as a
folder on disk (`DCIM`), not through Android's photo picker. On Android 11 and later that
needs **All files access**. While it is missing, Airclone shows a tappable banner reading
`Allow file access to browse this device's storage`; tapping it opens Android's own
settings screen, where you grant it. Come back to Airclone and the banner disappears on
its own. On Android 10 and earlier, Airclone asks for the older storage permission with a
normal system prompt instead.

Without that permission the engine can only see Airclone's own folders, so a photo backup
has nothing to read.

## Set it up

1. Open **Settings**. On a phone that is the `Settings` tab in the bottom bar. On an
   Android tablet wide enough for the desktop layout (700 logical pixels or more),
   Settings is a dialog opened from the `Settings` button in the top bar.
2. Scroll to the **Automation** group. It is not hidden behind Advanced mode — it is
   visible to everyone, on every platform.
3. Under **Back up your photos**, tap **Set up photo backup…**.

The dialog asks three questions, in this order.

### Where

Tap **Choose…**. A picker opens, titled `Where to keep the photos`. Pick a remote from the
`CLOUD` section, browse into a folder if you want one, and tap **Select this folder**.

Airclone then shows the full destination it composed, and the note:

> Photos land in `Airclone/Photos/<device>` there, mirroring the folders below.

You cannot leave this blank. Saving without a destination shows
`Choose where to keep the photos first.`

### What

The camera roll is already in the list, shown as a chip labelled **Camera roll** (that is
the `DCIM` folder). Tap the **×** on a chip to drop it, or **Add folder** to add another.

Added folders must be on the phone's **internal storage**. Picking anything else — a cloud
remote, an SD card, a USB volume — is refused with
`Only folders on this phone's internal storage can be backed up here.` That is a refusal
rather than a fallback: a folder that is not under internal storage has no meaningful place
in a backup rooted there, and silently backing up the wrong thing would be worse than saying
no.

**Include videos** is a switch, and it is **on** by default. Its subtitle says why it
matters: "They are most of the bytes, and most of the first run." Videos are recognised by
file extension:

```
mp4 m4v mov 3gp 3g2 mkv webm avi mts m2ts ts mpg mpeg wmv
```

Turn the switch off and files with those extensions are skipped, in upper or lower case. A
video saved with some other extension will still be copied, because the only thing Airclone
looks at here is the name.

Nothing outside the folders in the list is copied. There is no "everything else" case.

Saving with an empty list shows `Add at least one folder.`

### How often

A single dropdown, with these choices:

| Choice | Meaning |
| --- | --- |
| `Every 1 hour` | Checked hourly |
| `Every 3 hours` | |
| `Every 6 hours` | The default |
| `Every 12 hours` | |
| `Every 24 hours` | |

Below it, the app repeats the constraint that applies by default:

> Runs in the background on Wi-Fi by default — see "Background on this phone" in Settings
> to change that.

Tap **Start backing up** to save. (Re-opening the dialog later titles it
`Edit photo backup`, and the button reads **Save**.)

A photo backup always runs in the background when it is due. There is no
`Also run while Airclone is closed` checkbox here — the one you may have seen in the
[Back up a folder](backup.md) wizard — because for a camera roll on a phone that is the
entire point, so it is always on.

## Where the photos land

On the remote, under the folder you picked:

```
Airclone/Photos/<device name>/DCIM/Camera/IMG_0001.jpg
```

Three things about that path are worth knowing.

**The device segment keeps phones apart.** Two devices backing up to one remote would
otherwise merge into each other's folders. The name comes from Android's own device name,
falling back to make and model, and characters that cannot appear in a path (`\ / : * ? " < > |`)
are replaced with `-`.

**The folder structure is mirrored, not flattened.** A file in `DCIM/Camera` on the phone
lands in `DCIM/Camera` under the device folder. Once you can add arbitrary folders, that is
the only honest layout — there is nothing to sort a screenshot by but where it came from.

**It is an ordinary folder.** Nothing about it is a special format. You can browse to it in
Airclone on any device, or in the provider's own web interface, and the files are just
files.

To get photos back, open that folder and copy out of it, the same as any other transfer —
see [Copying, moving and syncing](transferring.md). Inside **Saved tasks** the backup's row
also has a **Restore from this backup…** button, which opens the destination in the other
pane so you can copy from it.

## Wi-Fi, charging, and how background runs behave

Directly under the photo backup, in the same Automation group, is **Background on this
phone**. Two switches:

| Switch | Default | What it means |
| --- | --- | --- |
| `Only on Wi-Fi` | **On** | "Never on mobile data." |
| `Only while charging` | **Off** | Runs only while the phone is plugged in |

`Only on Wi-Fi` defaults to on because the headline background task on a phone is a camera
roll, and a large roll copied over cellular is a bill.

These are per-device settings, not per-task. Android applies them to the single shared
wake, so they govern everything Airclone runs in the background on this phone.

Above the switches, Airclone states what will actually happen, in the app's own words —
for example:

> Android wakes Airclone about every 15 minutes on Wi-Fi and runs whatever is due, even
> with the app closed. A task can start up to that long after its time, and Android may
> hold a wake back to save battery.

That sentence is the honest description of background work on Android, and it is worth
reading twice:

- There is **one** shared wake, roughly every 15 minutes. Android's own floor for periodic
  work is 15 minutes, so nothing can be more punctual than that.
- "Every 6 hours" therefore means "about every 6 hours, checked at the next wake after it
  falls due" — not to the minute.
- Android may delay a wake further when the phone is asleep, in battery saver, or off
  Wi-Fi. Airclone cannot override that, and does not pretend to.
- While Airclone is open on screen, the background wake stands aside and the app's own
  scheduler runs what is due instead. Seeing no background activity while you are looking
  at the app is normal.
- After you install or update Airclone, **open it once**. Until the app has run at least
  once, Android has nothing registered to wake into.

### Running it now

When something is scheduled, a **Run due tasks in background now** link appears under the
status line. It queues one background run immediately, and it deliberately **ignores the
Wi-Fi and charging switches** — you asked for it now, on whatever connection you are on.
If mobile data is a concern, use **Run now** on the backup's own card instead, which runs
in the app where you can watch it.

## Checking on it

Once a backup exists, the section shows a card instead of the setup button:

| Row | What it shows |
| --- | --- |
| `To` | The full destination path |
| `From` | The folders being copied |
| `Videos` | `included` or `skipped` |
| `Runs` | The schedule, e.g. `Every 6 hours` |
| `Next` | When it is next due, or `due now` |
| `Last run` | How long ago, and `ok` or `failed` with the error |

with buttons **Edit…**, **Run now** and **Remove**.

Below the switches, a status line reports what Android itself holds: `Registered with
Android` (with the next wake, when Android has decided one) or `Not registered with
Android`, plus the outcome of the last background wake — `ok`, `a task failed`, or `could
not start`, with whatever detail the run produced.

Elsewhere:

- **Transfers** (the middle tab on a phone) shows the copy while it is running, with
  progress.
- The scheduled-task list at the top of the Automation group includes the backup, named
  `Photo backup`, with its schedule and last outcome.
- **Saved tasks** holds the same task if you want the full editor, restore, or version
  cleanup.

### Notifications

While a transfer runs, Android shows an ongoing notification — `Transferring files` for a
run you started in the app, `Running scheduled tasks` for a background wake. On Android 13
and later, Airclone asks for notification permission the first time a transfer starts, not
at launch. If you decline, transfers still run exactly as before; you just do not see the
progress notification.

### The first run is the big one

The first run copies everything; later runs copy only what is new, because a copy skips
what the destination already has.

On Android 12 and later the system usually refuses a background wake the extended runtime a
long copy needs, so Airclone caps that run so it ends cleanly instead of being killed
mid-copy. A large first backup then continues at the next wake, and the one after, picking
up where it stopped. It is not stuck, and nothing is copied twice. If you would rather get
it over with, plug the phone in, join Wi-Fi, open Airclone and use **Run now** — a run
started from inside the app is not held to the same limit.

## Turning it off

Tap **Remove** on the card. Airclone confirms with:

> **Stop backing up photos?**
> The schedule is removed. Nothing already copied to the remote is touched, and nothing on
> the phone is either.

Choose **Keep** to change your mind, or **Remove** to stop. Removing the backup is the only
thing that happens — your photos stay where they are, on the phone and on the remote.

If you only want to pause the cellular cost rather than stop backing up, turn on
`Only on Wi-Fi` (or `Only while charging`) instead and leave the backup in place.

## The permissions Airclone actually asks for

| Permission | When you are asked | If you say no |
| --- | --- | --- |
| All files access (Android 11+) | From the in-app banner, `Allow file access to browse this device's storage`, which opens Android's settings screen | Airclone can only see its own folders, so the camera roll cannot be read |
| Storage (Android 10 and earlier) | A system prompt, in place of the above | Same |
| Notifications (Android 13+) | The first time a transfer starts | Transfers still run; you lose the progress notification |
| Camera | Only when you open the QR scanner to import a config | Photo backup is unaffected — it never uses the camera |
| Internet | Never prompted; granted at install | — |
| Foreground service (data sync) | Never prompted; granted at install | Used to keep the app and the engine alive while a transfer runs |

Airclone does **not** request Android's "Photos and videos" media permission. It reads
`DCIM` as a folder on disk, which is why it asks for file access instead.

Airclone sends nothing anywhere except to the remote you chose. There is no analytics and
no phone-home; see [PRIVACY.md](../../PRIVACY.md).

## When something does not happen

A few symptoms with plain causes:

- **Nothing has run at all.** Check the status line says `Registered with Android`. If it
  says it is not registered, open Airclone once and return to Settings.
- **It runs hours late.** Expected. The shared wake is about every 15 minutes and Android
  may delay it; a "daily at a set time" precision does not exist for background work on
  Android.
- **It never runs away from home.** `Only on Wi-Fi` is on by default.
- **It stops overnight.** Battery optimisation and battery saver both hold wakes back.
  Charging overnight, with `Only while charging` off, is the friendliest arrangement.
- **A run failed.** The `Last run` row and the status line both carry the error verbatim.
  [Troubleshooting](troubleshooting.md) covers reading those, and the `Problem report` in
  Settings → Diagnostics collects the evidence locally if you need it.

## See also

- [Back up a folder](backup.md) — the same copy-only backup, for any folder, on any
  platform
- [Scheduled tasks](scheduling.md) — what a schedule means on each platform, and the
  safety breaker that can stop scheduled runs
- [Copying, moving and syncing](transferring.md) — running a transfer by hand, including
  copying photos back
- [Getting started](getting-started.md) — adding your first remote
- [All guide pages](README.md)
