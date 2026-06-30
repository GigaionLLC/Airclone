import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isDue — interval', () {
    const s = TaskSchedule(kind: ScheduleKind.interval, intervalMinutes: 60);
    final now = DateTime(2026, 6, 29, 12, 0);
    test('fires immediately when never run', () {
      expect(isDue(s, now: now, lastRun: null), isTrue);
    });
    test('not due before the interval elapses', () {
      expect(
        isDue(s, now: now, lastRun: now.subtract(const Duration(minutes: 30))),
        isFalse,
      );
    });
    test('due once the interval has elapsed', () {
      expect(
        isDue(s, now: now, lastRun: now.subtract(const Duration(minutes: 90))),
        isTrue,
      );
    });
  });

  group('isDue — daily', () {
    const s = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);
    test('not due before the slot', () {
      expect(
        isDue(s, now: DateTime(2026, 6, 29, 8, 59), lastRun: null),
        isFalse,
      );
    });
    test('due after the slot when not yet run today (catch-up)', () {
      // App opened at 14:00; 09:00 slot was missed → fire once.
      final now = DateTime(2026, 6, 29, 14, 0);
      expect(isDue(s, now: now, lastRun: DateTime(2026, 6, 28, 9, 0)), isTrue);
    });
    test('not due again once run past today\'s slot', () {
      final now = DateTime(2026, 6, 29, 14, 0);
      expect(isDue(s, now: now, lastRun: DateTime(2026, 6, 29, 9, 0)), isFalse);
    });
  });

  group('isDue — weekly', () {
    // Monday = 1. 2026-06-29 is a Monday.
    const s = TaskSchedule(
      kind: ScheduleKind.weekly,
      hour: 18,
      minute: 30,
      weekdays: [1, 3],
    );
    test('not due on a non-selected weekday', () {
      // 2026-06-30 is Tuesday (2), not selected.
      expect(
        isDue(s, now: DateTime(2026, 6, 30, 19, 0), lastRun: null),
        isFalse,
      );
    });
    test('due on a selected weekday after the slot', () {
      expect(
        isDue(s, now: DateTime(2026, 6, 29, 19, 0), lastRun: null),
        isTrue,
      );
    });
    test('not due before the slot on a selected day', () {
      expect(
        isDue(s, now: DateTime(2026, 6, 29, 18, 0), lastRun: null),
        isFalse,
      );
    });
  });

  group('nextRun', () {
    test('interval = lastRun + interval', () {
      const s = TaskSchedule(kind: ScheduleKind.interval, intervalMinutes: 60);
      final last = DateTime(2026, 6, 29, 12, 0);
      expect(
        nextRun(s, from: DateTime(2026, 6, 29, 12, 10), lastRun: last),
        DateTime(2026, 6, 29, 13, 0),
      );
    });
    test('daily rolls to tomorrow when today\'s slot passed', () {
      const s = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);
      expect(
        nextRun(s, from: DateTime(2026, 6, 29, 10, 0), lastRun: null),
        DateTime(2026, 6, 30, 9, 0),
      );
    });
    test('weekly finds the next selected weekday', () {
      const s = TaskSchedule(
        kind: ScheduleKind.weekly,
        hour: 8,
        minute: 0,
        weekdays: [3],
      );
      // From Monday 2026-06-29 → next Wednesday is 2026-07-01.
      expect(
        nextRun(s, from: DateTime(2026, 6, 29, 12, 0), lastRun: null),
        DateTime(2026, 7, 1, 8, 0),
      );
    });
  });

  test('describe is human-readable', () {
    expect(
      const TaskSchedule(
        kind: ScheduleKind.interval,
        intervalMinutes: 360,
      ).describe(),
      'Every 6 hours',
    );
    expect(
      const TaskSchedule(
        kind: ScheduleKind.daily,
        hour: 9,
        minute: 5,
      ).describe(),
      'Daily at 09:05',
    );
    expect(
      const TaskSchedule(
        kind: ScheduleKind.weekly,
        hour: 18,
        minute: 30,
        weekdays: [1, 3],
      ).describe(),
      'Mon, Wed at 18:30',
    );
  });

  test('TaskSchedule JSON round-trips', () {
    const s = TaskSchedule(
      kind: ScheduleKind.weekly,
      hour: 7,
      minute: 15,
      weekdays: [2, 4, 6],
    );
    expect(TaskSchedule.fromJson(s.toJson()), s);
  });

  group('TransferTask back-compat', () {
    TransferTask base() => const TransferTask(
      id: '1',
      name: 'T',
      srcFs: 'a:',
      srcLabel: 'a:',
      dstFs: 'b:',
      dstLabel: 'b:',
      options: TransferOptions(),
    );

    test('old JSON without schedule loads with null schedule/lastRun', () {
      final old = base().toJson()
        ..remove('schedule')
        ..remove('lastRun');
      final t = TransferTask.fromJson(old);
      expect(t.schedule, isNull);
      expect(t.lastRun, isNull);
    });

    test('toJson omits schedule/lastRun when null', () {
      final j = base().toJson();
      expect(j.containsKey('schedule'), isFalse);
      expect(j.containsKey('lastRun'), isFalse);
    });

    test('copyWith can set then clear the schedule', () {
      const s = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);
      final withSched = base().copyWith(
        schedule: s,
        lastRun: DateTime(2026, 6, 29),
      );
      expect(withSched.schedule, s);
      expect(withSched.lastRun, DateTime(2026, 6, 29));
      // round-trip through JSON keeps it
      final round = TransferTask.fromJson(withSched.toJson());
      expect(round.schedule, s);
      // clear
      final cleared = withSched.copyWith(schedule: null);
      expect(cleared.schedule, isNull);
      // name-only copyWith keeps schedule
      final renamed = withSched.copyWith(name: 'X');
      expect(renamed.schedule, s);
      expect(renamed.name, 'X');
    });
  });
}
