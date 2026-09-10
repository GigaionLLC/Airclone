import 'package:airclone/src/state/registration_policy.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hybrid means three different things can run a saved task: the in-app tick
/// while Airclone is open, an exact OS trigger, or the shared poller. When one
/// of them does not fire, "it did not run" is not a diagnosis.
///
/// These pin the sentence that turns it into one. The standard they are held to
/// is not "is it accurate" but **can the user act on it** — a name they can go
/// and open, and a number they can compare against what they saw.
const _interval = TaskSchedule(
  kind: ScheduleKind.interval,
  intervalMinutes: 120,
);
const _daily = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);

String explain({
  TaskSchedule schedule = _daily,
  String os = 'windows',
  bool runWhileClosed = true,
  int pollMinutes = 15,
  String taskName = 'Photos to backup',
}) => registrationExplanation(
  schedule: schedule,
  operatingSystem: os,
  runWhileClosed: runWhileClosed,
  pollMinutes: pollMinutes,
  taskName: taskName,
);

void main() {
  test('an exact schedule names the entry the user can go and open', () {
    final s = explain();
    // The task's own name, because that is what they will see in the list.
    expect(s, contains('Photos to backup'));
    expect(s, contains('Task Scheduler'));
    expect(s, contains('exact time'));
  });

  test('a poller schedule admits how late it can be, in minutes', () {
    // The number matters more than the mechanism: it is what the user compares
    // against "it ran at 09:12 and I asked for 09:00".
    final s = explain(schedule: _interval, pollMinutes: 30);
    expect(s, contains('30 minutes'));
    expect(s, contains('late'));
    expect(
      s,
      contains(kDueRunnerTaskName),
      reason: 'the shared job has a name; use it',
    );
  });

  test('the poller sentence says the job is SHARED', () {
    // Otherwise a user who disables it to stop one task silently stops them all.
    expect(explain(schedule: _interval), contains('shared'));
  });

  test('not opting in says so, and says what still happens', () {
    // The commonest "why did nothing run" cause, and the one where naming the
    // checkbox saves the whole investigation.
    final s = explain(runWhileClosed: false);
    expect(s, contains('only while Airclone is open'));
    expect(s, contains('Also run while Airclone is closed'));
    expect(s, contains('next launch'));
  });

  test(
    'a platform with no background scheduling does not blame a checkbox',
    () {
      // There is no checkbox to blame on macOS or iOS, so pointing at one
      // would send the user looking for a control that is not there.
      for (final os in ['macos', 'linux', 'ios']) {
        final s = explain(os: os, runWhileClosed: true);
        expect(s, contains('no background scheduling'), reason: os);
        expect(s, isNot(contains('Task Scheduler')), reason: os);
        expect(s, isNot(contains('Also run while')), reason: os);
      }
    },
  );

  test('unsupported wins over not-opted-in', () {
    // Both are true on iOS; only one of them is useful to say.
    expect(
      explain(os: 'ios', runWhileClosed: false),
      contains('no background scheduling'),
    );
  });

  group('Android', () {
    test('never names a place to look, because there is not one', () {
      // Windows registrations are inspectable entries a user can open. The
      // Android wake is WorkManager's; naming Task Scheduler there would send
      // someone hunting for a screen that does not exist on their phone.
      final s = explain(os: 'android', schedule: _daily);
      expect(s, isNot(contains('Task Scheduler')));
      expect(s, isNot(contains(kDueRunnerTaskName)));
    });

    test('admits the ways a phone makes a run later still', () {
      // Someone comparing "it said 15 minutes" against a run four hours late
      // needs doze, battery saver and Wi-Fi named, or they will reasonably
      // conclude it is broken.
      final s = explain(os: 'android', pollMinutes: 15);
      expect(s, contains('15 minutes'));
      expect(s.toLowerCase(), contains('asleep'));
      expect(s.toLowerCase(), contains('battery'));
      expect(s.toLowerCase(), contains('wi-fi'));
    });

    test('says the same for an exact schedule as an interval one', () {
      // One periodic worker serves both, so promising a daily 09:00 anything
      // more precise would be a lie WorkManager cannot honour.
      expect(
        explain(os: 'android', schedule: _daily),
        explain(os: 'android', schedule: _interval),
      );
    });
  });

  test('every case produces a real sentence', () {
    for (final os in ['windows', 'macos', 'android']) {
      for (final s in [_daily, _interval]) {
        for (final opted in [true, false]) {
          final line = explain(schedule: s, os: os, runWhileClosed: opted);
          expect(line, isNotEmpty, reason: '$os/${s.kind}/$opted');
          expect(line.endsWith('.'), isTrue, reason: '$os/${s.kind}/$opted');
        }
      }
    }
  });
}
