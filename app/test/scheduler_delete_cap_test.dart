import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/scheduler_controller.dart';
import 'package:airclone/src/state/scheduler_pause.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same in-memory task double the tick tests use — the scheduler must be
/// drivable without SharedPreferences hydration racing the assertion.
class _FixedTasks extends TasksController {
  _FixedTasks(this._initial);
  final List<TransferTask> _initial;
  @override
  List<TransferTask> build() => _initial;
}

/// A breaker that is already tripped when the container is first read, so a
/// tick can be driven against it without going through the async pause path.
class _AlreadyPaused extends SchedulerPaused {
  @override
  SchedulerPause? build() => SchedulerPause(
    at: DateTime(2026, 9, 9, 3),
    taskId: '1',
    taskName: 'a: -> b:',
    reason: 'too many deletes: max-delete limit reached',
  );
}

const _interval = TaskSchedule(
  kind: ScheduleKind.interval,
  intervalMinutes: 60,
);

TransferTask _task({String id = '1'}) => TransferTask(
  id: id,
  name: id,
  srcFs: 'a:',
  srcLabel: 'a:',
  dstFs: 'b:',
  dstLabel: 'b:',
  options: const TransferOptions(mode: TransferMode.sync),
  schedule: _interval,
  lastRun: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('withScheduledDeleteCap', () {
    test('caps an uncapped repeating one-way Sync', () {
      const o = TransferOptions(mode: TransferMode.sync);
      expect(o.maxDeleteFiles, isNull);
      expect(
        withScheduledDeleteCap(o).maxDeleteFiles,
        kDefaultScheduledDeleteCap,
      );
    });

    test('never overrides a cap the user chose — including a deliberate 0', () {
      const chosen = TransferOptions(
        mode: TransferMode.sync,
        maxDeleteFiles: 5,
      );
      expect(withScheduledDeleteCap(chosen).maxDeleteFiles, 5);
      // 0 means "abort on the first delete" and is a legitimate choice, not an
      // absent one. `?? default` would silently replace it; `== null` must not.
      const zero = TransferOptions(mode: TransferMode.sync, maxDeleteFiles: 0);
      expect(withScheduledDeleteCap(zero).maxDeleteFiles, 0);
    });

    test('leaves copy, move and bisync alone', () {
      // copy/move never delete at the destination, so a cap is meaningless; a
      // bisync cap is a PERCENT (maxDeletePercent), a different field entirely,
      // and setting the count one would be silently ignored.
      for (final m in [
        TransferMode.copy,
        TransferMode.move,
        TransferMode.bisync,
      ]) {
        expect(
          withScheduledDeleteCap(TransferOptions(mode: m)).maxDeleteFiles,
          isNull,
          reason: '$m must not be given a file-count delete cap',
        );
      }
    });

    test('the cap actually reaches the engine as _config MaxDelete', () {
      // The helper returning the right object proves nothing on its own — what
      // matters is that rclone is told. This is the end of that wire.
      final capped = withScheduledDeleteCap(
        const TransferOptions(mode: TransferMode.sync),
      );
      final call = buildRcCall(capped, 'a:', 'b:');
      expect(call.method, 'sync/sync');
      expect(
        (call.params['_config'] as Map)['MaxDelete'],
        kDefaultScheduledDeleteCap,
      );
    });

    test('is idempotent — a second application changes nothing', () {
      final once = withScheduledDeleteCap(
        const TransferOptions(mode: TransferMode.sync),
      );
      expect(withScheduledDeleteCap(once).maxDeleteFiles, once.maxDeleteFiles);
    });
  });

  group('isDeleteCapError', () {
    test('matches the wordings rclone is known to use', () {
      for (final s in [
        'too many deletes',
        'Too many deletes (max-delete), aborting',
        'max delete limit reached',
        '--max-delete limit exceeded',
      ]) {
        expect(isDeleteCapError(s), isTrue, reason: s);
      }
    });

    test('does not fire on an unrelated failure, or on no failure at all', () {
      // A false trip stops every scheduled task until a human notices, so the
      // ordinary failures must not match.
      for (final s in [
        null,
        '',
        'directory not found',
        'couldn\'t connect: context deadline exceeded',
        'failed to delete: permission denied',
      ]) {
        expect(isDeleteCapError(s), isFalse, reason: s ?? 'null');
      }
    });
  });

  group('SchedulerPause', () {
    test('JSON round-trips, and a corrupt record reads as no pause', () {
      final p = SchedulerPause(
        at: DateTime(2026, 9, 9, 3, 15),
        taskId: '1',
        taskName: 'a: -> b:',
        reason: 'too many deletes',
      );
      final back = SchedulerPause.fromJson(p.toJson())!;
      expect(back.at, p.at);
      expect(back.taskId, '1');
      expect(back.taskName, 'a: -> b:');
      expect(back.reason, 'too many deletes');
      // An unreadable timestamp must not resurrect as a pause pinned to epoch —
      // it would stop the scheduler with no legible reason.
      expect(SchedulerPause.fromJson({'at': 'not a date'}), isNull);
    });

    test('pause keeps the FIRST reason; resume clears it', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(schedulerPausedProvider.notifier);
      await n.pause(
        SchedulerPause(
          at: DateTime(2026, 9, 9),
          taskId: '1',
          taskName: 'first',
          reason: 'too many deletes',
        ),
      );
      await n.pause(
        SchedulerPause(
          at: DateTime(2026, 9, 9, 1),
          taskId: '2',
          taskName: 'second',
          reason: 'something else',
        ),
      );
      expect(c.read(schedulerPausedProvider)!.taskName, 'first');
      await n.resume();
      expect(c.read(schedulerPausedProvider), isNull);
    });

    test('a pause survives a restart', () async {
      final first = ProviderContainer();
      await first
          .read(schedulerPausedProvider.notifier)
          .pause(
            SchedulerPause(
              at: DateTime(2026, 9, 9),
              taskId: '1',
              taskName: 'a: -> b:',
              reason: 'too many deletes',
            ),
          );
      first.dispose();

      // A pause that forgets itself on relaunch is not a pause: the next tick
      // after restart would run the very task that tripped it.
      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.read(schedulerPausedProvider);
      await Future<void>.delayed(Duration.zero);
      expect(second.read(schedulerPausedProvider)?.taskName, 'a: -> b:');
    });
  });

  group('SchedulerController.tick — circuit breaker', () {
    test('a tripped breaker dispatches nothing and records no tick', () {
      final container = ProviderContainer(
        overrides: [
          tasksProvider.overrideWith(() => _FixedTasks([_task()])),
          schedulerPausedProvider.overrideWith(_AlreadyPaused.new),
        ],
      );
      addTearDown(container.dispose);

      container.read(schedulerProvider.notifier).tick();

      final status = container.read(schedulerProvider);
      // Without the guard this same tick reaches the engine check and stamps
      // both fields (the task is due, the engine is unavailable) — which is what
      // makes these two assertions the regression.
      expect(status.tickedAt, isNull);
      expect(status.skippedWhileUnavailable, isNull);
      expect(container.read(jobsControllerProvider), isEmpty);
    });

    test('resuming lets the scheduler tick again', () async {
      final container = ProviderContainer(
        overrides: [
          tasksProvider.overrideWith(() => _FixedTasks([_task()])),
          schedulerPausedProvider.overrideWith(_AlreadyPaused.new),
        ],
      );
      addTearDown(container.dispose);

      container.read(schedulerProvider.notifier).tick();
      expect(container.read(schedulerProvider).tickedAt, isNull);

      await container.read(schedulerPausedProvider.notifier).resume();
      container.read(schedulerProvider.notifier).tick();
      expect(container.read(schedulerProvider).tickedAt, isNotNull);
    });
  });
}
