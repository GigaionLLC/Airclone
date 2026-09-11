---
type: "plan"
name: "Phase 3 Continuation Plan"
status: "active"
description: "Finishing bisync / crypt / scheduling + engine currency. Desktop background execution and the crypt round-trip canary have since shipped (v0.2.0-beta.1); still open are background execution on macOS/Linux (Android shipped in v0.8), the crypt reattach and rotation wizards, the bisync reliability surface, and the engine test harness."
---

# 🧭 Phase 3 Continuation Plan

Grounded in a 4-agent audit (2026-07-09) of the shipped bisync (a55), crypt (a56), scheduling (a50),
and engine-provisioning code. **Bisync/crypt/scheduling are real, working features** — this plan is
about closing their trust gaps and keeping the engine current.

## Shipped in the 2026-07-09 safety & currency batch

| Area | Change |
| :--- | :--- |
| Sync safety | One-way Sync now confirms before a destructive run (Cancel / Dry run first / Run sync) + optional `--max-delete` cap (`MaxDelete` in `_config`) surfaced in the dialog |
| Bisync safety | Ad-hoc Two-way sync no longer fires an unconfirmed `--resync` (baseline confirm dialog) and no longer loops per selected file (dirs-only); saved tasks gain **Re-establish baseline…** recovery |
| Crypt safety | Unmissable "lost password = unrecoverable data" warnings (form + done screen); editing a crypt password now requires an explicit destructive confirm (it orphans all existing data) |
| Scheduler | Last-run display, live next-run countdown, locked-engine skip warning, pure testable `dueTasks` selection |
| Engine currency | Fail-closed SHA-256 (unverifiable download = hard error); min-version gate (≥ 1.73.5) with recovery CTA; **Update engine** in Settings (version row + check + one-click update); Android pin bumped to v1.74.4 (security patch: serve s3/webdav + local symlink CVEs); CI staleness check |

## Big items (each needs its own change, in recommended order)

### 1. Background execution for scheduled tasks — mostly closed
As written, schedules only fired while the app was open (a single `Timer.periodic(30s)` in
`scheduler_controller.dart`). **Items 1, 2, 5 and 6 shipped in v0.2.0-beta.1**, so on Windows a
saved task now runs with Airclone closed. What is left is the other two desktop operating systems
(3), Android (4), and the sharp edges under "Deliberately deferred". Build order:
1. ~~**Headless entrypoint first**~~ **DONE** (shared by all desktop platforms):
   [`headless/headless_runner.dart`](../../app/lib/src/headless/headless_runner.dart). `main(List<String> args)`
   now reads the args the Windows runner had always been forwarding (`main.cpp:22-25`); `--run-task
   <id>` / `--run-due` boots a `ProviderContainer` without `runApp`, spawns rcd on its own free
   loopback port (no collision with a running GUI), runs the task(s) to terminal status, exits with a
   code.
2. ~~**Windows**: register via `schtasks`~~ **DONE** (XML form for run-missed-start catch-up) from
   the schedule editor —
   [`state/windows_task_scheduler.dart`](../../app/lib/src/state/windows_task_scheduler.dart). Read
   "Deliberately deferred" below before touching it: the orphaned-task self-heal is still open, and
   an orphan re-fires forever.
3. **macOS launchd / Linux systemd-user timers** (`Persistent=true` gives catch-up) — ~1–2 days each.
4. ~~**Android**: `workmanager` plugin + headless isolate~~ **DONE (v0.8 Phase F)**, without the
   plugin: `app/android/.../DueTasksWorker.kt` is our own `CoroutineWorker` that boots a headless
   `FlutterEngine` and runs `androidWorkEntrypoint` (`state/android_work_entrypoint.dart` →
   `runHeadlessInProcess`). The prerequisite landed first — the `airclone/native` channel moved
   out of `MainActivity` into the Application-scoped `NativeChannel.kt`, which the worker registers
   on its own engine so `nativeLibraryDir` resolves with no Activity. `TransferService.kt` lends its
   notification channel to the worker's `setForeground()` attempt — but, **measured on Android 15
   (2026-09-09)**, Android 12+ refuses that promotion to a periodic wake started in the background
   (`mAllowStartForeground false`; WorkManager's promotion is not one of the exemptions for
   periodic work). So a background wake runs inside the plain worker's ~10-minute budget, with the
   Dart run capped at 8 minutes so it ends cleanly, and a large first backup proceeds in slices,
   one per wake, resuming where it stopped. No `BOOT_COMPLETED` receiver: WorkManager re-arms
   itself after a reboot. Battery-optimization UX is still open — and must NOT request
   `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (Play policy); detect and explain instead.
5. ~~**Cross-cutting prerequisite**: encrypted-config headless unlock~~ **DONE** — the config
   password comes from the OS vault (DPAPI / Keychain / Secret Service), opt-in, with
   `headless_runner.dart` falling back to an explicit vault read when the engine's own silent unlock
   does not fire. Without it, unattended runs could not start on a locked config at all.
6. ~~**Per-run history** on the saved task~~ **DONE** — `TaskRunRecord`s on `tasks_controller.dart`,
   newest-first, capped at 10 and persisted, so a failed scheduled run is no longer
   indistinguishable from a successful one.

### 2. Crypt: prove it, reattach it, rotate it
- ~~**Round-trip canary verification**~~ **DONE** — `state/encrypt_remote_controller.dart` `_verify`
  replaced `cryptcheck [base, crypt]` (which passed trivially on empty remotes and false-alarmed on
  populated ones) with a probe *directory* created through the crypt remote and read back both ways:
  its plaintext name reappearing through the crypt remote proves rclone decrypted it, a scrambled
  name at the base proves it was encrypted going down. Safe RC primitives only, and it never fails
  the wizard — the result is a tri-state hint.
- **"Connect an existing encrypted remote" wizard**: guided reattach (base + password/salt + matching
  modes) with round-trip verification — today users must hand-recreate via the generic form and any
  mode mismatch yields silent garbage.
- **Live filename-transform preview** (promised in `wiki/core/15-security.md:55`).
- **Safe password rotation**: guided re-wrap (new crypt remote + streamed re-encrypt copy + swap)
  instead of the config/update foot-gun.

### 3. Bisync: reliability surface
- Per-pair state beyond the baseline boolean: last-run result, conflict count, listing age.
- Expose rclone recovery options: `resilient`/`recover`, `force` (past a max-delete abort),
  `checkSync`.
- Move the baseline-flip out of the `_TaskRow` widget listener into the service layer keyed by task
  id (widget-lifecycle flip can silently fail to persist → re-runs the destructive resync).
- Parse the "cannot find prior listing" error into an actionable "Re-establish baseline" CTA on the
  job row.

### 4. Engine test harness (beta-quality-review #6)
Introduce injectable seams (fetch fn + Process/HttpRcloneClient factories) so `RcloneEngine` /
`EngineController` are testable: target-triple, extraction, checksum decisions, encrypted-header
detection, and the full phase state machine (bootstrap → provision → needsPassword → start → onDied →
restart). Land before/with any further engine work.

## Deliberately deferred
- OS-level scheduling UI before the headless entrypoint exists (would over-promise).
- Bisync filters parity and `--max-delete` abort override (`force`) until per-pair state exists.
- Crypt wizard exposure of `no_data_encryption`/`filename_encoding` (quick win, but batch scope was
  safety-first; add with the reattach wizard).
- **Orphaned Scheduled Task self-heal** (from the phase-3 headless review): if `schtasks /Delete`
  fails or a task's SharedPreferences entry vanishes on another profile/machine, the OS Scheduled
  Task survives and runs `airclone --run-task <id>` forever, each fire hitting "no saved task with
  id" and exiting 2 — no cap, no cleanup, no user signal. Fix: make the headless unknown-id branch
  unregister its own Scheduled Task (`WindowsTaskScheduler.unregister(request.taskId)`) before
  returning exit 2, so an orphan removes itself on its next fire. Deferred (needs care to only
  self-delete when the id is genuinely absent, not merely un-hydrated).
- **Cross-process SharedPreferences whole-file clobber** (headless concurrency note honesty): the
  desktop legacy prefs backend rewrites ALL keys to one file atomically, so a GUI/headless write
  collision drops the loser's ENTIRE prefs snapshot for that write (engine flags, concurrency,
  backdrop, tasks…), not just the run-history stamp the `headless_runner` doc calls out. Real fix is
  a scoped/segregated store or a cross-process lock; until then the doc note understates the blast
  radius. Tracked here as a known sharp edge (background runs are expected app-closed, so collisions
  are rare).
