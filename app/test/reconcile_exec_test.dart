import 'dart:io' show Platform, ProcessResult;

import 'package:airclone/src/state/registration_policy.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:airclone/src/state/windows_task_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// The executor behind the hybrid: what `schtasks` calls does a reconcile
/// actually make?
///
/// The plan is tested purely elsewhere. What these pin is the part that touches
/// a real machine — that deletes happen before creates, that an entry which is
/// already correct is LEFT ALONE, and that the definition written under each
/// name is the right one of the two shapes.
const _interval = TaskSchedule(
  kind: ScheduleKind.interval,
  intervalMinutes: 120,
);
const _daily = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);

TransferTask _task({
  required String id,
  TaskSchedule? schedule,
  bool runWhileClosed = true,
}) => TransferTask(
  id: id,
  name: id,
  srcFs: 'a:',
  srcLabel: 'a:',
  dstFs: 'b:',
  dstLabel: 'b:',
  options: const TransferOptions(mode: TransferMode.copy),
  schedule: schedule,
  runWhileClosed: runWhileClosed,
);

/// Records every schtasks invocation and answers /Query from a fixed folder.
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

  /// The names passed to /Create, in order.
  List<String> get created => [
    for (final c in calls)
      if (c.first == '/Create') c[c.indexOf('/TN') + 1],
  ];

  /// The names passed to /Delete, in order.
  List<String> get deleted => [
    for (final c in calls)
      if (c.first == '/Delete') c[c.indexOf('/TN') + 1],
  ];

  /// Indexes into [calls], so ordering between verbs can be asserted.
  int indexOf(String verb) => calls.indexWhere((c) => c.first == verb);
}

void main() {
  // schtasks does not exist off Windows and every public method no-ops there,
  // so these can only assert anything on a Windows host. Skipped elsewhere
  // rather than silently passing.
  final onWindows = Platform.isWindows;

  group('reconcile', () {
    test('an interval schedule creates the SHARED job, not a private one', () {
      // The bug this whole change fixes: the editor told the user an interval
      // schedule joins "Run due tasks" while register() quietly made it a
      // private per-task entry.
      final f = _Fake();
      return WindowsTaskScheduler(runner: f.run)
          .reconcile(
            tasks: [_task(id: 'every2h', schedule: _interval)],
            pollMinutes: 15,
          )
          .then((r) {
            expect(r.ok, isTrue);
            expect(f.created, [r'Airclone\Run due tasks']);
            expect(
              f.created,
              isNot(contains(r'Airclone\every2h')),
              reason: 'an interval schedule must not get its own entry',
            );
          });
    }, skip: onWindows ? false : 'schtasks is Windows-only');

    test('a daily schedule creates its own exact entry', () async {
      final f = _Fake();
      final r = await WindowsTaskScheduler(runner: f.run).reconcile(
        tasks: [_task(id: 'nightly', schedule: _daily)],
        pollMinutes: 15,
      );
      expect(r.ok, isTrue);
      expect(f.created, [r'Airclone\nightly']);
    }, skip: onWindows ? false : 'schtasks is Windows-only');

    test(
      'THE MIGRATION: the old per-task entry is deleted, poller created',
      () async {
        final f = _Fake(registered: {'every2h'});
        final r = await WindowsTaskScheduler(runner: f.run).reconcile(
          tasks: [_task(id: 'every2h', schedule: _interval)],
          pollMinutes: 15,
        );
        expect(r.deleted, ['every2h']);
        expect(r.created, [kDueRunnerTaskName]);
        // Deletes before creates, so a shape change never leaves both registered.
        expect(
          f.indexOf('/Delete') < f.indexOf('/Create'),
          isTrue,
          reason: 'both forms must never be registered at once',
        );
      },
      skip: onWindows ? false : 'schtasks is Windows-only',
    );

    test('an already-correct set touches nothing', () async {
      // `/Create /F` REPLACES a task, which resets its trigger state — and a
      // repeating trigger with a past boundary then fires straight away. If
      // reconcile rewrote everything, opening the app would start a run.
      final f = _Fake(registered: {'nightly', kDueRunnerTaskName});
      final r = await WindowsTaskScheduler(runner: f.run).reconcile(
        tasks: [
          _task(id: 'nightly', schedule: _daily),
          _task(id: 'every2h', schedule: _interval),
        ],
        pollMinutes: 15,
      );
      expect(r.created, isEmpty);
      expect(r.deleted, isEmpty);
      expect(f.created, isEmpty);
      expect(f.deleted, isEmpty);
    }, skip: onWindows ? false : 'schtasks is Windows-only');

    test(
      'refresh rewrites a definition under a name that already exists',
      () async {
        // Editing a daily schedule's time changes nothing about which entries
        // exist, so only an explicit refresh can carry the new definition.
        final f = _Fake(registered: {'nightly'});
        await WindowsTaskScheduler(runner: f.run).reconcile(
          tasks: [_task(id: 'nightly', schedule: _daily)],
          pollMinutes: 15,
          refresh: {'nightly'},
        );
        expect(f.created, [r'Airclone\nightly']);
      },
      skip: onWindows ? false : 'schtasks is Windows-only',
    );

    test('refresh cannot resurrect something that is not wanted', () async {
      // Otherwise saving a task with the checkbox turned OFF would re-register
      // it, which is the opposite of what the user just asked for.
      final f = _Fake(registered: {'nightly'});
      final r = await WindowsTaskScheduler(runner: f.run).reconcile(
        tasks: [_task(id: 'nightly', schedule: _daily, runWhileClosed: false)],
        pollMinutes: 15,
        refresh: {'nightly'},
      );
      expect(r.deleted, ['nightly']);
      expect(f.created, isEmpty);
    }, skip: onWindows ? false : 'schtasks is Windows-only');

    test('opting out entirely clears the folder', () async {
      final f = _Fake(registered: {'nightly', kDueRunnerTaskName});
      final r = await WindowsTaskScheduler(runner: f.run).reconcile(
        tasks: [
          _task(id: 'nightly', schedule: _daily, runWhileClosed: false),
          _task(id: 'every2h', schedule: _interval, runWhileClosed: false),
        ],
        pollMinutes: 15,
      );
      expect(r.deleted, [kDueRunnerTaskName, 'nightly']);
      expect(r.created, isEmpty);
    }, skip: onWindows ? false : 'schtasks is Windows-only');

    test('the cadence reaches the definition that gets written', () async {
      final f = _Fake();
      await WindowsTaskScheduler(runner: f.run).reconcile(
        tasks: [_task(id: 'i', schedule: _interval)],
        pollMinutes: 30,
      );
      // The XML goes to a temp file, so what is asserted here is that a create
      // happened for the shared job; the cadence -> XML mapping is pinned in
      // due_runner_task_test.dart.
      expect(f.created, [r'Airclone\Run due tasks']);
    }, skip: onWindows ? false : 'schtasks is Windows-only');

    test('a task with no schedule is never registered', () async {
      final f = _Fake();
      final r = await WindowsTaskScheduler(
        runner: f.run,
      ).reconcile(tasks: [_task(id: 'x')], pollMinutes: 15);
      expect(r.created, isEmpty);
      expect(f.calls.where((c) => c.first == '/Create'), isEmpty);
    }, skip: onWindows ? false : 'schtasks is Windows-only');
  });

  group('listRegistered', () {
    test('a failed query yields an empty set, so nothing is deleted', () async {
      // A reconcile that cannot see what is registered must create what it
      // needs and delete NOTHING — guessing would take out a working schedule.
      Future<ProcessResult> broken(String e, List<String> a) async =>
          ProcessResult(0, 1, '', 'ERROR: access denied');
      final s = WindowsTaskScheduler(runner: broken);
      expect(await s.listRegistered(), isEmpty);
      final r = await s.reconcile(
        tasks: [_task(id: 'nightly', schedule: _daily)],
        pollMinutes: 15,
      );
      expect(r.deleted, isEmpty);
    }, skip: onWindows ? false : 'schtasks is Windows-only');
  });
}
