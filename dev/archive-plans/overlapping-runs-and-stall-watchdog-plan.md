# 📦 Parcel Plan: One run per task (#55) and a stall watchdog instead of the 6 h cap (#54)

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `DONE` |
| **Version** | `v1.0.0` |
| **Active Persona** | `Senior Dev` |
| **Last Updated** | 2026-10-25 01:30 |

---

## 1️⃣ Phase 1: Expansion & Scoping
* **Intent:** A saved task never has two runs going at once, however each was started. A hung run is
  stopped by a no-progress watchdog, not a 6 h wall clock that kills big first backups.
* **In Scope:**
  - A cross-process per-task lock and a task id → local job gate. The scheduler tick, Run now, photo
    backup and the headless runner (`--run-due`, `--run-task`, WorkManager, iOS BG) all go through it.
  - A skipped-slot policy that the user can see.
  - A 60 min no-progress watchdog. The outer cap is 72 h everywhere: GUI, headless default and the
    Windows `ExecutionTimeLimit`.
  - Entries already registered with Windows pick up the new XML through a definition stamp.
* **Out of Scope:**
  - Android/iOS `--timeout-minutes` budgets (300 / 8 / 20). Their OS sets these, so they stay.
  - A version bump and release notes. The release is done separately.

## 2️⃣ Phase 2: Requirements & Context
* **Relevant Docs Found:**
  - `wiki/features/feat-scheduling.md` -> runners, reconcile rules; new §5.6.
  - `docs/guide/scheduling.md` -> the "stopped after six hours" promise.
  - `wiki/core/07-state-context.md`, `14-performance-standards.md`, `10-external-integrations.md`.
* **Relevant Code Found:**
  - `app/lib/src/state/scheduler_controller.dart` -> `dueTasks`, tick, `recordRunOutcome`.
  - `app/lib/src/headless/headless_runner.dart` -> `runSelected`, `kDefaultTimeoutMinutes`.
  - `app/lib/src/state/windows_task_scheduler.dart` -> both XMLs (PT6H), `reconcile`.
  - `app/lib/src/ui/tasks_panel.dart` (`_TaskRow._run`), `ui/photo_backup_section.dart` (`_runNow`).

## 3️⃣ Phase 3: User Clarification
* **Open Questions:** None. The issue and discussion settle the requirements. Policy choices are recorded in Phase 4.

## 4️⃣ Phase 4: Detailed Execution Plan
* **Architecture & Files to Touch:**
  - New `state/task_run_gate.dart`:
    - `TaskRunLocks` takes an exclusive `RandomAccessFile.lock` on
      `<support>/run-locks/<key>.lock` plus an `IsolateNameServer` name. POSIX record locks are
      per-process, so the name covers Android's second engine in the same process.
    - The key is the task id if it matches `[A-Za-z0-9-]`; otherwise `_` + hex. It is never a path.
    - `TaskRunGate` holds task id → `Job.id`. A claim ends when the job finishes, is removed, or its
      engine goes away. It does not end when the supervisor stops waiting.
  - `scheduler_controller.dart`:
    - `dueTasks(..., running:)` and `SchedulerStatus.skippedWhileRunning`.
    - The claim comes before the `lastRun` stamp.
    - `recordRunOutcome` gains a stall watchdog (`kStallWindow` 60 min, then `job/stop` and a failure
      record) and `kMaxSuperviseDuration` 72 h.
  - `job.dart`: a `work` counter (checks/listing) that counts as progress.
  - `headless_runner.dart`: `runSelected` claims each task and skips with `[SKIP] …` (exit 0);
    `kDefaultTimeoutMinutes` = 72 h.
  - `windows_task_scheduler.dart`:
    - Both XMLs use PT72H.
    - A `[airclone-def:<16 hex>]` self-hash goes in the Description.
    - `reconcile` rewrites a correctly named entry whose stamp differs. An unreadable definition is
      left alone.
* **Policy decisions:**
  - **Skipped slot:** skip, do not queue, and do not stamp `lastRun`. The task runs once when the
    earlier run ends. The skip shows in Saved tasks, or as a headless `[SKIP]` line.
  - **Stall window 60 min:** rclone's own 5 min I/O timeout and retries already catch dead
    connections. A slow listing counts as work, and a long server-side copy can be quiet for tens of
    minutes.
  - **Rewrite on fingerprint change:** this fires the entry once (`/Create /F` resets the trigger).
    That is acceptable once per definition change.
* **Test Verification Plan:**
  - `flutter test`, `flutter analyze`, `dart format --set-exit-if-changed .`, `python3 tool/check-docs.py`
  - `[x]` dueTasks excludes running ids
  - `[x]` lock with two holders: in-process via the name server, and cross-process via a python fcntl holder
  - `[x]` gate follows the job (finished, removed, dead engine, already finished); runningHere covers Run now
  - `[x]` headless skip summary and exit code
  - `[x]` watchdog: stall trip, 72 h cap, work counts, progress resets, queued never started, finishes in time
  - `[x]` fingerprint stable/changes; reconcile rewrites an old entry once and leaves an unreadable one

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `DONE`
* **Findings:**
  - ✅ **Vision & Scope** — matches #55 and #54.
  - ✅ **Business Logic & Edge Cases** — crash drops the lock (OS); an unusable lock dir does not block runs.
  - ⚠️ **Dependency & Functional Risk** — the rewrite fires each existing Windows entry once after upgrading.
  - ✅ **Completeness & User Intent** — the skip and the stall stop are both visible to the user.
* **Required Fixes:** None

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `DONE`
* **Findings:**
  - ✅ **DRY Scan** — one gate and one supervisor for every runner.
  - ✅ **Abstraction & Architecture** — the lock and the gate are separate, and the tests inject both.
  - ✅ **State Management & Data Flow** — the claim follows the real job state.
  - ✅ **Technical Debt & Deletion** — all three 6 h constants are removed.
  - ✅ **Secret Management** — no secrets are touched.
  - ✅ **Data Security (RLS)** — n/a. Lock files sit only in the app support dir, and their names come from the id only.
  - ✅ **Rate Limiting** — no new polling; the watchdog reuses the 1 s outcome poll.
  - ✅ **Error Handling** — every exit path releases the claim.
* **Required Fixes:** None

## 7️⃣ Phase 7: Implementation Checklist (Execution)
- `[x]` Gate and locks
- `[x]` Scheduler, Run now, photo backup, headless wired through the gate
- `[x]` Watchdog and 72 h cap
- `[x]` XML stamp and reconcile compare
- `[x]` Tests, docs, changelog

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `PASSED`
* **Report:**
  - `[x]` Test suite runs clean (2121 passed, 17 skipped on Linux)
  - `[x]` Code matches exact plan specifications
  - `[x]` No functional gaps identified

## 9️⃣ Phase 9: User Verification
* **Status:** `PENDING` (PR review)
* **User Feedback:** —

## 🔟 Phase 10: Wrap Up & Archival
* **System Context Updates:** `wiki/features/feat-scheduling.md` §5.6; `07-state-context.md` gains `taskRunGateProvider` and `taskRunLocksProvider`.

## ✅ Completion Note
All of it was implemented as planned. There is no widget test for the Run now SnackBar. The refusal it shows
comes from `TaskRunGate.tryClaim`, and `test/task_run_gate_test.dart` (runningHere) covers that. The Windows-only
reconcile tests are skipped on Linux CI.
