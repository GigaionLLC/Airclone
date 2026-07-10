import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/windows_task_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-function coverage for [buildTaskXml] — the schedule→Task-Scheduler-XML
/// mapping. No `Process.run`: the string builder is deterministic (fixed start
/// boundary, no clock read) so we can assert the exact trigger/action/settings
/// shapes `schtasks /Create /XML` will consume.
void main() {
  const exe = r'C:\Program Files\Airclone\airclone.exe';

  group('buildTaskXml — interval', () {
    final xml = buildTaskXml(
      schedule: const TaskSchedule(
        kind: ScheduleKind.interval,
        intervalMinutes: 30,
      ),
      id: 'abc-1',
      exePath: exe,
    );

    test('maps to a repeating TimeTrigger with PT<minutes>M', () {
      expect(xml, contains('<TimeTrigger>'));
      expect(xml, contains('<Repetition>'));
      expect(xml, contains('<Interval>PT30M</Interval>'));
      // Indefinite repetition = no <Duration> element.
      expect(xml, isNot(contains('<Duration>')));
      // Not a calendar trigger.
      expect(xml, isNot(contains('<CalendarTrigger>')));
    });

    test('a non-round interval keeps its exact minute count', () {
      final x = buildTaskXml(
        schedule: const TaskSchedule(
          kind: ScheduleKind.interval,
          intervalMinutes: 45,
        ),
        id: 'i',
        exePath: exe,
      );
      expect(x, contains('<Interval>PT45M</Interval>'));
    });
  });

  group('buildTaskXml — daily', () {
    final xml = buildTaskXml(
      schedule: const TaskSchedule(
        kind: ScheduleKind.daily,
        hour: 9,
        minute: 5,
      ),
      id: 'd1',
      exePath: exe,
    );

    test('maps to ScheduleByDay at the zero-padded time', () {
      expect(xml, contains('<CalendarTrigger>'));
      expect(xml, contains('<ScheduleByDay><DaysInterval>1</DaysInterval>'));
      // hour:minute land in the StartBoundary's time-of-day, zero-padded.
      expect(xml, contains('T09:05:00</StartBoundary>'));
      expect(xml, isNot(contains('<TimeTrigger>')));
    });
  });

  group('buildTaskXml — weekly', () {
    final xml = buildTaskXml(
      // Deliberately unsorted to prove the builder sorts the DaysOfWeek.
      schedule: const TaskSchedule(
        kind: ScheduleKind.weekly,
        hour: 18,
        minute: 30,
        weekdays: [5, 1, 3], // Fri, Mon, Wed
      ),
      id: 'w1',
      exePath: exe,
    );

    test('maps to ScheduleByWeek with named DaysOfWeek', () {
      expect(xml, contains('<ScheduleByWeek>'));
      expect(xml, contains('<DaysOfWeek>'));
      expect(xml, contains('<Monday/>'));
      expect(xml, contains('<Wednesday/>'));
      expect(xml, contains('<Friday/>'));
      // Unselected days are absent.
      expect(xml, isNot(contains('<Tuesday/>')));
      expect(xml, isNot(contains('<Sunday/>')));
    });

    test('emits the selected days in Mon→Sun order regardless of input', () {
      final mon = xml.indexOf('<Monday/>');
      final wed = xml.indexOf('<Wednesday/>');
      final fri = xml.indexOf('<Friday/>');
      expect(mon, lessThan(wed));
      expect(wed, lessThan(fri));
    });

    test('carries the chosen time-of-day', () {
      expect(xml, contains('T18:30:00</StartBoundary>'));
    });
  });

  group('buildTaskXml — settings & action (common)', () {
    final xml = buildTaskXml(
      schedule: const TaskSchedule(kind: ScheduleKind.interval),
      id: 'task-42',
      exePath: exe,
    );

    test('StartWhenAvailable is set for missed-run catch-up', () {
      expect(xml, contains('<StartWhenAvailable>true</StartWhenAvailable>'));
    });

    test('the unattended-run settings are present', () {
      expect(
        xml,
        contains(
          '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>',
        ),
      );
      expect(
        xml,
        contains(
          '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>',
        ),
      );
      expect(xml, contains('<ExecutionTimeLimit>PT6H</ExecutionTimeLimit>'));
    });

    test('the action runs the exe with --run-task <id>', () {
      expect(xml, contains('<Command>$exe</Command>'));
      expect(xml, contains('<Arguments>--run-task task-42</Arguments>'));
    });

    test('declares the v1.2 task schema namespace', () {
      expect(xml, contains('<?xml version="1.0" encoding="UTF-16"?>'));
      expect(
        xml,
        contains(
          'xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"',
        ),
      );
    });
  });

  group('buildTaskXml — XML escaping', () {
    test('a path with spaces & ampersands is XML-escaped in Command', () {
      const messy = r'C:\Program Files\Air & Clone\airclone.exe';
      final xml = buildTaskXml(
        schedule: const TaskSchedule(kind: ScheduleKind.daily),
        id: 'e1',
        exePath: messy,
      );
      // The literal `&` is escaped; the raw form must not leak into the XML.
      expect(
        xml,
        contains(
          r'<Command>C:\Program Files\Air &amp; Clone\airclone.exe</Command>',
        ),
      );
      expect(xml, isNot(contains(r'Air & Clone')));
      // Spaces are legal in XML text and pass through unescaped.
      expect(xml, contains(r'Program Files'));
    });

    test('an id with XML metacharacters is escaped in BOTH args and description', () {
      // Ids are [0-9a-z-] today, but the escaping must be symmetric so a future
      // id source with & < > can't produce well-formed <Arguments> yet malformed
      // <Description> (which would break registration in a way the escaped path
      // masks).
      final xml = buildTaskXml(
        schedule: const TaskSchedule(kind: ScheduleKind.daily),
        id: 'a&b<c>d',
        exePath: exe,
      );
      // The raw metacharacters must not leak into the document anywhere.
      expect(xml, isNot(contains('a&b<c>d')));
      // Escaped form appears in the Arguments...
      expect(xml, contains('--run-task a&amp;b&lt;c&gt;d'));
      // ...and in the Description.
      expect(xml, contains('transfer (a&amp;b&lt;c&gt;d)'));
    });
  });
}
