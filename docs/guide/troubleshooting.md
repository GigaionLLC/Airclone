# When something goes wrong

This page maps symptoms to causes. Most of the entries are not bugs: they are
Airclone refusing to do something, or a platform limit it cannot argue with. In
each case the page says what actually happened and what to do next.

One thing to know before anything else. **Airclone does not report problems to
anyone.** There is no crash reporting, no analytics, no background upload. If
something fails, the evidence is on your device and stays there until you choose
to hand it over. The place it lives is described in the next section.

---

## Start here: the Problem report

Airclone keeps a local record of failures. Open it at:

- **Desktop (Windows, macOS, Linux):** the `Settings` button at the right of the
  top bar → scroll to the **Diagnostics** group → **Problem report**. Settings is
  a dialog here.
- **Phone and Android TV:** the **Settings** tab → scroll to **Diagnostics** →
  **Problem report**. Settings is a tab, not a dialog, but the contents are the
  same.

The section shows either `Nothing recorded this session.` or a count such as
`12 events recorded, 3 errors.` Expand it to read the entries, or use the
buttons:

| Button | Platform | What it does |
|---|---|---|
| `Copy report` | all | Puts the whole report on the clipboard |
| `Save report…` | Windows, macOS, Linux | Asks where to save `airclone-diagnostics.txt` |
| `Share report` | Android, iOS | Hands the same file to the system share sheet |
| `Clear` | all | Empties the record |

What the report contains: a short header (app version, platform and OS build,
how the app was installed, engine version and engine mode), then the recorded
events oldest first.

What it does not contain: secrets. Passwords, tokens, `Authorization` headers,
credentials embedded in a URL, email addresses and your home-directory name are
stripped **as each event is recorded**, not when you export it — so no copy or
save path can leak by forgetting. The report says so itself, and still asks you
to skim it before sharing. That request is worth honouring: redaction is a
filter, not a proof.

Two limits to expect:

- The record is **held in memory only** and is capped at 300 events. It starts
  empty every time Airclone launches, so capture it while the problem is fresh.
  Closing the app loses it.
- It records failures, not everything. A transfer that succeeded leaves no
  entry; the `Recent activity` tab of the transfers dock is where past runs show
  up on the desktop, and the phone's `Transfers` tab has a `Recent` segment.

---

## A scheduled task did not run

Scheduling behaves genuinely differently per platform, and most "it did not run"
reports are one of the rows below rather than a fault.

| Platform | What Airclone promises |
|---|---|
| Windows | Scheduled tasks run in the background, even with Airclone closed. |
| Android | Scheduled tasks run in the background, even with Airclone closed. |
| macOS | Scheduled tasks run while Airclone is open. A run missed while it was closed starts once on next launch. |
| Linux | Scheduled tasks run while Airclone is open. A run missed while it was closed starts once on next launch. |
| iOS | Scheduling is not available on this device yet — saved tasks still run when you start them by hand. |

Settings → **Automation** prints the line for the device you are holding. Work
through the checks below in order.

### 1. Was Airclone closed, on a platform that needs it open?

On **macOS and Linux** nothing fires with the app closed. A missed slot is
caught up once on the next launch — once, not once per missed slot. On **iOS**
there is no scheduling at all; saved tasks are still there and still run from
`Run` in the `Saved tasks` dialog.

### 2. Is `Also run while Airclone is closed` ticked?

This checkbox only exists on **Windows and Android** — the two platforms with
background execution. Without it, even those two run the task only while the app
is open. Find it in the schedule editor: Settings → Automation → `Saved tasks` →
a task's `Edit…` → the schedule section.

The `Back up a folder` wizard ticks it by default on Windows and Android.

### 3. Is scheduling paused?

If a scheduled one-way `Sync` aborts because it would have deleted more files
than its cap, Airclone stops **every** scheduled task, not just that one, and
stays stopped across restarts. You will see a red band headed **`Scheduling is
paused`** in the `Saved tasks` dialog and in Settings → Automation, naming the
task, the time, and rclone's own words for the failure. A `Resume` button sits
beside it.

This is deliberate and there is no auto-resume and no timeout. The causes of an
unexpectedly large deletion are environmental — a drive that is not mounted, an
expired token, a folder renamed at the source — and those causes are rarely
confined to the one task that noticed. The pause exists so that a person looks
before anything else runs. Check that the source is where you expect it, then
press `Resume`.

A repeating one-way `Sync` that has no cap of its own gets one when it runs:
**100 files**.

### 4. Did the run refuse itself?

Open `Saved tasks` and look at the task's history. A scheduled one-way `Sync`
whose source is empty **or cannot be read** is refused before it starts, and the
refusal is recorded as:

```
Refused to run: the source is empty or could not be read, and a Sync would have
deleted the destination to match it.
```

Unreadable counts as unsafe on purpose. A person watching a preview can be told
"could not read that" and decide; a timer at 3am cannot. This applies only to
`Sync`. Backups are copy-only, so an empty source is a harmless no-op and they
are exempt.

### 5. Was the engine locked or down at the time?

The scheduler cannot run anything without the engine. When a task came due while
the engine was unavailable, the `Saved tasks` dialog shows:

> A scheduled task was due while the engine was locked — unlock to let it run.

That usually means an encrypted rclone config waiting for its password. See
[A transfer will not start](#a-transfer-will-not-start) below.

For a **background** run on an encrypted config there is no one to type the
password, so Airclone blocks you from enabling `Also run while Airclone is
closed` and says:

> This config is encrypted and no password is stored, so a background run could
> never unlock it. Enable "Remember config password" in Settings first.

That setting is in Settings → **Security**.

### 6. It ran, but late

Two mechanisms exist, and which one a schedule gets is decided by whether it
names a wall-clock time.

- **Windows, `Daily` or `Weekly`:** its own Task Scheduler entry, firing at the
  time you chose.
- **Windows, `Interval`:** one shared job, named `Run due tasks`, that wakes
  every 15 minutes and runs whatever is due. So an interval task can start up to
  fifteen minutes late. There is no setting for how often that job wakes.
- **Android, every schedule:** Android has exactly one periodic worker, so even
  a "daily at 09:00" task is served by the shared wake and will not fire at
  09:00 on the nose. Android's own floor is 15 minutes. The app's wording:
  "Android wakes Airclone about every 15 minutes and runs this when it is due,
  so it can start late — and later still if the phone is asleep, on battery
  saver, or off Wi-Fi."

On Android, Settings → Automation → **Background on this phone** also has two
switches that will hold a run back if they are on: `Only on Wi-Fi` ("Never on
mobile data.") and `Only while charging`. The status line under them reports
what Android currently thinks — `Registered with Android · next wake …` or
`Not registered with Android`, plus the outcome of the last background wake
(`ok`, `a task failed`, or `could not start`). There is also
`Run due tasks in background now`, which queues a real background wake so you
can test the path rather than guess at it.

### 7. Where to look on Windows

Airclone's entries live in the **`Airclone` folder** in Task Scheduler. Only the
shared interval job carries a readable name there — **`Run due tasks`**. An
exact-time task is registered under a generated identifier, so do not expect to
find your task's friendly name in that list.

More on all of this in [scheduling](scheduling.md) and [backup](backup.md).

---

## Thumbnails are missing, blank or out of date

Thumbnail tiles fetch when they scroll into view, and a single fetch can fail
transiently — a cold backend, an engine restarting under you. A tile retries on
its own, four attempts with a growing gap, before giving up and showing the file
kind icon. So the first thing worth doing is waiting a moment.

After that there are three different actions, and picking the wrong one wastes
time.

| Action | Desktop location | Phone location | What it does |
|---|---|---|---|
| `Reload thumbnails` | pane `View` menu | `⋯` → `ADVANCED` | Re-attempts only the tiles that never loaded. Cached ones stay instant. |
| `Load all in this folder` | pane `View` menu | `⋯` → `ADVANCED` | Fetches every image and video in the current listing, not just the ones on screen, so scrolling is instant afterwards. |
| `Rebuild (clear cache)` — on the phone, `Rebuild thumbnails (clear cache)` | pane `View` menu | `⋯` → `ADVANCED` | Re-fetches every tile, ignoring and overwriting the cache. |

Use **Reload** when some tiles are stuck as placeholders. Use **Rebuild** when a
thumbnail is *wrong* — showing the previous contents of a replaced file, for
instance. Rebuild is the expensive one; it re-downloads.

Other reasons a thumbnail may never appear:

- **Thumbnails are off for that remote.** The pane's `View` menu has a
  `Thumbnails` item with a tick; the phone's `⋯` sheet has a `Thumbnails`
  switch. It is per remote. For a local folder the item reads
  `Thumbnails (always on)` and cannot be turned off, because there is no
  bandwidth to save.
- **The file is an online-only cloud placeholder.** On Windows and macOS a file
  inside a OneDrive, iCloud, Proton Drive, Dropbox or Google Drive sync folder
  can be a placeholder whose contents are not on the disk. Reading it would make
  the OS download the whole file. Airclone deliberately skips those and shows
  the file kind icon instead. A multi-gigabyte surprise download is the thing
  being avoided; one missing thumbnail is the price.
- **The file is too large, or is a video that will not decode a frame.** A
  captured frame that comes back as one flat shade — the black leader many
  videos open on — is treated as a failure rather than cached, because a cached
  black square looks permanently broken.
- **`Keep cache in memory only` is on.** In Settings → **Storage & updates** →
  `Preview cache`. With it on, nothing is written to disk, so every thumbnail is
  regenerated each session by design.
- **You changed the rclone config password.** Cached previews are encrypted at
  rest and bound to that password. Blobs that no longer decrypt are simply
  regenerated, with no error — the first visit to a folder is slow again.

The same `Preview cache` section shows how much is on disk and has a
`Clear cache` button.

---

## A crypt folder says it is empty, or is missing files

This one is worth understanding, because rclone reports success while doing it.

A `crypt` remote stores file and folder names encrypted. If the password or the
salt (rclone's "second password") does not match the data that remote wraps,
rclone cannot decrypt the names — so it **skips those entries, logs a notice,
and returns the rest with an HTTP 200**. Nothing in the response says anything
was withheld. Six folders come back as an empty list, and a file manager that
trusts the answer confidently renders "Empty folder" over a full one.

Airclone watches the engine's log for those notices and counts them across each
listing, so it can tell you instead. You will see one of two things:

- If **nothing** came back, the pane shows a padlock, `N items hidden`, and:
  "rclone could not decrypt their names, so it returned none of them. This
  folder is not empty — the crypt remote's password or salt probably does not
  match the data it wraps."
- If **some** entries came back, a strip above the listing says
  `N items hidden here: rclone could not decrypt the names. The crypt remote's
  password or salt may not match this data.`

What this means in practice:

- **Your files are still there.** Nothing has been deleted. The remote cannot
  read the names, that is all.
- The usual cause is a **wrong or extra second password**. A crypt remote
  created with a salt and later recreated without one (or the other way round)
  produces exactly this. Check the remote's configuration: select it in the
  `CLOUD` section, open its actions menu and choose `Edit remote…`.
- `Test connection` on the same menu will report the remote as reachable. That
  is not a contradiction — reachability and decryptability are different
  questions.

One limit to be aware of: Airclone can only attribute the hidden entries when
the pane's own remote is of type `crypt`. A crypt reached *through* an alias or
a union remote will not raise either message, and such a folder can still appear
plainly empty.

---

## "object not found", or a file that is visibly there will not open

Almost always a stale listing. The file list you are looking at was fetched at
some point in the past; if the file has been moved, renamed or deleted since —
by another device, another app, or a transfer of your own — every action built
on that row asks the engine for a path that no longer exists.

Refresh the folder:

- **Desktop:** the `Refresh` button in the pane's address row, or press `F5`.
- **Phone:** pull down on the list, or `⋯` → `Refresh`.

Related messages you may see: the checksum dialog says
`File not found — it may have been moved or deleted.` for the same reason.

Airclone guards against its own version of this. Fast clicking used to let a
slow listing land after you had already navigated elsewhere, overwriting the new
folder's contents with the old one's; listings are now discarded if you have
moved on before they return. What it cannot know about is a change made
somewhere else. There is no live notification from a cloud remote, so a refresh
is the only way to find out.

---

## A transfer will not start

Work down this list; they are ordered by how often each one is the answer.

**The engine is not ready.** Airclone drives rclone; without it running, nothing
transfers. A transfer started before the engine is up appears in the transfers
list and immediately goes to `Failed` with the error `Engine not ready`. Look at
the desktop status bar, bottom left:

| Status bar says | Meaning |
|---|---|
| `engine ok · rclone <version>` | Running. |
| `engine error` | It failed; the work area shows why. |
| `engine not installed` | rclone was not found. |
| `engine starting…`, `engine locating…`, `engine provisioning…` | Still coming up. Wait. |

While the engine is not ready, the work area (and the phone's `Files` tab) shows
a card instead of your files:

- **`Starting Airclone`** — a spinner. Nothing to do.
- **`Set up the rclone engine`** — "Airclone uses the rclone engine. Download it
  now — nothing else to install." with a `Download rclone engine` button. This
  never appears on **Windows or Android**, where the engine ships inside the
  app.
- **`Engine error`** — with `Retry download` and `Re-check for a local rclone`.
  If the message says the engine stopped unexpectedly, start it again from here.
  If it says the installed rclone is older than the minimum Airclone supports,
  the same button updates it.
- **`Unlock your config`** — see the next item.

**Your rclone config is encrypted and locked.** The card reads `Unlock your
config`, with "Your rclone config is encrypted. Enter its password to unlock."
Type the password and press `Unlock`. A wrong one comes back as `Incorrect
password (or the engine failed to start). Try again.` The password is not
persisted unless you have turned on `Remember config password` in Settings →
Security. Nothing can browse, transfer, mount or serve while the config is
locked — the remotes are literally unreadable until it opens.

**The transfer queue is paused.** The transfers dock header has a pause control
whose tooltip is `Pause queue (queued transfers wait; running ones finish)`.
While it is on, new work sits at `Queued`. Note what it does *not* do: a
transfer already running is not interrupted or suspended. The pause is
session-only and is cleared by a restart, on purpose — a paused queue that
survived a restart would be a trap.

**A concurrency limit is holding it.** Settings → Transfers →
`Concurrent transfers` (Advanced mode). The default is `Unlimited`, in which
case everything dispatches at once and the pause control has little visible
effect. If you set a limit, the rest wait at `Queued` until a slot frees.

**A confirmation is waiting for you.** A real one-way `Sync` started from the
run-now dialog always raises a dialog headed **`Sync deletes destination
files`**, with `Cancel`, `Dry run first` and `Run sync`. Nothing is dispatched
until you answer. `Copy` and `Move` do not stop to ask. An ad-hoc
`Two-way sync` raises its own separate baseline confirmation, because a two-way
sync with no established baseline would otherwise run a destructive first pass.

**A bandwidth limit is throttling it to near nothing.** The top bar's
`Bandwidth limit` control shows `Unlimited` or a rate, and can also carry a
daily schedule. A transfer that looks stuck may simply be slow.

**On Android, storage access has not been granted.** A tappable banner reads
"Allow file access to browse this device's storage". Until it is granted,
local folders on the device will not list.

A failed transfer keeps a `Retry` button on its row in the transfers list, and
the row carries rclone's own error text. More on running transfers in
[transferring](transferring.md).

---

## Mounting and sharing

Both are **desktop only** in practice, and both live behind **Advanced mode**.

- **Mounting needs a filesystem driver.** On Windows, if WinFsp is not
  installed the mount panel shows: "Mounting on Windows needs WinFsp. Install it
  from winfsp.dev, then restart Airclone." No drive letters are offered until
  then.
- **The Mac App Store build cannot mount or serve at all.** FUSE is impossible
  under the App Sandbox, so those buttons are hidden rather than offered and
  failed. The direct-download macOS build can do both.
- **Closing Airclone with mounts live** raises a confirmation first, then
  unmounts before stopping the engine. That is there so a close cannot leave a
  drive letter that looks mounted but answers nothing.

Detail in [mount-and-share](mount-and-share.md).

---

## Nothing here matches

Two things worth trying before filing anything:

1. **`Test connection`** on the remote. Desktop: the actions menu on the
   remote's row in the `CLOUD` section. Phone: the `⋯` on the remote's row,
   tooltip `Remote actions`. It reports `Reachable`, usually with free and total
   space, or the engine's error verbatim.
2. **The command console**, if you are comfortable with rclone's own vocabulary.
   It runs real rclone commands against the same engine and prints what rclone
   prints, which is often more specific than a dialog can be. It is available on
   every platform with Advanced mode on. See [console](console.md).

Then export the Problem report as described at the top of this page and attach
it to a bug report. That is the only supported way to get evidence out of
Airclone, and it happens only because you asked for it.

---

## What Airclone will not do

Worth restating, because it shapes everything above:

- It sends **no** telemetry, analytics or crash reports.
- The Problem report leaves your device only when you press `Copy report`,
  `Save report…` or `Share report`.
- On a version installed from an app store, `Check for updates` makes no request
  to GitHub at all — it only names the store it updates through.

The full statement is in [PRIVACY.md](../../PRIVACY.md).

---

## Related pages

- [Getting started](getting-started.md)
- [Browsing your files](browsing.md)
- [Copying, moving and syncing](transferring.md)
- [Backing up a folder](backup.md)
- [Scheduling](scheduling.md)
- [Photo backup on Android](photos-android.md)
- [Mounting and sharing](mount-and-share.md)
- [Config and devices](config-and-devices.md)
- [The command console](console.md)
- [Guide index](README.md)
