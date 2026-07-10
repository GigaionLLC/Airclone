import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/config_password_vault.dart';
import '../state/engine_controller.dart';
import '../state/engine_flags.dart';
import '../state/jobs_controller.dart';
import '../state/scheduler_controller.dart';
import '../state/tasks_controller.dart';
import '../state/transfer_service.dart';

/// The headless background entrypoint: `airclone --run-task <id>` runs one saved
/// [TransferTask] by its stable id; `airclone --run-due` runs every task whose
/// schedule is due (`isDue`). It boots the rclone engine and drives the same run
/// path the in-app scheduler uses, but WITHOUT a UI, then exits with a code the
/// OS scheduler (schtasks / launchd / systemd) can act on:
///
///   0  ran to completion with no failures (or nothing was due)
///   1  at least one task failed (a wall-clock timeout counts as a failure)
///   2  could not start: engine missing/failed, an encrypted config with no
///      stored password, or a bad/unknown task id
///
/// These exit codes and the exact flag strings above are a contract the OS
/// scheduler registrations depend on — do not rename them lightly.
///
/// Concurrency: the engine spawns `rcd` on a FREE loopback port (see
/// `HttpRcloneClient._freeLoopbackPort`), so a headless run coexists safely
/// with a running GUI instance. The one KNOWN sharp edge — deliberately not
/// solved here — is that both processes persist tasks/settings through
/// SharedPreferences, so a headless `recordRun`/`lastRun` write can race a GUI
/// write of the same key (last-writer-wins). Background runs are expected with
/// the app closed; running both at once may drop one process's history stamp.

// --- CLI contract -----------------------------------------------------------

/// Run exactly one saved task by its [TransferTask.id]. Takes a value.
const String kRunTaskFlag = '--run-task';

/// Run every task whose schedule is due right now. Bare flag.
const String kRunDueFlag = '--run-due';

/// Overall wall-clock cap for the whole run, in minutes. Takes a value.
const String kTimeoutFlag = '--timeout-minutes';

/// Default wall-clock cap (6h) when [kTimeoutFlag] is absent or unparsable.
const int kDefaultTimeoutMinutes = 360;

/// Process exit codes (see the class doc for their meaning).
const int kExitOk = 0;
const int kExitFailed = 1;
const int kExitCannotStart = 2;

// --- Pure parsing / decision helpers (unit-tested, no engine/process) --------

/// Whether [args] request a headless run. Kept in sync with the Windows runner's
/// own scan (`windows/runner/main.cpp`) so the native side hides the window for
/// exactly the invocations this branches on — including the `--run-task=<id>`
/// joined form and a bare `--run-task` (which then exits 2 for the missing id).
bool isHeadlessInvocation(List<String> args) {
  for (final a in args) {
    if (a == kRunDueFlag) return true;
    if (a == kRunTaskFlag || a.startsWith('$kRunTaskFlag=')) return true;
  }
  return false;
}

/// A parsed headless invocation. [taskId] is null for a `--run-due` run (or a
/// malformed bare `--run-task` with no value).
@immutable
class HeadlessRequest {
  const HeadlessRequest({
    required this.runDue,
    required this.taskId,
    required this.timeout,
  });

  final bool runDue;
  final String? taskId;
  final Duration timeout;
}

/// Returns the value following [flag] in [args], accepting both the
/// space-separated (`--flag value`) and `=`-joined (`--flag=value`) forms, or
/// null when the flag is absent or trails with no value.
String? _flagValue(List<String> args, String flag) {
  final joined = '$flag=';
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == flag) return (i + 1 < args.length) ? args[i + 1] : null;
    if (a.startsWith(joined)) return a.substring(joined.length);
  }
  return null;
}

/// Parses a headless invocation. Unknown args are tolerated (the toolchain and
/// the OS scheduler may inject their own, e.g. `--enable-dart-profiling`); only
/// the three flags above are read. A non-numeric or non-positive
/// `--timeout-minutes` falls back to [kDefaultTimeoutMinutes].
HeadlessRequest parseHeadlessArgs(List<String> args) {
  final rawTimeout = int.tryParse(_flagValue(args, kTimeoutFlag) ?? '');
  return HeadlessRequest(
    runDue: args.contains(kRunDueFlag),
    taskId: _flagValue(args, kRunTaskFlag),
    timeout: Duration(
      minutes: (rawTimeout != null && rawTimeout > 0)
          ? rawTimeout
          : kDefaultTimeoutMinutes,
    ),
  );
}

/// The process exit code for a run that reached the task-execution stage, given
/// each task's terminal ok flag. An empty list (nothing due) is a clean 0; any
/// failure is 1. [timedOut] forces 1 even when every *completed* task was ok —
/// the wall-clock cap tripped, so the in-flight work is unproven. Startup
/// failures ([kExitCannotStart]) are decided earlier, before tasks run.
int exitCodeForRun(List<bool> outcomes, {bool timedOut = false}) {
  if (timedOut) return kExitFailed;
  return outcomes.any((ok) => !ok) ? kExitFailed : kExitOk;
}

/// One task's headless result, for the stdout summary and the exit-code roll-up.
@immutable
class HeadlessTaskResult {
  const HeadlessTaskResult({
    required this.taskId,
    required this.name,
    required this.ok,
    this.error,
    this.bytes,
  });

  final String taskId;
  final String name;
  final bool ok;
  final String? error;
  final int? bytes;

  /// The single line this task contributes to the stdout summary. Prefixed with
  /// a fixed-width `[OK  ]`/`[FAIL]` tag so a log scrape can grep failures.
  String get summaryLine {
    final tag = ok ? 'OK  ' : 'FAIL';
    final detail = ok
        ? (bytes != null ? ' — $bytes bytes' : '')
        : ' — ${error ?? 'unknown error'}';
    return '[$tag] $name [$taskId]$detail';
  }
}

// --- Runtime entrypoint (engine + process; not unit-tested) ------------------

/// Boots a headless run for [args] and exits the process. Owns its own
/// [WidgetsFlutterBinding] (plugins — path_provider / shared_preferences /
/// flutter_secure_storage — need it) but never calls `runApp`: there is no
/// widget tree, no window, and crucially no `flutter_acrylic` pre-frame backdrop
/// sequence (main() branches here BEFORE any window/backdrop init — that
/// sequence has no window to tint and hangs before the first frame on mobile;
/// see cc9d330 and `window_backdrop.dart`).
Future<void> runHeadless(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final request = parseHeadlessArgs(args);
  final container = ProviderContainer();
  final summary = <String>[];
  var code = kExitCannotStart;
  try {
    // Wrap the WHOLE run — engine boot included — under one outer deadline. The
    // inner `_runSelected` already caps the task-execution stage at
    // request.timeout, but the boot stage before it (isConfigEncrypted /
    // findExisting shell out to rclone with no timeout) runs outside that cap; a
    // wedged boot subprocess would otherwise leave this process spinning its
    // message loop forever as an invisible Task-Scheduler zombie. The slack lets
    // the inner cap fire first (clean per-task summary + exit 1) on a normal
    // overrun, so this only trips on a genuinely stuck boot/dispatch.
    code = await _runHeadless(
      container,
      request,
      summary,
    ).timeout(request.timeout + const Duration(minutes: 2));
  } on TimeoutException {
    stderr.writeln(
      'airclone: headless run exceeded its wall-clock cap (engine boot or '
      'dispatch wedged) — aborting.',
    );
    code = kExitFailed;
  } catch (e, s) {
    stderr.writeln('airclone: headless run crashed: $e\n$s');
    code = kExitCannotStart;
  } finally {
    // Always stop the engine we may have spawned (a no-op if it never started),
    // then flush the one-line-per-task summary to stdout before we exit.
    try {
      await container.read(engineControllerProvider).client?.quit();
    } catch (_) {
      /* best-effort shutdown */
    }
    for (final line in summary) {
      stdout.writeln(line);
    }
    container.dispose();
  }
  exit(code);
}

/// The body of [runHeadless], returning an exit code and appending summary
/// lines. Split out so the finally in [runHeadless] owns cleanup regardless of
/// which branch returns.
Future<int> _runHeadless(
  ProviderContainer container,
  HeadlessRequest request,
  List<String> summary,
) async {
  // A bare `--run-task` with no id can't target anything — fail before we pay
  // for an engine start (bad task id → 2).
  if (!request.runDue && request.taskId == null) {
    stderr.writeln('airclone: $kRunTaskFlag requires a task id.');
    return kExitCannotStart;
  }

  // Hydrate the SharedPreferences-backed providers we depend on, then use
  // getInstance() as a sync-point: each Notifier._load awaits the same cached
  // instance future and its synchronous tail (getBool/getString + state
  // assignment) runs before ours (registered earlier), so both have hydrated by
  // the time this returns.
  //   • tasksProvider — the task list we select from (no engine needed to read).
  //   • rememberConfigPasswordProvider — so a needsPassword unlock below re-saves
  //     rather than WIPES the stored password. unlockAndStart now awaits its own
  //     ensureLoaded() before the save/clear decision, so this read is belt-and-
  //     suspenders rather than load-bearing, but keeping it warms the value here.
  //   • engineFlagsProvider — the engine spawns with the user's saved flags
  //     (engine_controller._startWith reads it during bootstrap); un-hydrated,
  //     a scheduled run would silently drop e.g. a saved `--bwlimit`, letting a
  //     metered backup saturate the link when no one can intervene.
  //   • transferConcurrencyProvider — so a `--run-due` batch honours the user's
  //     concurrency limit rather than dispatching everything at once.
  container.read(tasksProvider);
  container.read(rememberConfigPasswordProvider);
  container.read(engineFlagsProvider);
  container.read(transferConcurrencyProvider);
  await SharedPreferences.getInstance();
  final tasks = container.read(tasksProvider);

  // Resolve the selection BEFORE starting the engine, so an unknown id or an
  // empty due-set never spawns rcd for nothing.
  final List<TransferTask> selected;
  if (request.runDue) {
    selected = dueTasks(tasks, DateTime.now());
    if (selected.isEmpty) {
      summary.add('run-due: nothing due.');
      return kExitOk;
    }
  } else {
    final match = [
      for (final t in tasks)
        if (t.id == request.taskId) t,
    ];
    if (match.isEmpty) {
      stderr.writeln('airclone: no saved task with id "${request.taskId}".');
      return kExitCannotStart;
    }
    selected = match;
  }

  // There is work to do — bring the engine up now.
  final startError = await _startEngine(container);
  if (startError != null) {
    stderr.writeln('airclone: $startError');
    return kExitCannotStart;
  }

  return _runSelected(container, request, selected, summary);
}

/// Transient phases the engine passes through while coming up; we wait for it to
/// leave them for a settled phase (ready / needsPassword / notInstalled / error).
const Set<EnginePhase> _transientPhases = {
  EnginePhase.idle,
  EnginePhase.locating,
  EnginePhase.provisioning,
  EnginePhase.starting,
};

/// Drives [EngineController] to a settled state and, for an encrypted config,
/// unlocks it from the OS vault. Returns null on a ready engine, or a
/// human-readable reason it could not start (mapped to exit 2 by the caller).
Future<String?> _startEngine(ProviderContainer container) async {
  final engine = container.read(engineControllerProvider.notifier);
  await engine.bootstrap();
  var phase = await _awaitEngineSettled(container);

  // Encrypted config: there is no human to type the password. bootstrap() itself
  // already attempts a silent unlock from the OS vault (DPAPI / Keychain / Secret
  // Service) on a cold start, so parking in needsPassword means that attempt was
  // absent or failed. Fall back to an explicit vault read + unlock (which also
  // retries past a transient start failure); an absent password → we genuinely
  // can't proceed unattended.
  if (phase == EnginePhase.needsPassword) {
    final password = await container.read(configPasswordVaultProvider).read();
    if (password == null || password.isEmpty) {
      return 'the rclone config is encrypted but no config password is '
          'stored — enable "Remember config password" in Settings to allow '
          'unattended runs.';
    }
    await engine.unlockAndStart(password);
    phase = await _awaitEngineSettled(container);
  }

  final st = container.read(engineControllerProvider);
  if (!st.isReady) {
    // needsPassword here means the stored password was wrong; any other
    // non-ready phase is a missing binary or a failed start.
    return 'the engine did not start (${st.message ?? phase.name}).';
  }
  return null;
}

/// Polls the engine until it leaves the [_transientPhases], or [timeout]
/// elapses. `bootstrap()` already fully awaits its own async chain, so this
/// usually returns on the first read; the poll is a defensive cap on a stuck
/// provision/start (e.g. a slow first-time engine download).
Future<EnginePhase> _awaitEngineSettled(
  ProviderContainer container, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final phase = container.read(engineControllerProvider).phase;
    if (!_transientPhases.contains(phase)) return phase;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return container.read(engineControllerProvider).phase;
}

/// Dispatches every [selected] task, supervises each to a terminal state, and
/// records its outcome — all under one wall-clock [HeadlessRequest.timeout].
/// Returns the process exit code and appends a summary line per task.
Future<int> _runSelected(
  ProviderContainer container,
  HeadlessRequest request,
  List<TransferTask> selected,
  List<String> summary,
) async {
  final now = DateTime.now();
  final tasksCtrl = container.read(tasksProvider.notifier);
  final svc = container.read(transferServiceProvider);
  final results = <String, HeadlessTaskResult>{};

  Future<void> runOne(TransferTask t) async {
    try {
      // Stamp lastRun before dispatch (mirrors SchedulerController.tick) so a
      // later --run-due can't treat this slot as still pending.
      tasksCtrl.update(t.copyWith(lastRun: now));
      final jobId = await svc.transferAdvancedRaw(
        srcFs: t.srcFs,
        dstFs: t.dstFs,
        srcLabel: t.srcLabel,
        dstLabel: t.dstLabel,
        options: t.options,
      );
      // Reuse the scheduler's supervisor verbatim: it polls the job to terminal
      // and appends exactly one [TaskRunRecord] to the task's capped history.
      // Pass a live client GETTER so mid-run engine death is detected promptly
      // (a captured null-able reference would stay non-null past onDied).
      await recordRunOutcome(
        readClient: () => container.read(engineControllerProvider).client,
        tasks: tasksCtrl,
        readJobs: () => container.read(jobsControllerProvider),
        taskId: t.id,
        jobId: jobId,
      );
      // Only trust a record this run actually produced. If the supervisor
      // returned without adding one (engine vanished), _latestRecordFor would
      // hand back a PRIOR run's entry and could report a stale [OK] for a run
      // whose engine died — so treat a record older than this dispatch as "no
      // outcome" and fail the task explicitly.
      final rec = _latestRecordFor(container, t.id);
      final fresh = rec != null && !rec.at.isBefore(now);
      results[t.id] = HeadlessTaskResult(
        taskId: t.id,
        name: t.name,
        ok: fresh && rec.ok,
        error: fresh
            ? rec.error
            : 'the run ended without recording an outcome (engine stopped?)',
        bytes: fresh ? rec.bytes : null,
      );
    } catch (e) {
      // recordRunOutcome owns its own errors, so this only guards an unexpected
      // throw; keep it from rejecting the whole Future.wait.
      results[t.id] = HeadlessTaskResult(
        taskId: t.id,
        name: t.name,
        ok: false,
        error: '$e',
      );
    }
  }

  var timedOut = false;
  try {
    await Future.wait(selected.map(runOne)).timeout(request.timeout);
  } on TimeoutException {
    // The overall cap tripped; in-flight runs keep their engine work but we stop
    // waiting and report a failure. The process exits right after cleanup.
    timedOut = true;
  }

  // Order the summary by the input selection; any task that didn't land a
  // result before the cap is reported as a failure.
  final ordered = <HeadlessTaskResult>[
    for (final t in selected)
      results[t.id] ??
          HeadlessTaskResult(
            taskId: t.id,
            name: t.name,
            ok: false,
            error: 'did not finish within ${request.timeout.inMinutes} min',
          ),
  ];
  for (final r in ordered) {
    summary.add(r.summaryLine);
  }
  return exitCodeForRun([for (final r in ordered) r.ok], timedOut: timedOut);
}

/// The newest [TaskRunRecord] for [id] (history is newest-first), or null when
/// the task is gone or has no recorded run yet.
TaskRunRecord? _latestRecordFor(ProviderContainer container, String id) {
  for (final t in container.read(tasksProvider)) {
    if (t.id == id) return t.history.isNotEmpty ? t.history.first : null;
  }
  return null;
}
