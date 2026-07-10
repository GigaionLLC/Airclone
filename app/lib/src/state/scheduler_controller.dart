import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_controller.dart';
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
      svc.transferAdvancedRaw(
        srcFs: t.srcFs,
        dstFs: t.dstFs,
        srcLabel: t.srcLabel,
        dstLabel: t.dstLabel,
        options: t.options,
      );
    }
    // Publish the tick (re-times UI labels) and clear any prior skip warning —
    // the engine is back, so due tasks just ran.
    state = SchedulerStatus(tickedAt: now);
  }
}

final schedulerProvider =
    NotifierProvider<SchedulerController, SchedulerStatus>(
      SchedulerController.new,
    );
