---
type: "feature"
name: "Scheduling & Automation"
status: "partial"
platforms: ["desktop", "android"]
dependencies: ["07-state-context", "11-validation-standards", "14-performance-standards"]
description: "Saved tasks that run on an interval, daily or weekly — in-app everywhere, with the app closed on Windows and Android — and the delete cap and circuit breaker that keep an unattended Sync from emptying a destination."
---

# ⏰ Scheduling & Automation

A **saved task** is a source, a destination, a set of transfer options and — optionally — a
schedule. With a schedule it runs by itself; without one it is a one-click repeat of a transfer
you set up once.

> **Status: partial.** What is written below is what ships. The gaps are named in §6 rather than
> glossed over, because the difference between "scheduled" and "scheduled *and it actually fires*"
> is the whole feature, and it is not the same on every platform.
>
> **Something did not run?** Start at [§5.4](#54-four-things-can-run-a-task--know-which-one-owns-yours):
> four different mechanisms can run a saved task, and knowing which one owns yours is most of the
> diagnosis.

---

## 1. Where it lives

**Settings → Automation** is the front door, and it is behind no gate at all. It states what a
schedule means on this platform (§3–§4), lists every scheduled task with its cadence, next run and
last outcome, surfaces a tripped circuit breaker (§5.3), and opens the full panel.

**Creating** a schedule is still gated, and these are the gates being removed across v0.8 — see
[the scheduling and backup plan](../../dev/plans/scheduling-and-backup-plan.md) §4.a:

| Gate | Effect | Status |
| :--- | :--- | :--- |
| **Advanced mode** (`state/advanced_mode.dart`, default **off**) | The toolbar and command-palette doors to Saved tasks are behind `if (advanced)` (`ui/home_screen.dart`). | **Closed.** Settings → Automation is ungated and opens the panel, and nothing on the path from there to a saved, scheduled task reads advanced mode. The two old doors still exist for people who already use them. |
| **Two panes** | "New task" used to read the source from the active pane and the destination from the other, and refuse if either was empty. | **Closed.** `ui/from_to_picker.dart` asks for both ends directly; the panes now only pre-fill it. |
| **Shell width** | Below 700 dp there is no toolbar and no command palette. | **Bypassed** — Settings reaches a phone. But see the caveat below. On Android there is now a background poll to schedule *into* (§4.2); on iOS there is not. |

> **The remaining mobile blocker is not scheduling.** `ui/transfer_options_dialog.dart` is a
> hard-coded `SizedBox(width: 720, height: 560)` rather than the shared `DialogBody`, and overflows
> by 115 px at 375×812 (measured 2026-09-09). Everything either side of it fits; that one dialog is
> what stops the chain on a phone.

### 1.1 One place decides what "scheduled" means

`state/scheduling_policy.dart` — a `SchedulingSupport` of `background`, `whileOpen` or `none`,
decided by a pure function of the OS name (so it is testable from any platform), plus the one
sentence to show a user for each. Every surface asks it rather than testing `Platform.isWindows`
itself; when launchd and systemd-user land, they land in one place.

An OS the function has never heard of gets `none`, not a guess — promising a background run that was
never wired is the failure the file exists to prevent.

## 2. What a schedule can say

`state/task_schedule.dart` — three kinds, deliberately not cron:

| Kind | Fires |
| :--- | :--- |
| **Interval** | Every N minutes since the last run (presets from 15 minutes upward). |
| **Daily** | At a wall-clock time. |
| **Weekly** | At a wall-clock time, on chosen weekdays. |

**Missed slots are caught up once, not replayed.** For **daily and weekly**, `isDue` is
`now >= slot && lastRun < slot`, so a machine that was off for three days runs the task once on
next launch rather than three times. An **interval** schedule has no slot: it is due when at least
N minutes have elapsed since `lastRun`, and due immediately when it has never run
(`lastRun == null`). A task run manually stamps `lastRun` before it dispatches, so the next tick
does not fire a second copy behind it.

**A two-way sync with no baseline is never auto-run**, and that gate sits *before* `isDue` rather
than beside it. bisync's first pass is a `--resync`, which is destructive and has to be done once by
hand; so `dueTasks` (`state/scheduler_controller.dart`, shared verbatim with the headless path)
filters those tasks out before the schedule is even consulted. Nothing is recorded when it happens —
the task simply never runs and its history stays empty. Saved tasks marks the row *"Needs first run
— baseline not established"*; Settings → Automation does not.

Each task keeps its **last 10 run outcomes** (`TaskRunRecord`, capped in `state/tasks_controller.dart`)
so a failure that happened while nobody was watching is still there afterwards.

## 3. Running while the app is open — every platform

`SchedulerController` (`state/scheduler_controller.dart`) arms one app-lifetime timer that ticks
every 30 s and dispatches whatever is due through the ordinary transfer path. The provider is
force-read once at launch (in `HomeScreen`'s `initState`, before the shell is chosen, so a phone
ticks too), because Riverpod providers are lazy and a scheduler nobody reads is a scheduler that
never runs.

If the engine is not ready when a slot comes up — still starting, config locked, crashed — nothing
is dispatched and the tick records `skippedWhileUnavailable`, which the tasks dialog surfaces as
*"A scheduled task was due while the engine was locked — unlock to let it run."* A due slot that
silently evaporates is the failure this replaced.

## 4. Running with the app closed — Windows and Android

The schedule editor offers **"Also run while Airclone is closed"** wherever `schedulingSupport`
is `background` (§1.1) — Windows and Android today. The opt-in is **persisted on the task**
(`TransferTask.runWhileClosed`); how the OS registrations are kept in step with it is §5.4a.

### 4.1 Windows — Task Scheduler

A daily or weekly schedule registers a Windows Scheduled Task of its own (`schtasks /Create /XML
… /F`, so it doubles as an update on an edited schedule) pointing at the headless entry point;
an interval schedule joins one shared polling job instead (§5.4):

```
airclone --run-task <id>
airclone --run-due
```

`headless/headless_runner.dart` runs the same task through the same code path with no UI and
exits with a code the OS scheduler can read: **0** ran and succeeded, **1** ran and something
failed, **2** could not start at all (bad or missing task id, engine unavailable).

One thing it refuses to do, on purpose: **an encrypted config with no stored password** blocks
the checkbox. Every background fire would exit 2 unattended with no history entry, so Save stops
and points at *Settings → Remember config password* instead.

### 4.2 Android — a WorkManager poll

Android runs due tasks with the app closed too, but by **polling only**. One
`PeriodicWorkRequest` (15-minute floor — Android's, not ours; Wi-Fi-only by default, optionally
charging-only, under Settings → Automation → "Background on this phone") wakes a headless engine
that runs the same `--run-due` selection. There are **no exact-time triggers**, so a daily 09:00
task starts up to one wake late, and Doze may hold a wake back further. The wake yields when the
app is on screen, because the in-app tick owns due tasks then. It survives reboots with no
`BOOT_COMPLETED` receiver of ours — WorkManager re-arms itself.

> **A background wake is usually short, and a big first backup runs in slices.** Measured on an
> Android 15 emulator (2026-09-09): Android 12+ **refuses** `setForeground()` to a periodic wake
> started in the background (`startForegroundService() not allowed due to mAllowStartForeground
> false`) — WorkManager's promotion is not one of the sanctioned exemptions for periodic work. So
> that wake runs inside the plain worker's budget, and the Dart run is capped at **8 minutes**
> (`UNPROMOTED_TIMEOUT_MINUTES` in `DueTasksWorker.kt`) so it ends cleanly — rclone quit, outcome
> recorded — rather than being torn down mid-copy. A large first backup therefore proceeds **one
> slice per wake**, resuming where it stopped (`copy` skips what the destination already has).
> Someone expecting a 40 GB camera roll to finish overnight should expect days of wakes instead.
>
> **The 8 minutes is the refused case, not the only case.** The promotion is attempted on every
> wake, and where it is granted the cap is **5 hours** (`DART_TIMEOUT_MINUTES`, sized to stay inside
> Android 15's ~6 h/day dataSync budget). It is granted on **Android 8–11** — `minSdk` is 26, so
> those are live — and on 12+ for the one-off *"Run due tasks in background now"* the user starts
> from inside the app, which is exactly why that button exists. On a modern phone left alone, 8
> minutes is what you get. A run that starts while the app is on screen is under no cap at all: the
> in-app scheduler runs it as an ordinary transfer.

macOS, Linux and iOS get the in-app scheduler and an honest footnote. launchd and systemd-user
are Phase D of the plan, now expected after v0.8; iOS background execution is out of scope (§6).

## 5. Unattended safety: the delete cap and the circuit breaker

A one-way **Sync** makes the destination match the source, which means it deletes whatever the
source no longer has. Run by a human that is a considered action; run at 3 a.m. by a timer against a
source that is missing — an external drive not mounted, an expired token, a renamed folder — it is
the whole destination.

### 5.1 The cap

Every repeating Sync runs under a delete cap: rclone's `--max-delete`, sent as `_config.MaxDelete`,
which **aborts the run** rather than exceed it.

- The default is **100 files** (`kDefaultScheduledDeleteCap`, `state/transfer_options.dart`).
- The schedule editor **pre-fills** it, so the number is on screen when the schedule is created.
  Emptying the field saves the default — it never means "unlimited".
- It is applied again when the task **runs** (`withScheduledDeleteCap`), so tasks saved before the
  cap existed are covered. Those are precisely the uncapped scheduled syncs already sitting in
  people's configs.
- A cap the user chose is never overridden, **including a deliberate 0** ("abort on the first
  delete"), which is a real choice and not an absent one.
- Copy and Move never delete at the destination, so they get no cap. A two-way sync caps by
  *percent*: bisync's own `--max-delete`, which rclone reads as a percentage there (default 50,
  sent as `maxDelete` on the bisync request) — a different setting, in the transfer options
  dialog. There is no `--max-delete-percent` flag.

### 5.2 The other half: a source that has stopped answering

The cap is a blast-radius limiter, not a veto — a cap of 100 still lets a
destination holding 80 files be wiped. So a scheduled one-way Sync lists its
source before it dispatches, and **refuses to run at all** if that source is
empty or unreadable (`SchedulerController._sourceIsUnsafe`). The two guards
together cover the range; neither covers it alone.

Unreadable counts as unsafe, which is deliberately different from the
interactive sync preview. A human watching a preview can be told "could not read
that" and decide for themselves; a timer at 3 a.m. cannot. The refusal is
recorded as a failed run, so it appears in Settings → Automation with its reason
rather than being the silent stop this feature exists to prevent.

Copy, Move and two-way sync are not gated on this — none of them deletes at the
destination to match a source, so refusing would stop a legitimate no-op and
teach the user that the guard fires for no reason.

### 5.3 The breaker

When a scheduled run aborts on the cap, Airclone **pauses the entire scheduler** until a human
resumes it (`state/scheduler_pause.dart`).

- **Global, not per-task**, because the causes are environmental: the drive that is missing for one
  task is missing for every task pointing at it. Letting the others keep firing is how one bad night
  becomes several.
- **Persisted**, because a pause that forgets itself on restart is not a pause.
- **No auto-resume and no timeout.** The point is that somebody looks.
- The tasks dialog shows a banner naming the task that tripped it and quoting the engine's error
  **verbatim** — a paraphrase of an error is one more thing that can be wrong — with a **Resume**
  button. The first reason is the one kept; a later failure cannot overwrite it.

> **Known soft spot.** Over the RC there is no exit code, only the error string from `job/status`,
> so `isDeleteCapError` is a text match (deliberately loose, and the only place that decides).
> It has **not** been verified against a real aborted run yet. If rclone's wording turns out to
> vary, the fallback is to pause on any failure of a scheduled destructive sync — blunter, but it
> cannot silently stop working, and silently-stopped-working is the failure this exists to prevent.

### 5.4 Four things can run a task — know which one owns yours

This is the first thing to establish when something did not run, because "it did
not run" is not a diagnosis until you know **which** of these was supposed to run
it.

| Runner | Covers | Where it lives | How late it can be |
| :--- | :--- | :--- | :--- |
| **The in-app tick** | Every schedule, on every platform, whenever Airclone is open | `SchedulerController` — a 30 s timer inside the app | Up to 30 s |
| **An exact OS trigger** | **Daily and weekly** schedules, opted in, on Windows | Task Scheduler → `Airclone` → *the task's own name* | Not late — it fires at the time you chose |
| **The shared poller** | **Interval** schedules ("every N hours"), opted in, on Windows | Task Scheduler → `Airclone` → `Run due tasks` | Up to one cadence (default 15 min) |
| **The Android poll** | **Every** opted-in schedule on Android, with the app closed (§4.2) | WorkManager → `DueTasksWorker`; Settings → Automation → "Background on this phone" | Up to one wake (15 min floor) plus whatever Doze adds; and a wake is capped at 8 min on Android 12+ (5 h where the foreground promotion is granted — §4.2) |

The split is not arbitrary and it is not a setting: a schedule that names an
exact time gets an exact trigger, because Task Scheduler can hit 09:00 exactly
and a poller can only approximate it. A schedule that names only a gap is already
polling by its nature, so it joins the shared job rather than adding a second
wakeup source. See `state/registration_policy.dart`.

**The app tells you which one owns a given schedule.** The schedule editor's
footnote names the mechanism *and the Task Scheduler entry to open*, so it is
something you can act on rather than a reassurance. `registrationExplanation()`
produces it, and it is pinned by tests that check it stays actionable — a name
you can find, a number you can compare against what you observed.

### 5.4a How the registrations are kept honest

Airclone does not register or unregister one task at a time; it **reconciles**.
The hybrid made a per-task answer impossible — turning a daily schedule into an
interval one has to delete that task's exact entry *and* create the shared
poller, and neither of those is a fact about the task being edited.

So `reconcile()` asks what the whole set should be, asks Task Scheduler what it
currently holds, and makes the second match the first. It runs at launch and
after any edit.

Three properties worth knowing, because they explain behaviour you might
otherwise read as a bug:

- **An entry that is already correct is not touched.** `schtasks /Create /F`
  *replaces* a task, which resets its trigger state, and a repeating trigger
  whose start boundary is in the past then fires immediately. If reconcile
  rewrote everything it saw, opening Airclone would start a background run. Only
  entries that are missing — or that the caller explicitly flags as changed, such
  as the task you just edited — get written.
- **Deletes happen before creates**, so a schedule changing shape never leaves
  both forms registered at once.
- **If it cannot see what is registered, it deletes nothing.** A failed query
  returns an empty set, and a reconcile that treated that as "the folder is
  empty" would take out every working schedule.

**Upgrading from a build before the hybrid** is handled by the same machinery.
Your old per-task entry for an interval schedule is simply not wanted any more,
so it is removed and the shared job is created in its place — your daily and
weekly entries are left exactly as they were, because those are still the right
shape. Nothing about that path is version-specific.

The one thing that *is* special about the upgrade: whether you wanted background
runs at all used to be inferred by asking Task Scheduler whether your task had an
entry. Under the hybrid an interval schedule has no entry of its own, so that
question stopped being answerable and the answer moved onto the task itself. Any
task that is currently registered is marked as opted-in once, before anything is
reconciled — otherwise the first reconcile after upgrading would read "nobody
wants this" and unregister everything.

### 5.5 When a scheduled run did not happen

Work down this list; it is ordered by how often each one is the answer.

1. **Was "Also run while Airclone is closed" actually ticked?** It is per task,
   and off by default on a schedule you set up in the **task editor** — but the
   **backup wizard pre-ticks it** wherever background runs are possible, so a
   wizard-created backup is opted in unless you unticked it. The editor's
   footnote says so in as many words when it is off, naming the checkbox.
2. **Was Airclone closed on a platform that has no background scheduling?**
   macOS, Linux and iOS run schedules **only while the app is open** (§4). A
   missed slot is caught up once on next launch — once, not replayed.
3. **Is the scheduler paused?** A delete-cap trip stops *everything* until a
   human resumes it (§5.3). Settings → Automation shows a banner naming the task
   that tripped it and the engine's own error. This is deliberately global, so
   one bad task stops the others too. A background wake while paused reports
   **success** to the OS — it exits 0 having selected nothing and run nothing —
   so `0x0` beside an empty run history is what a pause looks like from Task
   Scheduler's side.
4. **Did it refuse rather than fail?** A scheduled Sync whose source is empty or
   unreadable does not run at all (§5.2). It records a failed run whose reason
   says exactly that; Settings → Automation shows the last outcome per task.
5. **Is it a two-way sync that has never been run by hand?** A bisync task with
   no established baseline is filtered out before the schedule is consulted
   (§2), by every runner. There is no error and no run record — the history
   simply stays empty — so this one hides better than anything else on the list.
   Run it once from Saved tasks, where the row says *"Needs first run"*.
6. **Was the engine locked?** An encrypted config with no stored password cannot
   unlock unattended. The in-app path records "a scheduled task was due while the
   engine was locked"; a background run exits **2**, which Task Scheduler shows
   as `0x2` in *Last Run Result*.
7. **Was the machine asleep or off?** Both Windows jobs set
   `StartWhenAvailable`, so the run catches up when the machine returns — but
   once, and not at the original time.
8. **On Android, was the wake late, or just short?** A poll fires at best every
   15 minutes, Doze can hold it back, and on Android 12+ a background wake is
   capped at 8 minutes (§4.2) — a big backup that "did not finish" is usually one
   that is still proceeding a slice per wake. Settings → Automation shows the
   last wake's outcome.
9. **Only then, look at Task Scheduler itself.** `Airclone` → the entry the
   editor named. *Last Run Time* and *Last Run Result* are the ground truth about
   whether Windows started the process at all. `0x0` means it ran and succeeded,
   `0x1` means it ran and something failed (check the task's run history in
   Airclone for the reason), `0x2` means it could not start — bad task id, or an
   engine that would not come up.

**A run that actually dispatched a task always leaves a trace in Airclone**, in
that task's run history, whether it succeeded or failed. Two ordinary outcomes
dispatch nothing and so record nothing, and both exit **0**: a `Run due tasks`
wake that found nothing due (most poller wakes, by design), and any wake at all
while the scheduler is paused. So `0x0` with an empty history is expected for the
shared poller and expected while paused — but for an **exact trigger** on an
unpaused scheduler it is a real bug worth reporting rather than a configuration
problem.

## 6. What this is not, yet

- **No background execution on macOS or Linux** (launchd / systemd-user: Phase D of the plan,
  now expected after v0.8).
- **Android runs due tasks in the background; iOS does not.** The Android path is §4.2 — a
  WorkManager poll with no exact-time triggers, and a background wake capped at 8 minutes on
  Android 12+ (5 hours where the foreground promotion is granted), so a large first backup lands in
  slices across wakes. iOS background execution is explicitly out of scope. **No
  battery-optimisation detection yet:** a phone that has put Airclone in a restricted bucket
  stretches the 15-minute period to hours, and nothing in the app says so.
- **Camera-roll backup is Android-only** (`TaskKind.photos`, Settings → Automation → "Back up
  your photos"): a set of folders under internal storage (DCIM by default), mirrored into
  `remote:Airclone/Photos/<device>/`, copy only, videos on a separate toggle.
- **No way to create a task on a phone-sized shell** — not because of scheduling, but because the
  transfer options dialog does not fit (see §1). The backup wizard and the photo-backup section do
  fit, so on Android what a phone can schedule today is a backup, not an arbitrary task.
- **No cron**, no filesystem watcher, no event triggers.
- **No definition-time acknowledgement** that a repeating Sync is destructive. That is the one
  open item from Phase B of the plan; the empty-source refusal (§5.2), the cap (§5.1) and the
  breaker (§5.3) are what stand there today.

## 7. Where the code is

| Piece | File |
| :--- | :--- |
| What "scheduled" means per platform | `state/scheduling_policy.dart` |
| Tick loop, dispatch, outcome supervision | `state/scheduler_controller.dart` |
| Schedule model and `isDue` | `state/task_schedule.dart` |
| Task model, run history | `state/tasks_controller.dart` |
| Delete cap default and application | `state/transfer_options.dart` |
| Circuit breaker state and error match | `state/scheduler_pause.dart` |
| Which OS shape a schedule gets — exact trigger vs shared poller — and `desiredRegistrations` | `state/registration_policy.dart` |
| The shared poller's cadence (default 15 min; 5/10/15/30/60, clamped not snapped) | `state/poll_cadence.dart` |
| Reconcile-on-launch and the one-time `runWhileClosed` seeding (`seedRunWhileClosed`) | `state/scheduler_registration.dart` |
| Windows registration, `listRegistered`, `reconcile` | `state/windows_task_scheduler.dart` |
| Android registration rule, reconciler, constraints | `state/android_work_registration.dart`, `state/android_work_settings.dart`, `state/android_work_channel.dart` |
| Android background isolate (the `--run-due` of a WorkManager wake) | `state/android_work_entrypoint.dart`; native side `app/android/.../DueTasksWorker.kt`, `WorkChannel.kt`, `NativeChannel.kt` |
| Photo backup model (folders → filter rules, destination, device folder) | `state/photo_backup.dart`; UI `ui/photo_backup_section.dart` |
| Headless entry point and exit codes | `headless/headless_runner.dart` |
| Tasks dialog, schedule editor, paused banner, Settings → Automation | `ui/tasks_panel.dart` |
| From/To picker (replaces the two-pane requirement) | `ui/from_to_picker.dart` |

Tests: `test/scheduler_tick_test.dart`, `test/schedule_test.dart`,
`test/scheduling_policy_test.dart`, `test/scheduler_delete_cap_test.dart`,
`test/scheduler_empty_source_test.dart`, `test/scheduler_pause_ui_test.dart`,
`test/from_to_picker_test.dart`, `test/windows_task_scheduler_test.dart`,
`test/due_runner_task_test.dart`, `test/headless_breaker_test.dart` (the breaker on the
path nobody is watching); the hybrid — `test/registration_policy_test.dart`,
`test/registration_explanation_test.dart`, `test/registration_seed_test.dart`,
`test/reconcile_plan_test.dart`, `test/reconcile_exec_test.dart`,
`test/reconcile_launch_test.dart`; Android — `test/android_work_registration_test.dart`,
`test/photo_backup_test.dart`, `test/photo_backup_dialog_test.dart`.
