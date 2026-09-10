import 'package:airclone/src/state/registration_policy.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

/// The hybrid rule, and the reason it is a rule rather than a preference:
/// **exact schedules get exact OS triggers, inexact ones share one poller.**
///
/// A "daily at 09:00" task should fire at 09:00, which an OS scheduler does for
/// free with no wakeups in between. An "every two hours" task is already polling
/// by its nature, so a private OS entry buys nothing and adds a second wakeup
/// source to keep in sync.
const _interval = TaskSchedule(
  kind: ScheduleKind.interval,
  intervalMinutes: 120,
);
const _daily = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);
const _weekly = TaskSchedule(
  kind: ScheduleKind.weekly,
  hour: 9,
  minute: 0,
  weekdays: [1, 4],
);

void main() {
  group('registrationShapeFor', () {
    test('a schedule that names a time gets its own exact trigger', () {
      for (final s in [_daily, _weekly]) {
        expect(
          registrationShapeFor(schedule: s, operatingSystem: 'windows'),
          RegistrationShape.exactTrigger,
          reason: '${s.kind} names a wall-clock time',
        );
      }
    });

    test('a schedule that names only a gap joins the shared poller', () {
      expect(
        registrationShapeFor(schedule: _interval, operatingSystem: 'windows'),
        RegistrationShape.sharedPoller,
      );
    });

    test('a platform without background execution registers nothing', () {
      // Including exact schedules: there is nothing to register INTO. macOS and
      // Linux land here until launchd and systemd-user are actually built, so
      // this is the test that stops a half-built platform from silently
      // promising background runs.
      for (final os in ['macos', 'linux', 'android', 'ios', 'plan9']) {
        for (final s in [_daily, _weekly, _interval]) {
          expect(
            registrationShapeFor(schedule: s, operatingSystem: os),
            RegistrationShape.unsupported,
            reason: '$os / ${s.kind}',
          );
        }
      }
    });
  });

  group('poll cadence', () {
    test('the default is one of the offered choices', () {
      // A default nobody can pick again after changing it is a trap.
      expect(kPollMinuteChoices, contains(kDefaultPollMinutes));
    });

    test('choices are ordered and sane', () {
      final sorted = [...kPollMinuteChoices]..sort();
      expect(kPollMinuteChoices, sorted);
      expect(kPollMinuteChoices.first, 5);
    });

    test('a stored value outside the range is clamped, not snapped', () {
      // A value from an older build or a hand-edited preference should be
      // honoured if it is sane rather than forced onto the nearest choice.
      expect(clampPollMinutes(7), 7);
      expect(clampPollMinutes(0), 5);
      expect(clampPollMinutes(-100), 5);
      expect(clampPollMinutes(99999), 60);
      expect(clampPollMinutes(kDefaultPollMinutes), kDefaultPollMinutes);
    });
  });

  group('desiredRegistrations', () {
    ({String id, TaskSchedule? schedule}) t(String id, TaskSchedule? s) =>
        (id: id, schedule: s);

    test('opting in is required — a schedule alone registers nothing', () {
      // Background execution is never assumed for a schedule just because it
      // exists; the user asks for it per task.
      final r = desiredRegistrations(
        tasks: [t('a', _daily), t('b', _interval)],
        runWhileClosed: const {},
        operatingSystem: 'windows',
      );
      expect(r.exactTriggerIds, isEmpty);
      expect(r.needsPoller, isFalse);
    });

    test('the two halves are decided together', () {
      final r = desiredRegistrations(
        tasks: [
          t('daily', _daily),
          t('weekly', _weekly),
          t('every2h', _interval),
          t('unscheduled', null),
        ],
        runWhileClosed: const {'daily', 'weekly', 'every2h', 'unscheduled'},
        operatingSystem: 'windows',
      );
      expect(r.exactTriggerIds, {'daily', 'weekly'});
      expect(
        r.needsPoller,
        isTrue,
        reason: 'one interval task opted in, so the poller must exist',
      );
    });

    test('the poller exists only while something needs it', () {
      // The failure this guards is an orphaned job waking the machine 96 times
      // a day to discover it has nothing to do.
      final none = desiredRegistrations(
        tasks: [t('daily', _daily)],
        runWhileClosed: const {'daily'},
        operatingSystem: 'windows',
      );
      expect(none.exactTriggerIds, {'daily'});
      expect(none.needsPoller, isFalse);
    });

    test('a task with no schedule is skipped even if opted in', () {
      final r = desiredRegistrations(
        tasks: [t('x', null)],
        runWhileClosed: const {'x'},
        operatingSystem: 'windows',
      );
      expect(r.exactTriggerIds, isEmpty);
      expect(r.needsPoller, isFalse);
    });

    test('an unsupported platform wants nothing, however much is opted in', () {
      final r = desiredRegistrations(
        tasks: [t('a', _daily), t('b', _interval)],
        runWhileClosed: const {'a', 'b'},
        operatingSystem: 'macos',
      );
      expect(r.exactTriggerIds, isEmpty);
      expect(r.needsPoller, isFalse);
    });

    test('several interval tasks still want exactly one poller', () {
      final r = desiredRegistrations(
        tasks: [t('a', _interval), t('b', _interval), t('c', _interval)],
        runWhileClosed: const {'a', 'b', 'c'},
        operatingSystem: 'windows',
      );
      expect(r.exactTriggerIds, isEmpty);
      expect(r.needsPoller, isTrue);
    });
  });
}
