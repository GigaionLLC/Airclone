import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/scheduler_controller.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixed in-memory task list so the scheduler can be driven deterministically
/// without SharedPreferences (mirrors bw_schedule/transfer_queue test doubles).
class _FixedTasks extends TasksController {
  _FixedTasks(this._initial);
  final List<TransferTask> _initial;
  @override
  List<TransferTask> build() => _initial;
}

const _interval = TaskSchedule(
  kind: ScheduleKind.interval,
  intervalMinutes: 60,
);

TransferTask _task({
  String id = '1',
  TaskSchedule? schedule = _interval,
  TransferMode mode = TransferMode.copy,
  bool baselineEstablished = false,
  DateTime? lastRun,
}) => TransferTask(
  id: id,
  name: id,
  srcFs: 'a:',
  srcLabel: 'a:',
  dstFs: 'b:',
  dstLabel: 'b:',
  options: TransferOptions(
    mode: mode,
    baselineEstablished: baselineEstablished,
  ),
  schedule: schedule,
  lastRun: lastRun,
);

void main() {
  group('dueTasks', () {
    // 2026-06-29 is a Monday; the interval schedule ignores weekday anyway.
    final now = DateTime(2026, 6, 29, 12, 0);

    test('skips a task without a schedule', () {
      expect(dueTasks([_task(schedule: null)], now), isEmpty);
    });

    test('includes a scheduled task that is due (never run)', () {
      expect(dueTasks([_task(lastRun: null)], now).map((t) => t.id), ['1']);
    });

    test('excludes a scheduled task whose interval has not elapsed', () {
      final t = _task(lastRun: now.subtract(const Duration(minutes: 30)));
      expect(dueTasks([t], now), isEmpty);
    });

    test(
      'skips an unbaselined two-way (bisync) task even when its slot is due',
      () {
        final t = _task(
          mode: TransferMode.bisync,
          baselineEstablished: false,
          lastRun: null,
        );
        expect(dueTasks([t], now), isEmpty);
      },
    );

    test('includes a baselined two-way (bisync) task when due', () {
      final t = _task(
        mode: TransferMode.bisync,
        baselineEstablished: true,
        lastRun: null,
      );
      expect(dueTasks([t], now).map((t) => t.id), ['1']);
    });

    test('returns only the due tasks from a mixed list, preserving order', () {
      final list = [
        _task(id: 'a', schedule: null), // no schedule
        _task(id: 'b', lastRun: null), // due
        _task(
          id: 'c',
          lastRun: now.subtract(const Duration(minutes: 10)),
        ), // not due yet
        _task(
          id: 'd',
          mode: TransferMode.bisync,
          baselineEstablished: false,
          lastRun: null,
        ), // bisync baseline not established → skipped
        _task(
          id: 'e',
          mode: TransferMode.bisync,
          baselineEstablished: true,
          lastRun: null,
        ), // due
      ];
      expect(dueTasks(list, now).map((t) => t.id), ['b', 'e']);
    });
  });

  group('manual run stamps lastRun (no scheduled double-run)', () {
    test('stamping a scheduled task on manual run advances the anchor + drops it '
        'from the next tick', () {
      final container = ProviderContainer(
        overrides: [
          tasksProvider.overrideWith(() => _FixedTasks([_task(lastRun: null)])),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(tasksProvider.notifier);
      final t = container.read(tasksProvider).single;
      // A due scheduled task run manually would otherwise still read as due to
      // the next 30s tick, firing a second (scheduled) run behind the manual
      // one. `_TaskRow._run` now stamps lastRun before dispatch on a scheduled
      // task; model that stamp through the real controller.
      expect(dueTasks([t], DateTime.now()), isNotEmpty);
      notifier.update(t.copyWith(lastRun: DateTime.now()));
      final after = container.read(tasksProvider).single;
      expect(after.lastRun, isNotNull);
      expect(dueTasks([after], DateTime.now()), isEmpty);
    });
  });

  group('double-fire guard', () {
    test(
      'stamping lastRun before dispatch stops the next tick re-running it',
      () {
        final now = DateTime(2026, 6, 29, 12, 0);
        final due = _task(lastRun: now.subtract(const Duration(minutes: 90)));
        // The first tick sees it as due.
        expect(dueTasks([due], now).single.id, '1');
        // The controller stamps lastRun = now BEFORE the async kickoff...
        final stamped = due.copyWith(lastRun: now);
        // ...so neither this instant nor the next 30 s tick fires it again.
        expect(dueTasks([stamped], now), isEmpty);
        expect(
          dueTasks([stamped], now.add(const Duration(seconds: 30))),
          isEmpty,
        );
      },
    );
  });

  group('SchedulerController.tick — engine unavailable', () {
    test(
      'records a due run skipped while the engine is locked (no dispatch)',
      () {
        // Default EngineController state is idle → client == null (locked/down).
        final container = ProviderContainer(
          overrides: [
            tasksProvider.overrideWith(
              () => _FixedTasks([_task(lastRun: null)]),
            ),
          ],
        );
        addTearDown(container.dispose);

        final ctrl = container.read(schedulerProvider.notifier);
        expect(
          container.read(schedulerProvider).skippedWhileUnavailable,
          isNull,
        );

        ctrl.tick();

        final status = container.read(schedulerProvider);
        expect(status.tickedAt, isNotNull);
        expect(status.skippedWhileUnavailable, isNotNull);
        // Nothing may be dispatched while the engine is unavailable.
        expect(container.read(jobsControllerProvider), isEmpty);
      },
    );

    test('a locked tick with nothing due raises no skip warning', () {
      // Just-run interval task → not due, so the lock isn't holding anything back.
      final container = ProviderContainer(
        overrides: [
          tasksProvider.overrideWith(
            () => _FixedTasks([_task(lastRun: DateTime.now())]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(schedulerProvider.notifier).tick();
      expect(container.read(schedulerProvider).skippedWhileUnavailable, isNull);
    });
  });
}
