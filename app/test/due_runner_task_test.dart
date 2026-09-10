import 'package:airclone/src/state/poll_cadence.dart';
import 'package:airclone/src/state/registration_policy.dart';
import 'package:airclone/src/state/windows_task_scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shared half of the hybrid: one Windows Scheduled Task that wakes on a
/// cadence and runs whatever is due, for the schedules that never named an
/// exact time.
///
/// Task Scheduler's parser is order-sensitive and rejects a definition outright
/// rather than explaining itself, so the XML shape is pinned here the same way
/// the per-task builder's is.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('buildDueRunnerXml', () {
    String xml({int minutes = 15, String exe = r'C:\Apps\airclone.exe'}) =>
        buildDueRunnerXml(intervalMinutes: minutes, exePath: exe);

    test('runs --run-due, not a single task', () {
      // The whole point of the shared job: it selects, rather than being told.
      final x = xml();
      expect(x, contains('<Arguments>--run-due</Arguments>'));
      expect(x, isNot(contains('--run-task')));
    });

    test('repeats on the cadence it was given, forever', () {
      expect(xml(minutes: 5), contains('<Interval>PT5M</Interval>'));
      expect(xml(minutes: 60), contains('<Interval>PT60M</Interval>'));
      // No <Duration> is the schema's way of saying "repeat indefinitely"; a
      // duration would silently stop the scheduler after that window.
      expect(xml(), isNot(contains('<Duration>')));
    });

    test('an out-of-range cadence is clamped, never emitted raw', () {
      // A definition built from a corrupt preference must still be a sane task,
      // not one that wakes every second.
      expect(xml(minutes: 0), contains('<Interval>PT5M</Interval>'));
      expect(xml(minutes: -30), contains('<Interval>PT5M</Interval>'));
      expect(xml(minutes: 99999), contains('<Interval>PT60M</Interval>'));
    });

    test('the start boundary is in the past so the first fire is immediate', () {
      // StartWhenAvailable only catches up a boundary that has already elapsed.
      expect(xml(), contains('<StartBoundary>2024-01-01T00:00:00'));
      expect(xml(), contains('<StartWhenAvailable>true</StartWhenAvailable>'));
    });

    test('unattended settings match the per-task job, deliberately', () {
      // Same reasons, so the same answers: catch up a missed run, do not skip
      // on battery, never stack a slow run under the next tick.
      final x = xml();
      expect(
        x,
        contains(
          '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>',
        ),
      );
      expect(
        x,
        contains(
          '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>',
        ),
      );
      expect(x, contains('<ExecutionTimeLimit>PT6H</ExecutionTimeLimit>'));
      expect(x, contains('<RunLevel>LeastPrivilege</RunLevel>'));
    });

    test('an exe path with XML metacharacters stays well-formed', () {
      final x = xml(exe: r'C:\Air & Clone\<v1>\airclone.exe');
      expect(x, contains(r'C:\Air &amp; Clone\&lt;v1&gt;\airclone.exe'));
      expect(x, isNot(contains('<v1>')));
    });

    test('the description says what the user did not name themselves', () {
      // This job appears in Task Scheduler without the user ever creating it by
      // name, so it has to explain itself where they will read it.
      final x = xml(minutes: 30);
      expect(x, contains('Airclone background scheduler'));
      expect(x, contains('every 30 minutes'));
    });

    test('the shared job has a fixed, findable name', () {
      // An uninstall has to find it and a reconcile has to recognise it.
      expect(kDueRunnerTaskName, 'Run due tasks');
      expect(
        WindowsTaskScheduler.taskName(kDueRunnerTaskName),
        r'Airclone\Run due tasks',
      );
    });
  });

  group('PollCadence', () {
    test('starts at the default', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(pollCadenceProvider), kDefaultPollMinutes);
    });

    test('set clamps on the way in', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(pollCadenceProvider.notifier);
      await n.set(1);
      expect(c.read(pollCadenceProvider), 5);
      await n.set(100000);
      expect(c.read(pollCadenceProvider), 60);
      await n.set(5);
      expect(c.read(pollCadenceProvider), 5);
    });

    test('a chosen cadence survives a restart', () async {
      final first = ProviderContainer();
      await first.read(pollCadenceProvider.notifier).set(30);
      first.dispose();

      // The OS registration built from this outlives the process, so a cadence
      // that resets on relaunch would silently disagree with what is registered.
      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.read(pollCadenceProvider);
      await Future<void>.delayed(Duration.zero);
      expect(second.read(pollCadenceProvider), 30);
    });

    test('a corrupt stored value is clamped on read, not trusted', () async {
      SharedPreferences.setMockInitialValues({'scheduler_poll_minutes': -7});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(pollCadenceProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(pollCadenceProvider), 5);
    });
  });
}
