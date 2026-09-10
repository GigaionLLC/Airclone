---
type: "feature"
name: "Scheduling & Automation"
status: "partial"
platforms: ["desktop"]
dependencies: ["07-state-context", "11-validation-standards", "14-performance-standards"]
description: "Saved tasks that run on an interval, daily or weekly — in-app everywhere, with the app closed on Windows — and the delete cap and circuit breaker that keep an unattended Sync from emptying a destination."
---

# ⏰ Scheduling & Automation

A **saved task** is a source, a destination, a set of transfer options and — optionally — a
schedule. With a schedule it runs by itself; without one it is a one-click repeat of a transfer
you set up once.

> **Status: partial.** What is written below is what ships. The gaps are named in §6 rather than
> glossed over, because the difference between "scheduled" and "scheduled *and it actually fires*"
> is the whole feature, and it is not the same on every platform.
>
> **Something did not run?** Start at [§5.4](#54-three-things-can-run-a-task--know-which-one-owns-yours):
> three different mechanisms can run a saved task, and knowing which one owns yours is most of the
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
| **Shell width** | Below 700 dp there is no toolbar and no command palette. | **Bypassed** — Settings reaches a phone. But see the caveat below, and §4: there is no background execution on mobile to schedule *into* yet. |

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

**Missed slots are caught up once, not replayed.** `isDue` is
`now >= slot && lastRun < slot`, so a machine that was off for three days runs the task once on
next launch rather than three times. A task run manually stamps `lastRun` before it dispatches, so
the next tick does not fire a second copy behind it.

Each task keeps its **last 10 run outcomes** (`TaskRunRecord`, capped in `state/tasks_controller.dart`)
so a failure that happened while nobody was watching is still there afterwards.

## 3. Running while the app is open — every desktop platform

`SchedulerController` (`state/scheduler_controller.dart`) arms one app-lifetime timer that ticks
every 30 s and dispatches whatever is due through the ordinary transfer path. The provider is
force-read once at launch, because Riverpod providers are lazy and a scheduler nobody reads is a
scheduler that never runs.

If the engine is not ready when a slot comes up — still starting, config locked, crashed — nothing
is dispatched and the tick records `skippedWhileUnavailable`, which the tasks dialog surfaces as
*"A scheduled task was due while the engine was locked — unlock to let it run."* A due slot that
silently evaporates is the failure this replaced.

## 4. Running with the app closed — Windows only, today

The schedule editor offers **"Also run while Airclone is closed"** on Windows. It registers a
Windows Scheduled Task (`schtasks /Create /XML … /F`, so it doubles as an update on an edited
schedule) pointing at the headless entry point:

```
airclone --run-task <id>
```

`headless/headless_runner.dart` runs the same task through the same code path with no UI and
exits with a code the OS scheduler can read: **0** ran and succeeded, **1** ran and something
failed, **2** could not start at all (bad or missing task id, engine unavailable).

Two things it refuses to do, both on purpose:

- **An encrypted config with no stored password** blocks the checkbox. Every background fire would
  exit 2 unattended with no history entry, so Save stops and points at *Settings → Remember config
  password* instead.
- **A slow probe cannot clobber a fresh tick.** Task Scheduler is the source of truth (nothing about
  the registration is persisted on the task model), so the editor probes `schtasks /Query` on open;
  Save stays disabled until that resolves, or a fast Save would take the unregister branch on a
  stale default and delete a registration the user meant to keep.

macOS and Linux get the in-app scheduler and an honest footnote. launchd and systemd-user are Phase
D of the v0.8 plan.

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
  *percent* (`--max-delete-percent`, default 50) — a different setting, in the transfer options
  dialog.

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

### 5.4 Three things can run a task — know which one owns yours

This is the first thing to establish when something did not run, because "it did
not run" is not a diagnosis until you know **which** of these was supposed to run
it.

| Runner | Covers | Where it lives | How late it can be |
| :--- | :--- | :--- | :--- |
| **The in-app tick** | Every schedule, on every desktop, whenever Airclone is open | `SchedulerController` — a 30 s timer inside the app | Up to 30 s |
| **An exact OS trigger** | **Daily and weekly** schedules, opted in, on Windows | Task Scheduler → `Airclone` → *the task's own name* | Not late — it fires at the time you chose |
| **The shared poller** | **Interval** schedules ("every N hours"), opted in, on Windows | Task Scheduler → `Airclone` → `Run due tasks` | Up to one cadence (default 15 min) |

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

1. **Was "Also run while Airclone is closed" actually ticked?** It is per task
   and off by default. The editor's footnote says so in as many words when it is
   off, naming the checkbox.
2. **Was Airclone closed on a platform that has no background scheduling?**
   macOS, Linux and mobile run schedules **only while the app is open** (§4). A
   missed slot is caught up once on next launch — once, not replayed.
3. **Is the scheduler paused?** A delete-cap trip stops *everything* until a
   human resumes it (§5.3). Settings → Automation shows a banner naming the task
   that tripped it and the engine's own error. This is deliberately global, so
   one bad task stops the others too.
4. **Did it refuse rather than fail?** A scheduled Sync whose source is empty or
   unreadable does not run at all (§5.2). It records a failed run whose reason
   says exactly that; Settings → Automation shows the last outcome per task.
5. **Was the engine locked?** An encrypted config with no stored password cannot
   unlock unattended. The in-app path records "a scheduled task was due while the
   engine was locked"; a background run exits **2**, which Task Scheduler shows
   as `0x2` in *Last Run Result*.
6. **Was the machine asleep or off?** Both Windows jobs set
   `StartWhenAvailable`, so the run catches up when the machine returns — but
   once, and not at the original time.
7. **Only then, look at Task Scheduler itself.** `Airclone` → the entry the
   editor named. *Last Run Time* and *Last Run Result* are the ground truth about
   whether Windows started the process at all. `0x0` means it ran and succeeded,
   `0x1` means it ran and something failed (check the task's run history in
   Airclone for the reason), `0x2` means it could not start — bad task id, or an
   engine that would not come up.

**A run that Windows started always leaves a trace in Airclone**, in that task's
run history, whether it succeeded or failed. If Task Scheduler says a run
happened and Airclone's history has nothing for it, that is a real bug worth
reporting rather than a configuration problem.

## 6. What this is not, yet

- **No background execution on macOS or Linux** (launchd / systemd-user: v0.8 Phase D).
- **Android runs due tasks in the background; iOS does not.** On Android, one WorkManager
  periodic request (15-minute floor, Wi-Fi-only by default, optionally charging-only — Settings →
  Automation → "Background on this phone") wakes a headless engine that runs the same `--run-due`
  selection. There are no exact-time triggers, so a daily task can start up to one wake late, and
  Doze may hold a wake back. It reschedules itself across reboots — there is no `BOOT_COMPLETED`
  receiver, on purpose. iOS background execution is explicitly out of scope.
- **Camera-roll backup is Android-only** (`TaskKind.photos`, Settings → Automation → "Back up
  your photos"): a set of folders under internal storage (DCIM by default), mirrored into
  `remote:Airclone/Photos/<device>/`, copy only, videos on a separate toggle.
- **No way to create a task on a phone-sized shell** — not because of scheduling, but because the
  transfer options dialog does not fit (see §1). And nothing to schedule into if it did.
- **No cron**, no filesystem watcher, no event triggers.
- **No definition-time acknowledgement** that a repeating Sync is destructive, and **no refusal to
  run against a source that resolves empty**. Both are open items in Phase B of the plan; the cap
  and the breaker are what stand there today.

## 7. Where the code is

| Piece | File |
| :--- | :--- |
| What "scheduled" means per platform | `state/scheduling_policy.dart` |
| Tick loop, dispatch, outcome supervision | `state/scheduler_controller.dart` |
| Schedule model and `isDue` | `state/task_schedule.dart` |
| Task model, run history | `state/tasks_controller.dart` |
| Delete cap default and application | `state/transfer_options.dart` |
| Circuit breaker state and error match | `state/scheduler_pause.dart` |
| Windows registration | `state/windows_task_scheduler.dart` |
| Android registration rule, reconciler, constraints | `state/android_work_registration.dart`, `state/android_work_settings.dart`, `state/android_work_channel.dart` |
| Android background isolate (the `--run-due` of a WorkManager wake) | `state/android_work_entrypoint.dart`; native side `app/android/.../DueTasksWorker.kt`, `WorkChannel.kt`, `NativeChannel.kt` |
| Photo backup model (folders → filter rules, destination, device folder) | `state/photo_backup.dart`; UI `ui/photo_backup_section.dart` |
| Headless entry point and exit codes | `headless/headless_runner.dart` |
| Tasks dialog, schedule editor, paused banner, Settings → Automation | `ui/tasks_panel.dart` |
| From/To picker (replaces the two-pane requirement) | `ui/from_to_picker.dart` |

Tests: `test/scheduler_tick_test.dart`, `test/schedule_test.dart`,
`test/scheduling_policy_test.dart`, `test/scheduler_delete_cap_test.dart`,
`test/scheduler_pause_ui_test.dart`, `test/from_to_picker_test.dart`,
`test/windows_task_scheduler_test.dart`.
