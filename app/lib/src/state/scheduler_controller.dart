import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_controller.dart';
import 'task_schedule.dart';
import 'tasks_controller.dart';
import 'transfer_options.dart';
import 'transfer_service.dart';

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
class SchedulerController extends Notifier<DateTime?> {
  Timer? _timer;

  @override
  DateTime? build() {
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void _tick() {
    // Skip until the engine is ready, or due tasks would spam failed jobs at
    // boot. Before tasks hydrate from disk the list is empty, so nothing fires.
    if (ref.read(engineControllerProvider).client == null) return;
    final now = DateTime.now();
    final tasks = ref.read(tasksProvider);
    for (final t in tasks) {
      final s = t.schedule;
      if (s == null) continue;
      // Never auto-run a bisync first --resync unattended (it's destructive) —
      // the baseline must be established manually once first.
      if (t.options.mode == TransferMode.bisync &&
          !t.options.baselineEstablished) {
        continue;
      }
      if (!isDue(s, now: now, lastRun: t.lastRun)) continue;
      // Stamp lastRun BEFORE the async kickoff so the next tick can't double-fire.
      ref.read(tasksProvider.notifier).update(t.copyWith(lastRun: now));
      ref
          .read(transferServiceProvider)
          .transferAdvancedRaw(
            srcFs: t.srcFs,
            dstFs: t.dstFs,
            srcLabel: t.srcLabel,
            dstLabel: t.dstLabel,
            options: t.options,
          );
    }
    state = now;
  }
}

final schedulerProvider = NotifierProvider<SchedulerController, DateTime?>(
  SchedulerController.new,
);
