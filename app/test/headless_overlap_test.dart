import 'dart:io';

import 'package:airclone/src/headless/headless_runner.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/task_run_gate.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// #55 on the path nobody watches: a background wake (`--run-due`,
/// `--run-task`, WorkManager, BGProcessingTask) that finds the task already
/// running somewhere else must not start a second copy beside it.
class _FixedTasks extends TasksController {
  _FixedTasks(this._initial);
  final List<TransferTask> _initial;
  @override
  List<TransferTask> build() => _initial;
}

/// No engine at all: if the skip did not happen, the dispatch would fail with
/// "Engine not ready" and the summary would say FAIL, not SKIP.
class _NoEngine extends EngineController {
  @override
  EngineUi build() => const EngineUi(phase: EnginePhase.ready);
}

const _task = TransferTask(
  id: 'nightly',
  name: 'photos',
  srcFs: 'a:',
  srcLabel: 'a:',
  dstFs: 'b:',
  dstLabel: 'b:',
  options: TransferOptions(mode: TransferMode.copy),
  schedule: TaskSchedule(kind: ScheduleKind.interval, intervalMinutes: 60),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('airclone-headless-'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a task already running elsewhere is skipped, not run twice', () async {
    // The other holder: the app, or another wake, mid-run.
    final other = TaskRunLocks(baseDir: () async => tmp);
    expect(await other.tryAcquire(_task.id), isTrue);
    addTearDown(() => other.release(_task.id));

    final c = ProviderContainer(
      overrides: [
        engineControllerProvider.overrideWith(_NoEngine.new),
        tasksProvider.overrideWith(() => _FixedTasks([_task])),
        taskRunLocksProvider.overrideWithValue(
          TaskRunLocks(baseDir: () async => tmp),
        ),
      ],
    );
    addTearDown(c.dispose);

    final summary = <String>[];
    final code = await runSelected(
      c,
      const HeadlessRequest(
        runDue: true,
        taskId: null,
        timeout: Duration(minutes: 5),
      ),
      [_task],
      summary,
    );

    // A clean exit: nothing failed, so Task Scheduler shows no red result.
    expect(code, kExitOk);
    expect(summary, [
      '[SKIP] photos [nightly] — already running in another Airclone process',
    ]);
    final after = c.read(tasksProvider).single;
    // The slot is not consumed: it runs once the other run ends.
    expect(after.lastRun, isNull);
    expect(after.history, isEmpty);
  });

  test('a skip summary line is a SKIP, not an OK or a FAIL', () {
    const r = HeadlessTaskResult.skipped(taskId: 'x', name: 'n');
    expect(r.ok, isTrue);
    expect(r.summaryLine, startsWith('[SKIP] n [x]'));
  });
}
