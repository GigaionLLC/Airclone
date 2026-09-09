import 'dart:io' show ProcessResult;

import 'package:airclone/src/state/scheduler_controller.dart';
import 'package:airclone/src/state/scheduler_pause.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:airclone/src/state/windows_task_scheduler.dart';
import 'package:airclone/src/ui/tasks_panel.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The circuit breaker is only as good as the way out of it. These cover the
/// two halves a user actually meets: the banner that says the scheduler has
/// stopped, and the number it stopped at.
class _FixedTasks extends TasksController {
  _FixedTasks(this._initial);
  final List<TransferTask> _initial;
  @override
  List<TransferTask> build() => _initial;
  @override
  void update(TransferTask t) {
    saved = t;
    super.update(t);
  }

  /// The last task written back, so a test can assert what Save persisted.
  TransferTask? saved;
}

/// The real controller arms a 30 s periodic timer in `build()`, which the test
/// binding rejects as a pending timer. The banner reads nothing from it.
class _NoTimerScheduler extends SchedulerController {
  @override
  SchedulerStatus build() => const SchedulerStatus();
}

class _AlreadyPaused extends SchedulerPaused {
  @override
  SchedulerPause? build() => SchedulerPause(
    at: DateTime(2026, 9, 9, 3, 15),
    taskId: '1',
    taskName: 'photos: -> backup:',
    reason: 'too many deletes: max-delete limit of 100 reached',
  );
}

/// `schtasks` never actually runs in a test: /Query reports "not registered"
/// (exit 1) and everything else succeeds.
Future<ProcessResult> _fakeSchtasks(String exe, List<String> args) async =>
    ProcessResult(0, args.contains('/Query') ? 1 : 0, '', '');

TransferTask _task({
  TransferMode mode = TransferMode.sync,
  int? cap,
  TaskSchedule? schedule,
}) => TransferTask(
  id: '1',
  name: 'photos to backup',
  srcFs: 'photos:',
  srcLabel: 'photos:',
  dstFs: 'backup:',
  dstLabel: 'backup:',
  options: TransferOptions(mode: mode, maxDeleteFiles: cap),
  schedule: schedule,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget Function(BuildContext, WidgetRef) body, {
    List<Override> overrides = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        windowsTaskSchedulerProvider.overrideWithValue(
          WindowsTaskScheduler(runner: _fakeSchtasks),
        ),
        schedulerProvider.overrideWith(_NoTimerScheduler.new),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(builder: (ctx, ref, _) => body(ctx, ref)),
          ),
        ),
      ),
    );
    return container;
  }

  group('paused banner', () {
    testWidgets('names the task, quotes the engine, and Resume clears it', (
      tester,
    ) async {
      final tasks = _FixedTasks([
        _task(
          schedule: const TaskSchedule(
            kind: ScheduleKind.interval,
            intervalMinutes: 60,
          ),
        ),
      ]);
      final container = await pump(
        tester,
        (ctx, ref) => TextButton(
          onPressed: () => showTasksDialog(ctx),
          child: const Text('open'),
        ),
        overrides: [
          tasksProvider.overrideWith(() => tasks),
          schedulerPausedProvider.overrideWith(_AlreadyPaused.new),
        ],
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Scheduling is paused'), findsOneWidget);
      // The task that tripped it and the engine's own words: a user deciding
      // whether resuming is safe needs both.
      expect(find.textContaining('photos: -> backup:'), findsOneWidget);
      expect(find.textContaining('max-delete limit of 100'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(container.read(schedulerPausedProvider), isNull);
      expect(find.text('Scheduling is paused'), findsNothing);
    });

    testWidgets('is absent while the scheduler is running', (tester) async {
      await pump(
        tester,
        (ctx, ref) => TextButton(
          onPressed: () => showTasksDialog(ctx),
          child: const Text('open'),
        ),
        overrides: [
          tasksProvider.overrideWith(() => _FixedTasks([_task()])),
        ],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Scheduling is paused'), findsNothing);
    });
  });

  group('schedule editor delete cap', () {
    Future<_FixedTasks> open(
      WidgetTester tester,
      TransferTask t, {
      bool scheduleOn = false,
    }) async {
      final tasks = _FixedTasks([t]);
      await pump(
        tester,
        (ctx, ref) => TextButton(
          onPressed: () => showScheduleDialog(ctx, ref, t),
          child: const Text('open'),
        ),
        overrides: [tasksProvider.overrideWith(() => tasks)],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (scheduleOn) {
        await tester.tap(find.text('Run automatically on a schedule'));
        await tester.pumpAndSettle();
      }
      return tasks;
    }

    testWidgets('seeds an uncapped Sync with the default, visibly', (
      tester,
    ) async {
      await open(tester, _task(), scheduleOn: true);
      expect(
        find.textContaining('Stop if a run would delete more than'),
        findsOneWidget,
      );
      // The number must be ON SCREEN. Applying it only at run time would leave
      // the user with a scheduler that can stop for a reason they never saw.
      expect(
        find.widgetWithText(TextField, '$kDefaultScheduledDeleteCap'),
        findsOneWidget,
      );
    });

    testWidgets('shows a cap the user already chose rather than the default', (
      tester,
    ) async {
      await open(tester, _task(cap: 7), scheduleOn: true);
      expect(find.widgetWithText(TextField, '7'), findsOneWidget);
    });

    testWidgets('is absent for Copy, which never deletes at the destination', (
      tester,
    ) async {
      await open(tester, _task(mode: TransferMode.copy), scheduleOn: true);
      expect(
        find.textContaining('Stop if a run would delete more than'),
        findsNothing,
      );
    });

    testWidgets('Save persists the edited cap onto the task', (tester) async {
      final tasks = await open(tester, _task(), scheduleOn: true);
      await tester.enterText(
        find.widgetWithText(TextField, '$kDefaultScheduledDeleteCap'),
        '25',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(tasks.saved?.schedule, isNotNull);
      expect(tasks.saved?.options.maxDeleteFiles, 25);
    });

    testWidgets('an emptied field saves the default, never "no cap"', (
      tester,
    ) async {
      final tasks = await open(tester, _task(cap: 7), scheduleOn: true);
      await tester.enterText(find.widgetWithText(TextField, '7'), '');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Blanking the field must not read as "unlimited" — that is the exact
      // state this feature exists to make unreachable for a repeating Sync.
      expect(tasks.saved?.options.maxDeleteFiles, kDefaultScheduledDeleteCap);
    });
  });
}
