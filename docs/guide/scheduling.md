# Running tasks on a schedule

A **saved task** is a transfer you have given a name: a From, a To, and the
options you picked. You can run it whenever you like from one button. Give it a
**schedule** and Airclone runs it for you.

Whether a scheduled task runs with Airclone closed depends entirely on the
platform you are on. That is the part most worth reading, and it starts at
[What your device can actually do](#what-your-device-can-actually-do).

## Where to find it

**Settings → Automation**, on every platform. It is not hidden behind Advanced
mode, and it is the only route to saved tasks on a phone.

- On Windows, macOS and Linux, Settings is a dialog. Open it with the
  **Settings** button at the right of the top bar.
- On a phone or an Android TV, **Settings** is one of the three tabs at the
  bottom (a side rail on a TV). Scroll to the **Automation** group.

The group contains a **Scheduled tasks** section — "Saved transfers that run by
themselves." — which lists what is already scheduled, and two buttons:

| Button | What it opens |
|---|---|
| `Back up a folder` | A short wizard: which folder, where to keep it, how often. See [Backing up a folder](backup.md). |
| `Saved tasks` | The full list of saved tasks, where schedules are edited. |

On Windows, macOS and Linux there are two more doors to the same list, both of
which need **Advanced mode** turned on: the `Saved tasks` button in the top bar,
and `Ctrl + K` → "Saved tasks". Settings → Automation needs nothing.

On Android, Settings → Automation also holds **Back up your photos** and
**Background on this phone**. Those are covered in
[Backing up your photos](photos-android.md).

## Making a saved task

In the `Saved tasks` dialog, press **New task**. Airclone asks three things in
turn:

1. **From** and **To**. If you already have a source open in the active pane and
   a destination in the other one, the picker starts there — but it is only a
   starting point. You do not have to arrange your panes first, and you do not
   need a second pane at all.
2. **Options** — the transfer mode (`Copy`, `Move`, `Sync`, and `Two-way sync`
   under Advanced mode) and anything else the transfer dialog offers. These are
   the same options described in [Copying, moving and syncing](transferring.md).
3. **A name**, in a `Save task as` box. It is pre-filled with
   `source → destination`.

Each row in the list then shows the name, the mode, the From → To pair, and a
`Run` button that starts it immediately.

Every run is recorded, whether you started it or the schedule did: the row shows
`last ran 5 min ago`, with `· failed` in red when it did not work. Hover the line
to see the last five runs, how long each took, and the engine's error text for
any that failed. Airclone keeps the ten most recent runs per task. This is local
to your device — nothing is sent anywhere.

A task made by the `Back up a folder` wizard is a **backup**: it only ever
copies, it keeps replaced versions, and it cannot be turned into something that
deletes, even by editing it afterwards.

## Giving a task a schedule

On the task's row, press the alarm button — its tooltip is **Schedule…**, or
**Edit schedule** once it has one. Turn on **Run automatically on a schedule**
and pick one of three kinds:

| Chip | What you set | Notes |
|---|---|---|
| `Interval` | An `Every` dropdown: `15 minutes`, `30 minutes`, `hour`, `2 hours`, `6 hours`, `12 hours`, `24 hours` | Starts at 6 hours. Measured from the last run, not from a clock time. |
| `Daily` | An `At` time | Starts at 09:00. |
| `Weekly` | `On days` (M T W T F S S) plus an `At` time | `Save` stays disabled until you choose at least one day. |

Press **Save**. The row then reads something like
`Daily at 09:00 · next tomorrow 09:00`, or `· due now` when a slot is already
past.

Saving resets the task's clock, so a time that has already gone by today does not
fire the moment you close the dialog.

The `Back up a folder` wizard is deliberately simpler: it offers only **Daily**
(the default, at 02:00) and **Hourly** (`hour`, `6 hours` or `12 hours`). Weekly
exists only in the full editor above — a backup that runs once a week is six days
stale when you need it.

## What your device can actually do

This is not the same everywhere, and Airclone says so on the screen rather than
promising one answer to everyone. The sentence under the schedule controls is
the sentence for the device you are holding.

| Platform | While Airclone is open | While Airclone is closed | Missed runs |
|---|---|---|---|
| Windows | Runs | Runs, if you opt in | Started when the PC is next available |
| Android | Runs | Runs, if you opt in | Started at the next background wake |
| macOS | Runs | Nothing runs | One missed run starts on next launch |
| Linux | Runs | Nothing runs | One missed run starts on next launch |
| iOS, iPadOS | Not supported | Nothing runs | — |

The exact wording Airclone uses:

- Windows and Android: "Scheduled tasks run in the background, even with
  Airclone closed."
- macOS and Linux: "Scheduled tasks run while Airclone is open. A run missed
  while it was closed starts once on next launch."
- iPhone and iPad: "Scheduling is not available on this device yet — saved tasks
  still run when you start them by hand." Settings → Automation adds: "Saved
  tasks still work here — open one and run it when you want it. Background
  scheduling on this platform is planned."

While Airclone is open, on any platform that schedules at all, it checks its
schedules every 30 seconds.

**Catch-up runs one slot, not every slot you missed.** If a daily 09:00 task was
not run for four days, it runs once when Airclone next opens — not four times.

## "Also run while Airclone is closed"

This checkbox appears **only on Windows and Android**, because those are the only
platforms where ticking it can do anything. The `Back up a folder` wizard ticks
it for you; the schedule editor leaves it as you last set it for that task, and
off for a task that has never had it.

### On Windows

What gets arranged depends on the kind of schedule:

| Schedule kind | How it is registered |
|---|---|
| `Daily`, `Weekly` | Its own entry in Windows Task Scheduler, firing at the exact time you chose |
| `Interval` | One shared entry named **`Run due tasks`**, which wakes every 15 minutes and runs whatever is due |

All of it lives in the **`Airclone` folder** in Task Scheduler, and that is where
to look if a task stops firing. Only the shared job carries a name you will
recognise; the per-task entries are named by an internal id, so do not expect to
find your task's own name in that list.

Those entries are set up to be trustworthy when nobody is watching: a run missed
because the PC was off or asleep starts when the PC is available again, a laptop
on battery still runs, a slow run is not stacked on by the next slot, and any
single run is stopped after six hours.

### On Android

Android has exactly one periodic wake, so **everything** goes through it,
including a `Daily at 09:00` task. Airclone tells you what that means:

> Android wakes Airclone about every 15 minutes and runs this when it is due, so
> it can start late — and later still if the phone is asleep, on battery saver,
> or off Wi-Fi.

A daily task will therefore not fire at 09:00 on the nose. Fifteen minutes is
Android's own floor for this kind of background work, not a choice Airclone made.

Two switches under **Background on this phone** control when Android is allowed
to wake it: **Only on Wi-Fi** ("Never on mobile data.") and **Only while
charging**. The line beneath them says whether Airclone is registered with
Android, when the next wake is expected, and how the last one went. There is also
a **Run due tasks in background now** button, which queues a real background run
so you can see it work rather than wait for one.

### Everywhere else

macOS, Linux and iOS show no checkbox, because there is nothing behind it yet. On
macOS and Linux a schedule still works — it just needs Airclone to be open.

## A background run can start late

Worth stating plainly, because it reads as a fault when it is not:

- An `Interval` schedule on Windows is served by a job that wakes every 15
  minutes, so it can start up to 15 minutes after its time.
- Every schedule on Android goes through a wake that is also about 15 minutes
  apart, and Android may hold that wake back to save battery, or until the Wi-Fi
  and charging conditions you set are met.
- On Windows, a `Daily` or `Weekly` task with the checkbox ticked is the one case
  that does fire at the exact time.

There is no setting in Airclone for how often the background job wakes.

## If your config is encrypted

A background run happens with nobody there to type a password. If your rclone
config is encrypted and Airclone has no stored password for it, ticking "Also run
while Airclone is closed" is refused, with this message:

> This config is encrypted and no password is stored, so a background run could
> never unlock it. Enable "Remember config password" in Settings first.

That setting is in **Settings → Security**. Without it, every background run
would fail silently at the first step. See
[Your config and your devices](config-and-devices.md).

The same thing can happen while Airclone is open but still locked. When a
scheduled run comes due and the engine is not available, the `Saved tasks` dialog
shows: "A scheduled task was due while the engine was locked — unlock to let it
run." Nothing is lost; the run happens once the engine is up.

## The delete cap, and why a schedule can stop everything

A one-way **Sync** makes the destination match the source, which means it deletes
whatever the source no longer has. That is fine when you are watching. It is not
fine at 3am when the source has quietly gone missing — an external drive that did
not mount, an expired token, a folder somebody renamed. To the sync, an empty
source looks like "the user deleted everything".

Airclone puts two separate guards in the way.

### 1. A cap on deletions

The schedule editor shows **Stop if a run would delete more than [100] files** for
any task whose mode is one-way `Sync`. You can change the number, but you cannot
remove it: a repeating sync is given the cap of 100 when it runs even if it was
saved before this existed, or edited to drop it.

The field does not appear for `Copy` or `Move` — neither deletes at the
destination — and a `Two-way sync` caps by percentage instead, on its own screen.

If a run would exceed the cap, the run stops. Nothing further is deleted, and the
failure is written into the task's run history with the engine's own words.

### 2. The pause that covers everything

When the run that hit the cap was started by Airclone's own scheduler — that is,
with the app open — Airclone also **pauses every schedule**, not only the one that
tripped. The causes are usually environmental, and a missing drive is missing for
every task pointing at it.

You will see a red banner at the top of `Saved tasks` and in Settings →
Automation:

> **Scheduling is paused** — "<task>" would have deleted more than its cap, so
> nothing scheduled has run since <date and time>. Check that the source is where
> you expect it before resuming.

The engine's error is quoted underneath, verbatim, so you can judge it rather
than trust a summary.

**Nothing scheduled runs until you press `Resume` on that banner.** There is no
timeout and no automatic recovery — the whole point is that a person looks first.
The pause survives closing and reopening Airclone, and a background run on
Windows or Android checks it too and refuses to run anything while it stands.

### The refusal that the cap cannot cover

A cap of 100 files still allows a destination holding 80 to be wiped. So a
scheduled one-way `Sync` whose source is **empty, or cannot be read at all**, is
refused before it starts:

> Refused to run: the source is empty or could not be read, and a Sync would have
> deleted the destination to match it.

That lands in the run history like any other outcome, so it is visible rather
than silent. "Could not be read" counts as unsafe on purpose: a person looking at
a preview can decide, an unattended timer cannot.

Backups are exempt, because they only copy — an empty source is a harmless
no-op, not a wipe.

## Two-way sync is never started for you

A `Two-way sync` task whose baseline has not been established is skipped by the
scheduler, every time, and its row says **Needs first run — baseline not
established**. The first two-way run matches both sides and cannot be undone, so
it has to be started by hand, from a confirmation that shows which side wins.
Once that has happened, the schedule behaves normally.

## Changing, pausing or removing a schedule

- **Change it**: alarm button → adjust → `Save`. On Windows the background
  registration is rewritten to match, including a time you only moved by an hour.
- **Stop scheduling but keep the task**: alarm button → turn **Run automatically
  on a schedule** off → `Save`. The task stays, and `Run` still works.
- **Stop background runs but keep the schedule**: untick "Also run while Airclone
  is closed" → `Save`. It then runs only while Airclone is open.
- **Delete the task**: the bin button on its row. Any background registration for
  it is removed at the same time, so a deleted task cannot keep firing.

The **Pause queue** button in the Transfers dock is a different thing entirely.
It holds *queued transfers* for the current session and has nothing to do with
schedules. See [Copying, moving and syncing](transferring.md).

## What scheduling will not do

- It will not run anything on an iPhone or iPad without you.
- It will not run on macOS or Linux with Airclone closed. Closing the app there
  stops the schedule until you open it again.
- It will not catch up more than one missed slot per task.
- It will not hit an exact time on Android, or on a Windows `Interval` schedule.
- It will not delete past the cap on a repeating one-way sync, and it will not
  quietly carry on after it stops.
- It will not run while the config is locked, and it will not attempt a
  background run against an encrypted config with no stored password.

---

If a task is not running when you think it should, start with
[When something goes wrong](troubleshooting.md). New to Airclone? Start at
[Getting started](getting-started.md), or return to the
[guide index](README.md).
