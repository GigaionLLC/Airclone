import 'dart:convert';

import 'package:airclone/src/headless/headless_runner.dart';
import 'package:airclone/src/state/scheduler_pause.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The circuit breaker, on the path nobody is watching.
///
/// A tripped breaker stops the in-app tick. For a long time it stopped nothing
/// else — a Windows Scheduled Task or an Android WorkManager wake would happily
/// run the very task that tripped it. That makes "pauses the entire scheduler"
/// false in exactly the situation the pause exists for: the one where a human
/// has not looked yet, and the environment that caused a mass deletion is still
/// broken.
///
/// This drives the real headless entry point against real SharedPreferences,
/// because the interesting part is not the `if` — it is whether the paused state
/// has HYDRATED by the time that `if` runs. `SchedulerPaused.build()` returns
/// null and loads asynchronously, so a check that runs too early reads "not
/// paused" and the guard silently does nothing.
Map<String, dynamic> _taskJson(String id) => {
  'id': id,
  'name': id,
  'srcFs': 'a:',
  'srcLabel': 'a:',
  'dstFs': 'b:',
  'dstLabel': 'b:',
  'options': const TransferOptions(mode: TransferMode.copy).toJson(),
  'schedule': const TaskSchedule(
    kind: ScheduleKind.interval,
    intervalMinutes: 60,
  ).toJson(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A PAUSED SCHEDULER STOPS A HEADLESS RUN, and says why', () async {
    final pause = SchedulerPause(
      at: DateTime(2026, 9, 9, 3, 15),
      taskId: 'nightly',
      taskName: 'photos: -> backup:',
      reason: 'too many deletes: max-delete limit reached',
    );
    SharedPreferences.setMockInitialValues({
      'transfer_tasks': jsonEncode([_taskJson('nightly')]),
      'scheduler_paused': jsonEncode(pause.toJson()),
    });

    final out = await runHeadlessInProcess(['--run-due']);

    // Clean exit: the run was refused, not failed. A non-zero code would make
    // Task Scheduler show a red Last Run Result for a deliberate, correct
    // decision, and train the user to ignore it.
    expect(out.code, kExitOk);

    final said = out.summary.join('\n');
    expect(
      said,
      contains('paused'),
      reason: 'a silent refusal is the failure this feature exists to prevent',
    );
    // Which task, and when — the two things someone needs to decide whether it
    // is safe to resume.
    expect(said, contains('photos: -> backup:'));
    expect(said, contains('2026-09-09'));
  });

  test('with no pause recorded, it gets past the breaker', () async {
    // The counterpart, so the test above cannot pass merely because the
    // headless path refuses everything.
    SharedPreferences.setMockInitialValues({
      'transfer_tasks': jsonEncode([_taskJson('nightly')]),
    });

    final out = await runHeadlessInProcess(['--run-due']);

    // Only the property that matters: the breaker did not stop it. What
    // happens AFTER the breaker (no engine in a test, so it gets no further)
    // is a different mechanism with its own tests, and asserting an exit code
    // here would be asserting a guess about internals — which is exactly what
    // the first version of this line did, wrongly.
    expect(out.summary.join('\n'), isNot(contains('paused')));
  });

  test('an unreadable pause record does not stop everything forever', () async {
    // A pause we cannot parse must not become a permanent, unexplainable halt:
    // "nothing backs up and nobody knows why" is worse than one more run.
    SharedPreferences.setMockInitialValues({
      'transfer_tasks': jsonEncode([_taskJson('nightly')]),
      'scheduler_paused': 'not json at all',
    });

    final out = await runHeadlessInProcess(['--run-due']);
    expect(out.summary.join('\n'), isNot(contains('paused')));
  });
}
