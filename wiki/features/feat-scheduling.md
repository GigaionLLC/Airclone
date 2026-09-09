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

---

## 1. Where it lives

**Settings → Automation** is the front door, and it is behind no gate at all. It states what a
schedule means on this platform (§3–§4), lists every scheduled task with its cadence, next run and
last outcome, surfaces a tripped circuit breaker (§5.2), and opens the full panel.

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

### 5.2 The breaker

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

## 6. What this is not, yet

- **No background execution on macOS or Linux** (launchd / systemd-user: v0.8 Phase D).
- **No background execution on mobile.** Android WorkManager is v0.8 Phase F; iOS background
  execution is explicitly out of scope.
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
| Headless entry point and exit codes | `headless/headless_runner.dart` |
| Tasks dialog, schedule editor, paused banner, Settings → Automation | `ui/tasks_panel.dart` |
| From/To picker (replaces the two-pane requirement) | `ui/from_to_picker.dart` |

Tests: `test/scheduler_tick_test.dart`, `test/schedule_test.dart`,
`test/scheduling_policy_test.dart`, `test/scheduler_delete_cap_test.dart`,
`test/scheduler_pause_ui_test.dart`, `test/from_to_picker_test.dart`,
`test/windows_task_scheduler_test.dart`.
