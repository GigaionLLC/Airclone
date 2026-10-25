import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'engine_controller.dart';
import 'file_ops.dart';
import 'poll_cadence.dart';
import 'jobs_controller.dart';
import 'scheduler_pause.dart';
import 'scheduler_registration.dart';
import 'task_kind.dart';
import 'task_run_gate.dart';
import 'task_schedule.dart';
import 'tasks_controller.dart';
import 'transfer_options.dart';
import 'transfer_service.dart';
import 'windows_task_scheduler.dart';

/// The snapshot the scheduler republishes on every tick so the UI can re-time
/// its due/next/last-ran labels and warn when a run had to be held back. Purely
/// in-memory runtime state — never persisted.
@immutable
class SchedulerStatus {
  const SchedulerStatus({
    this.tickedAt,
    this.skippedWhileUnavailable,
    this.skippedWhileRunning = const {},
  });

  /// Wall-clock time of the most recent tick (null before the first). It changes
  /// every 30 s, so a widget that watches this provider rebuilds and re-evaluates
  /// relative-time labels ("due now", "next …", "last ran …") that would
  /// otherwise go stale while the tasks dialog sits open.
  final DateTime? tickedAt;

  /// When a due task was last passed over because the engine was locked/down
  /// (null if that hasn't happened). The scheduler can't run anything while the
  /// engine is unavailable, so rather than silently drop a due slot it records it
  /// here for the tasks panel to surface. Cleared on the next tick that runs with
  /// the engine available.
  final DateTime? skippedWhileUnavailable;

  /// Ids of the tasks that were due on the latest tick but held back because
  /// their previous run is still going (see [TaskRunGate]). Their `lastRun` is
  /// deliberately NOT advanced, so each one runs once as soon as the run in
  /// flight ends, rather than losing the slot. Recomputed every tick, so an
  /// entry disappears when that catch-up run starts.
  final Set<String> skippedWhileRunning;

  @override
  bool operator ==(Object other) =>
      other is SchedulerStatus &&
      other.tickedAt == tickedAt &&
      other.skippedWhileUnavailable == skippedWhileUnavailable &&
      setEquals(other.skippedWhileRunning, skippedWhileRunning);

  @override
  int get hashCode => Object.hash(
    tickedAt,
    skippedWhileUnavailable,
    Object.hashAllUnordered(skippedWhileRunning),
  );
}

/// The scheduled tasks that are due to run at [now], in list order.
///
/// Pulled out of the tick loop so its branches are unit-testable. Four gates,
/// in order: the task must carry a [TaskSchedule]; a two-way (bisync) task whose
/// baseline hasn't been established is never auto-run (its first `--resync` is
/// destructive and must be done manually once — see [SchedulerController.tick]);
/// a task whose id is in [running] already has a run in flight and never gets a
/// second one beside it ([TaskRunGate]); and finally [isDue] must fire for the
/// schedule given the task's `lastRun`.
List<TransferTask> dueTasks(
  List<TransferTask> tasks,
  DateTime now, {
  Set<String> running = const {},
}) => [
  for (final t in tasks)
    if (t.schedule != null &&
        !(t.options.mode == TransferMode.bisync &&
            !t.options.baselineEstablished) &&
        !running.contains(t.id) &&
        isDue(t.schedule!, now: now, lastRun: t.lastRun))
      t,
];

/// Drives scheduled saved tasks **while the app is open**. A single app-lifetime
/// timer ticks every 30 s and runs any task whose [TaskSchedule] is due, reusing
/// the normal run path ([TransferService.transferAdvancedRaw]).
///
/// There is no OS background service: if Airclone is closed at a scheduled time
/// the run is skipped and caught up once on the next launch (see [isDue]).
///
/// Lifecycle mirrors [StatsController]: the timer is created in [build] and
/// cancelled in `ref.onDispose`. The provider must be force-read once at launch
/// (HomeScreen) so the timer actually arms — Riverpod providers are lazy.
class SchedulerController extends Notifier<SchedulerStatus> {
  Timer? _timer;

  @override
  SchedulerStatus build() {
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    ref.onDispose(() => _timer?.cancel());
    // Make the OS registrations match the saved tasks, once, at launch. This is
    // also where the one-time seeding of `runWhileClosed` happens - see
    // state/scheduler_registration.dart - so it must run before anything else
    // reconciles, which is why it lives in the provider that HomeScreen
    // force-reads at startup rather than in a widget that may never build.
    unawaited(
      reconcileRegistrations(
        notifier: ref.read(tasksProvider.notifier),
        readTasks: () => ref.read(tasksProvider),
        os: ref.read(windowsTaskSchedulerProvider),
        pollMinutes: ref.read(pollCadenceProvider),
        seed: true,
      ),
    );
    return const SchedulerStatus();
  }

  /// One scheduler evaluation: dispatch every due task, or — when the engine is
  /// locked/down — record that a due run had to be skipped. Public + annotated so
  /// a test can drive a single tick without waiting on the 30 s timer.
  @visibleForTesting
  void tick() {
    final now = DateTime.now();
    // A tripped circuit breaker stops EVERYTHING until a human resumes it. The
    // causes of a run deleting more than its cap are environmental - an
    // unmounted drive, an expired token, a renamed folder - and they are rarely
    // confined to the one task that noticed. See state/scheduler_pause.dart.
    if (ref.read(schedulerPausedProvider) != null) return;
    // Before tasks hydrate from disk the list is empty, so a cold boot fires
    // nothing here regardless of engine state.
    final all = ref.read(tasksProvider);
    final due = dueTasks(all, now);

    // Engine not ready (still starting, config locked, or crashed): we can't run
    // anything now. Rather than silently dropping a due slot — which used to fail
    // invisibly — record it so the tasks panel can prompt the user to unlock.
    if (ref.read(engineControllerProvider).client == null) {
      state = SchedulerStatus(
        tickedAt: now,
        skippedWhileUnavailable: due.isNotEmpty
            ? now
            : state.skippedWhileUnavailable,
      );
      return;
    }

    // A due task whose previous run is still going is held back, not run a
    // second time beside it. Its lastRun stays where it is, so it is still due
    // on the tick after that run ends and runs once then: a long run delays the
    // next slot rather than swallowing it. The skip is published so the tasks
    // panel can say why a due task did not start.
    final gate = ref.read(taskRunGateProvider.notifier);
    final runnable = dueTasks(
      all,
      now,
      running: ref.read(taskRunGateProvider).keys.toSet(),
    );
    final busy = {
      for (final t in due)
        if (!runnable.contains(t)) t.id,
    };

    final tasks = ref.read(tasksProvider.notifier);
    final svc = ref.read(transferServiceProvider);
    for (final t in runnable) {
      // Fire-and-forget the dispatch, but supervise it to a terminal state so
      // the outcome lands in history — a failed scheduled run must not vanish.
      // The gate claim inside it is taken synchronously, so the next tick
      // cannot double-fire even before lastRun is stamped.
      unawaited(_runAndRecord(svc, tasks, gate, t, now));
    }
    // Publish the tick (re-times UI labels) and clear any prior skip warning —
    // the engine is back, so due tasks just ran.
    state = SchedulerStatus(tickedAt: now, skippedWhileRunning: busy);
  }

  /// Dispatches [t] and supervises the resulting job to a terminal state,
  /// appending the outcome to [t]'s per-run history. Kicked off unawaited from
  /// [tick]; [recordRunOutcome] owns its own error handling.
  Future<void> _runAndRecord(
    TransferService svc,
    TasksController tasks,
    TaskRunGate gate,
    TransferTask t,
    DateTime now,
  ) async {
    final claim = await gate.tryClaim(t.id);
    if (claim != TaskClaim.claimed) {
      // Another process (a background run) is running this task. Same policy
      // as a run in flight here: lastRun is left alone so the slot runs once
      // that run ends, and the skip shows in the panel until then.
      if (claim == TaskClaim.runningElsewhere) {
        state = SchedulerStatus(
          tickedAt: state.tickedAt,
          skippedWhileUnavailable: state.skippedWhileUnavailable,
          skippedWhileRunning: {...state.skippedWhileRunning, t.id},
        );
      }
      return;
    }
    // Stamp lastRun only once the run is really ours, BEFORE the async
    // dispatch, so a slot is never consumed by a run that did not happen.
    tasks.update(t.copyWith(lastRun: now));
    // The guard the delete cap cannot be: a cap of 100 still lets a destination
    // of 80 files be wiped. Nothing else catches that.
    if (await _sourceIsUnsafe(t)) {
      gate.release(t.id);
      tasks.recordRun(
        t.id,
        TaskRunRecord(
          at: DateTime.now(),
          ok: false,
          error: kEmptySourceRefusal,
          duration: Duration.zero,
        ),
      );
      return;
    }
    final int jobId;
    try {
      jobId = await svc.transferAdvancedRaw(
        srcFs: t.srcFs,
        dstFs: t.dstFs,
        srcLabel: t.srcLabel,
        dstLabel: t.dstLabel,
        // Two run-time enforcements, both for the same reason: a task saved
        // before a constraint existed, or edited through the raw advanced dialog,
        // must not be able to run as something other than what its name says.
        //
        // A backup is copy-only with versions kept, whatever its stored options
        // say; a repeating Sync never runs uncapped.
        options: t.kind == TaskKind.transfer
            ? withScheduledDeleteCap(t.options)
            : backupOptions(t.options),
      );
    } catch (_) {
      gate.release(t.id);
      rethrow;
    }
    gate.attach(t.id, jobId);
    await recordRunOutcome(
      readClient: () => ref.read(engineControllerProvider).client,
      tasks: tasks,
      readJobs: () => ref.read(jobsControllerProvider),
      taskId: t.id,
      jobId: jobId,
      stopJob: (id) => ref.read(jobsControllerProvider.notifier).stop(id),
      onOutcome: ({required bool ok, String? error}) {
        if (ok || !isDeleteCapError(error)) return;
        unawaited(
          ref
              .read(schedulerPausedProvider.notifier)
              .pause(
                SchedulerPause(
                  at: DateTime.now(),
                  taskId: t.id,
                  taskName: '${t.srcLabel} -> ${t.dstLabel}',
                  reason: error ?? '',
                ),
              ),
        );
      },
    );
  }

  /// Whether a scheduled run of [t] must be refused because its source has
  /// stopped answering the way a real folder does.
  ///
  /// This is the guard the delete cap cannot be. A cap of 100 still lets a
  /// destination holding 80 files be wiped, and the case that produces both —
  /// a source that vanished or emptied — is the same one. The two together
  /// cover the range; neither covers it alone.
  ///
  /// Only a one-way **Sync** is checked, because only a Sync deletes at the
  /// destination to match the source. Copy and Move from a vanished source are
  /// no-ops, and a two-way sync caps by percentage instead.
  ///
  /// **Unreadable counts as unsafe, and that is a deliberate difference from
  /// the interactive preflight.** A human watching a preview can be told "could
  /// not read that" and decide; a timer at 3am cannot. If the engine will not
  /// list the source, the safe answer is not to run something destructive
  /// against it — and the refusal lands in the run history that Settings →
  /// Automation surfaces, so it is not the silent stop this feature exists to
  /// prevent.
  Future<bool> _sourceIsUnsafe(TransferTask t) async {
    // A backup is copy-only by construction, so it can never delete at the
    // destination and an empty source is a harmless no-op rather than a wipe.
    if (t.kind != TaskKind.transfer) return false;
    if (t.options.mode != TransferMode.sync) return false;
    final empty = await ref.read(fileOpsProvider).isRootEmpty(t.srcFs);
    return empty ?? true;
  }
}

/// Recorded instead of running when a scheduled Sync's source will not answer.
///
/// A whole sentence rather than a code, because it is read in a list of run
/// outcomes by someone working out why last night did nothing.
const String kEmptySourceRefusal =
    'Refused to run: the source is empty or could not be read, and a Sync '
    'would have deleted the destination to match it.';

/// Default cadence for the supervised outcome poll — matches [JobsController]'s
/// own 1 s `job/status` poll so supervising a run costs no more engine traffic
/// than the Jobs panel already generates. Injectable via [recordRunOutcome] so a
/// test can drive the loop without waiting on wall-clock seconds.
const kOutcomePollInterval = Duration(seconds: 1);

/// How long a running job may go without moving a byte or doing any other
/// work (checks, deletes, renames, server-side copies, listing) before the
/// supervisor calls it stuck, stops it, and records the failure.
///
/// A wall-clock cap cannot tell a stuck run from a big one: a first backup of
/// a few terabytes takes days, and one cut at six hours restarts every night
/// and never finishes. A no-progress window can. Sixty minutes, because:
/// rclone's own I/O idle timeout (`--timeout`, 5 min) and its retries already
/// surface a dead connection far sooner, so anything quiet for an hour has
/// stalled in a way rclone is not handling; listing a huge tree counts as
/// work, so a slow walk does not trip it; and a single large server-side copy
/// or a slow provider-side operation can sit without visible progress for tens
/// of minutes. Tripping a healthy run costs a whole restart, while noticing a
/// stuck one half an hour later costs nothing more than that half hour.
const kStallWindow = Duration(minutes: 60);

/// Outer wall-clock cap on a single supervised run, the backstop behind
/// [kStallWindow]. It bounds the cases the watchdog cannot see: a paused
/// transfer queue that leaves a job `queued` with no rclone jobid (phase 1),
/// and a job whose counters keep creeping without ever finishing. Without it
/// each dispatch could leak one loop for the app's lifetime. When it trips the
/// job is stopped and a timed-out failure is recorded, so the run still lands
/// in history. The same 72 hours is the Scheduled-Task `ExecutionTimeLimit`
/// (`PT72H`) and the headless default (`kDefaultTimeoutMinutes`), so every
/// path gives up at the same point.
const kMaxSuperviseDuration = Duration(hours: 72);

/// "60 min", "72 h": a duration as the run history shows it.
String _span(Duration d) => d.inMinutes >= 120 && d.inMinutes % 60 == 0
    ? '${d.inHours} h'
    : '${d.inMinutes} min';

/// Supervises one dispatched task run to its terminal state and appends the
/// outcome to the task's capped per-run history. Shared by the scheduler tick
/// ([SchedulerController._runAndRecord]) and manual runs (`_TaskRow._run`).
///
/// [jobId] is the LOCAL id returned by [TransferService.transferAdvancedRaw]. We
/// resolve its rclone async jobid off [readJobs] once dispatch assigns it, then
/// poll the engine's `job/status` — the same finished/success/error read
/// [JobsController] performs — until the run terminates. If the local job settles
/// into a terminal [JobStatus] before it ever received an rclone jobid (a
/// dispatch failure, e.g. "Engine not ready"), the outcome is recorded from that
/// instead.
///
/// Kick off with `unawaited(...)`: the loop owns its error handling, always
/// records exactly one [TaskRunRecord], and never leaks an unhandled rejection.
///
/// [readClient] is a live GETTER, not a captured reference: the engine's client
/// goes null the moment rcd dies ([EngineController.onDied]), and re-reading it
/// each poll lets the loop notice death promptly and bail instead of spinning to
/// [maxSupervise] against a stale non-null handle.
///
/// The stall watchdog: once the job is running, if neither its bytes nor its
/// other work count ([Job.work]) moves for [stallWindow], the job is stopped
/// through [stopJob] and a failure naming the stall is recorded. [maxSupervise]
/// is the outer cap over both phases and stops the job the same way. [now] is
/// the clock both read, injectable so a test can drive hours in milliseconds.
Future<void> recordRunOutcome({
  required RcloneClient? Function() readClient,
  required TasksController tasks,
  required List<Job> Function() readJobs,
  required String taskId,
  required int jobId,
  Duration pollInterval = kOutcomePollInterval,
  Duration maxSupervise = kMaxSuperviseDuration,
  Duration stallWindow = kStallWindow,
  DateTime Function() now = DateTime.now,
  Future<void> Function(int localJobId)? stopJob,
  void Function({required bool ok, String? error})? onOutcome,
}) async {
  final start = now();
  final deadline = start.add(maxSupervise);

  Future<void> stop() async {
    try {
      await stopJob?.call(jobId);
    } catch (_) {
      // Best effort: the failure is recorded either way.
    }
  }

  Job? localJob() {
    for (final j in readJobs()) {
      if (j.id == jobId) return j;
    }
    return null;
  }

  void record({required bool ok, String? error, int? bytes}) {
    // Every terminal path in this function goes through here, which is why the
    // circuit breaker hooks it rather than the call sites: a future platform
    // cannot add a path that skips the check without also skipping history.
    onOutcome?.call(ok: ok, error: error);
    tasks.recordRun(
      taskId,
      TaskRunRecord(
        at: now(),
        ok: ok,
        error: (error != null && error.isNotEmpty) ? error : null,
        duration: now().difference(start),
        bytes: (bytes != null && bytes > 0) ? bytes : null,
      ),
    );
  }

  // Phase 1: wait for dispatch to assign the rclone jobid — or for the local job
  // to settle (a pre-dispatch failure) before it ever got one. `late final`: the
  // loop below assigns exactly once (assign → break), which the compiler can't
  // prove for a plain final local.
  late final int rcJobid;
  while (true) {
    final job = localJob();
    if (job == null) return; // cleared out from under us — nothing to record.
    final id = job.jobid;
    if (id != null) {
      rcJobid = id;
      break;
    }
    if (job.isFinished) {
      record(
        ok: job.status == JobStatus.success,
        error: job.error,
        bytes: job.bytes,
      );
      return;
    }
    // A paused queue can leave a job `queued` with no jobid indefinitely; the
    // wall-clock cap stops this phase from spinning for the app's lifetime.
    if (now().isAfter(deadline)) {
      // Stop it too: a queued job left behind would still start later.
      await stop();
      record(
        ok: false,
        error: 'run did not start within ${_span(maxSupervise)}',
      );
      return;
    }
    await Future<void>.delayed(pollInterval);
  }

  // Phase 2: poll to completion. Prefer the jobs poller's own terminal signal
  // when it beats us to it (it also carries bytes/error); otherwise ask the
  // engine directly. The watchdog starts here, at the moment the job is really
  // running: time spent queued is not a stall.
  var lastBytes = -1;
  var lastWork = -1;
  var lastProgress = now();
  while (true) {
    final job = localJob();
    if (job == null) return;
    if (job.bytes != lastBytes || job.work != lastWork) {
      lastBytes = job.bytes;
      lastWork = job.work;
      lastProgress = now();
    }
    if (job.isFinished) {
      record(
        ok: job.status == JobStatus.success,
        error: job.error,
        bytes: job.bytes,
      );
      return;
    }
    // Engine vanished after dispatch (crash/quit): re-read the LIVE client so we
    // catch onDied promptly. The jobs poller can't advance the job past a dead
    // engine either, so record a failure (rather than returning silently, which
    // would let a caller fall back to a prior run's stale [OK]) and stop.
    final client = readClient();
    if (client == null) {
      record(ok: false, error: 'the engine stopped before the run finished');
      return;
    }
    // A job that has moved nothing for the whole window is stuck: stop it, so
    // the slot is free for the next run, and say why in its history.
    if (now().difference(lastProgress) > stallWindow) {
      await stop();
      record(
        ok: false,
        error:
            'stopped: no progress for ${_span(stallWindow)} (no bytes moved '
            'and no files checked)',
        bytes: job.bytes,
      );
      return;
    }
    // The outer cap, for a run that creeps but never finishes.
    if (now().isAfter(deadline)) {
      await stop();
      record(
        ok: false,
        error: 'stopped: run did not finish within ${_span(maxSupervise)}',
        bytes: job.bytes,
      );
      return;
    }
    try {
      final status = await RcApi(client).job.status(rcJobid);
      if (status['finished'] == true) {
        final err = status['error'];
        record(
          ok: status['success'] == true,
          error: err is String ? err : null,
          bytes: localJob()?.bytes,
        );
        return;
      }
    } catch (_) {
      // Transient engine hiccup — retry next tick (mirrors JobsController._poll).
    }
    await Future<void>.delayed(pollInterval);
  }
}

final schedulerProvider =
    NotifierProvider<SchedulerController, SchedulerStatus>(
      SchedulerController.new,
    );
