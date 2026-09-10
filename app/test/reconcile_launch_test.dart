import 'dart:convert';
import 'dart:io' show Platform, ProcessResult;

import 'package:airclone/src/state/registration_policy.dart';
import 'package:airclone/src/state/scheduler_registration.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:airclone/src/state/windows_task_scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The launch path, end to end, through the REAL hydration.
///
/// The pure seeding is tested next door. What this covers is the thing that
/// actually protects an upgrading user: that a reconcile at launch **seeds
/// first**, and that it waits for the saved tasks to load before deciding
/// anything. Acting on the empty list `build()` returns would read as "nothing
/// is scheduled" and unregister every task the user has.
///
/// A deliberate choice not to use a test double for [TasksController]: a double
/// that overrides `build()` skips `_load()`, which is exactly the code being
/// tested here.
const _daily = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);

Map<String, dynamic> _taskJson(String id, {bool runWhileClosed = false}) => {
  'id': id,
  'name': id,
  'srcFs': 'a:',
  'srcLabel': 'a:',
  'dstFs': 'b:',
  'dstLabel': 'b:',
  'options': const TransferOptions(mode: TransferMode.copy).toJson(),
  'schedule': _daily.toJson(),
  if (runWhileClosed) 'runWhileClosed': true,
};

class _Fake {
  _Fake({this.registered = const <String>{}});
  final Set<String> registered;
  final calls = <List<String>>[];

  Future<ProcessResult> run(String exe, List<String> args) async {
    calls.add(args);
    if (args.first == '/Query') {
      final csv = registered
          .map((n) => '"\\Airclone\\$n","","Ready"')
          .join('\n');
      return ProcessResult(0, 0, csv, '');
    }
    return ProcessResult(0, 0, '', '');
  }

  /// Leaf names, so assertions read the way the folder does.
  static const _prefix = r'Airclone\';
  String _leaf(String tn) =>
      tn.startsWith(_prefix) ? tn.substring(_prefix.length) : tn;

  List<String> get deleted => [
    for (final c in calls)
      if (c.first == '/Delete') _leaf(c[c.indexOf('/TN') + 1]),
  ];
  List<String> get created => [
    for (final c in calls)
      if (c.first == '/Create') _leaf(c[c.indexOf('/TN') + 1]),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final onWindows = Platform.isWindows;

  Future<void> run({
    required List<Map<String, dynamic>> saved,
    required _Fake fake,
    bool seed = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'transfer_tasks': jsonEncode(saved),
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await reconcileRegistrations(
      notifier: c.read(tasksProvider.notifier),
      readTasks: () => c.read(tasksProvider),
      os: WindowsTaskScheduler(runner: fake.run),
      pollMinutes: 15,
      seed: seed,
    );
  }

  test('AN UPGRADE KEEPS ITS REGISTRATIONS', () async {
    // The task was saved before `runWhileClosed` existed, so its JSON has no
    // key for it and it loads as false — while a working registration sits in
    // Task Scheduler. Without seeding, this reconcile deletes it.
    final fake = _Fake(registered: {'nightly'});
    await run(saved: [_taskJson('nightly')], fake: fake, seed: true);

    expect(
      fake.deleted,
      isEmpty,
      reason: 'upgrading must not silently unregister a working schedule',
    );
  }, skip: onWindows ? false : 'schtasks is Windows-only');

  test('without seeding, that same reconcile deletes it', () async {
    // The counterpart, kept deliberately: it demonstrates the trap rather than
    // asserting the fix, so the previous test cannot pass for the wrong reason.
    final fake = _Fake(registered: {'nightly'});
    await run(saved: [_taskJson('nightly')], fake: fake, seed: false);
    expect(fake.deleted, ['nightly']);
  }, skip: onWindows ? false : 'schtasks is Windows-only');

  test('it waits for the saved tasks to load first', () async {
    // `build()` returns an empty list and fills it in asynchronously. Acting on
    // that empty list reads as "nothing is scheduled" and clears the folder.
    final fake = _Fake(registered: {'a', 'b', kDueRunnerTaskName});
    await run(
      saved: [
        _taskJson('a', runWhileClosed: true),
        _taskJson('b', runWhileClosed: true),
      ],
      fake: fake,
    );
    expect(fake.deleted, [
      kDueRunnerTaskName,
    ], reason: 'only the poller is stale — both daily tasks are still wanted');
  }, skip: onWindows ? false : 'schtasks is Windows-only');

  test('a task the user really did opt out of is still unregistered', () async {
    // Seeding only turns the flag ON, so an opt-out the user made deliberately
    // survives — the registration for it is stale and goes.
    final fake = _Fake(registered: {'gone'});
    await run(saved: const [], fake: fake, seed: true);
    expect(fake.deleted, ['gone']);
  }, skip: onWindows ? false : 'schtasks is Windows-only');

  test('nothing saved and nothing registered does nothing at all', () async {
    final fake = _Fake();
    await run(saved: const [], fake: fake, seed: true);
    expect(fake.created, isEmpty);
    expect(fake.deleted, isEmpty);
  }, skip: onWindows ? false : 'schtasks is Windows-only');
}
