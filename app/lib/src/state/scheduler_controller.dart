import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/rclone_client.dart';
import 'engine_controller.dart';
import 'jobs_controller.dart';
import 'task_schedule.dart';
import 'tasks_controller.dart';
import 'transfer_options.dart';
import 'transfer_service.dart';

/// The snapshot the scheduler republishes on every tick so the UI can re-time
/// its due/next/last-ran labels and warn when a run had to be held back. Purely
/// in-memory runtime state — never persisted.
@immutable
class SchedulerStatus {
  const SchedulerStatus({this.tickedAt, this.skippedWhileUnavailable});

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

  @override
  bool operator ==(Object other) =>
      other is SchedulerStatus &&
      other.tickedAt == tickedAt &&
      other.skippedWhileUnavailable == skippedWhileUnavailable;

  @override
  int get hashCode => Object.hash(tickedAt, skippedWhileUnavailable);
}

/// The scheduled tasks that are due to run at [now], in list order.
///
/// Pulled out of the tick loop so its branches are unit-testable. Three gates,
/// in order: the task must carry a [TaskSchedule]; a two-way (bisync) task whose
/// baseline hasn't been established is never auto-run (its first `--resync` is
/// destructive and must be done manually once — see [SchedulerController.tick]);
/// and finally [isDue] must fire for the schedule given the task's `lastRun`.
List<TransferTask> dueTasks(List<TransferTask> tasks, DateTime now) => [
  for (final t in tasks)
    if (t.schedule != null &&
        !(t.options.mode == TransferMode.bisync &&
            !t.options.baselineEstablished) &&
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
    return const SchedulerStatus();
  }

  /// One scheduler evaluation: dispatch every due task, or — when the engine is
  /// locked/down — record that a due run had to be skipped. Public + annotated so
  /// a test can drive a single tick without waiting on the 30 s timer.
  @visibleForTesting
  void tick() {
    final now = DateTime.now();
    // Before tasks hydrate from disk the list is empty, so a cold boot fires
    // nothing here regardless of engine state.
    final due = dueTasks(ref.read(tasksProvider), now);

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

    final tasks = ref.read(tasksProvider.notifier);
    final svc = ref.read(transferServiceProvider);
    for (final t in due) {
      // Stamp lastRun BEFORE the async kickoff so the next tick can't double-fire.
      tasks.update(t.copyWith(lastRun: now));
      // Fire-and-forget the dispatch, but supervise it to a terminal state so
      // the outcome lands in history — a failed scheduled run must not vanish.
      unawaited(_runAndRecord(svc, tasks, t));
    }
    // Publish the tick (re-times UI labels) and clear any prior skip warning —
    // the engine is back, so due tasks just ran.
    state = SchedulerStatus(tickedAt: now);
  }

  /// Dispatches [t] and supervises the resulting job to a terminal state,
  /// appending the outcome to [t]'s per-run history. Kicked off unawaited from
  /// [tick]; [recordRunOutcome] owns its own error handling.
  Future<void> _runAndRecord(
    TransferService svc,
    TasksController tasks,
    TransferTask t,
  ) async {
    final jobId = await svc.transferAdvancedRaw(
      srcFs: t.srcFs,
      dstFs: t.dstFs,
      srcLabel: t.srcLabel,
      dstLabel: t.dstLabel,
      options: t.options,
    );
    await recordRunOutcome(
      readClient: () => ref.read(engineControllerProvider).client,
      tasks: tasks,
      readJobs: () => ref.read(jobsControllerProvider),
      taskId: t.id,
      jobId: jobId,
    );
  }
}

/// Default cadence for the supervised outcome poll — matches [JobsController]'s
/// own 1 s `job/status` poll so supervising a run costs no more engine traffic
/// than the Jobs panel already generates. Injectable via [recordRunOutcome] so a
/// test can drive the loop without waiting on wall-clock seconds.
const kOutcomePollInterval = Duration(seconds: 1);

/// Hard wall-clock cap on a single supervised run. Without it the GUI supervisor
/// can spin forever — a paused transfer queue leaves a job `queued` with no
/// rclone jobid (phase 1 loops), or a genuinely stuck rclone job keeps phase 2
/// polling — and each dispatch would leak one loop for the app's lifetime. When
/// it trips we record a timed-out failure so the run still lands in history.
/// Mirrors the Scheduled-Task `ExecutionTimeLimit=PT6H`. (Headless is also
/// bounded by [HeadlessRequest.timeout] + process exit; this covers the GUI.)
const kMaxSuperviseDuration = Duration(hours: 6);

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
Future<void> recordRunOutcome({
  required RcloneClient? Function() readClient,
  required TasksController tasks,
  required List<Job> Function() readJobs,
  required String taskId,
  required int jobId,
  Duration pollInterval = kOutcomePollInterval,
  Duration maxSupervise = kMaxSuperviseDuration,
}) async {
  final start = DateTime.now();
  final deadline = start.add(maxSupervise);

  Job? localJob() {
    for (final j in readJobs()) {
      if (j.id == jobId) return j;
    }
    return null;
  }

  void record({required bool ok, String? error, int? bytes}) {
    tasks.recordRun(
      taskId,
      TaskRunRecord(
        at: DateTime.now(),
        ok: ok,
        error: (error != null && error.isNotEmpty) ? error : null,
        duration: DateTime.now().difference(start),
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
    if (DateTime.now().isAfter(deadline)) {
      record(
        ok: false,
        error: 'run did not start within ${maxSupervise.inHours}h',
      );
      return;
    }
    await Future<void>.delayed(pollInterval);
  }

  // Phase 2: poll to completion. Prefer the jobs poller's own terminal signal
  // when it beats us to it (it also carries bytes/error); otherwise ask the
  // engine directly.
  while (true) {
    final job = localJob();
    if (job == null) return;
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
    // Bound a genuinely stuck rclone job so phase 2 can't poll forever.
    if (DateTime.now().isAfter(deadline)) {
      record(
        ok: false,
        error: 'run did not finish within ${maxSupervise.inHours}h',
      );
      return;
    }
    try {
      final status = await client.rpc('job/status', {'jobid': rcJobid});
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
