import 'package:airclone/src/state/registration_policy.dart';
import 'package:airclone/src/state/scheduler_registration.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// The upgrade trap, and the thing that stops it.
///
/// `runWhileClosed` is new. It used to be inferred by asking Task Scheduler
/// whether `Airclone\<id>` existed — which stops working under the hybrid,
/// because an interval schedule now has no entry of its own to ask about. So
/// the intent moved onto the model, and every task saved before that moment
/// says false while a perfectly good registration sits in Task Scheduler.
///
/// A reconcile run against those tasks reads "nobody wants background runs" and
/// deletes every one of them. This is the seeding that runs first.
const _interval = TaskSchedule(
  kind: ScheduleKind.interval,
  intervalMinutes: 120,
);
const _daily = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);

TransferTask _task({
  required String id,
  TaskSchedule? schedule = _daily,
  bool runWhileClosed = false,
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

void main() {
  group('seedRunWhileClosed', () {
    test('a registered task is carried forward as opted in', () {
      // The whole point: this user set up a background schedule under the old
      // build, and must not lose it by upgrading.
      final out = seedRunWhileClosed([_task(id: 'nightly')], {'nightly'})!;
      expect(out.single.runWhileClosed, isTrue);
    });

    test('an OLD INTERVAL registration is carried forward too', () {
      // Its per-task entry is about to be replaced by the shared poller, but
      // the user's intent is the same and has to survive the swap.
      final out = seedRunWhileClosed(
        [_task(id: 'every2h', schedule: _interval)],
        {'every2h'},
      )!;
      expect(out.single.runWhileClosed, isTrue);
    });

    test('nothing registered changes nothing, and says so', () {
      // Returning null rather than an equal list keeps the common case from
      // rewriting the store on every launch.
      expect(seedRunWhileClosed([_task(id: 'a')], const {}), isNull);
    });

    test('it only ever turns the flag ON', () {
      // Inferring "they must not want this" from an absent registration would
      // undo a choice rather than recover one — and a failed listRegistered()
      // returns an empty set, which would then silently opt everyone out.
      final already = [_task(id: 'a', runWhileClosed: true)];
      expect(seedRunWhileClosed(already, const {}), isNull);
      final out = seedRunWhileClosed(already, {'a'});
      expect(out, isNull, reason: 'already true, so nothing changed');
    });

    test('the shared job is not a task id and seeds nobody', () {
      // "Run due tasks" appears in the folder alongside real ids; matching it
      // against a task would be a coincidence, never a fact.
      expect(
        seedRunWhileClosed([_task(id: 'a')], {kDueRunnerTaskName}),
        isNull,
      );
    });

    test('only the registered ones change; the rest are untouched', () {
      final out = seedRunWhileClosed(
        [_task(id: 'a'), _task(id: 'b'), _task(id: 'c', runWhileClosed: true)],
        {'a'},
      )!;
      expect(out.map((t) => t.runWhileClosed), [true, false, true]);
      // Everything else about the task survives the copy.
      expect(out.map((t) => t.id), ['a', 'b', 'c']);
      expect(out.first.schedule, isNotNull);
    });
  });

  group('TransferTask.runWhileClosed round-trip', () {
    test('old JSON with no key reads as OFF', () {
      // A task saved before this existed must not acquire a background
      // registration by being loaded.
      final t = TransferTask.fromJson({
        'id': 'x',
        'name': 'x',
        'srcFs': 'a:',
        'dstFs': 'b:',
        'options': const <String, dynamic>{},
      });
      expect(t.runWhileClosed, isFalse);
    });

    test(
      'false is omitted from JSON so old builds round-trip byte-identical',
      () {
        final t = _task(id: 'x');
        expect(t.toJson().containsKey('runWhileClosed'), isFalse);
      },
    );

    test('true survives a round trip', () {
      final t = _task(id: 'x', runWhileClosed: true);
      expect(TransferTask.fromJson(t.toJson()).runWhileClosed, isTrue);
    });

    test('copyWith carries it, and can change it', () {
      final on = _task(id: 'x').copyWith(runWhileClosed: true);
      expect(on.runWhileClosed, isTrue);
      expect(on.copyWith(name: 'renamed').runWhileClosed, isTrue);
      expect(on.copyWith(runWhileClosed: false).runWhileClosed, isFalse);
    });
  });
}
