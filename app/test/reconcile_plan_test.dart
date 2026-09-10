import 'package:airclone/src/state/registration_policy.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reconciliation, and the migration hiding inside it.
///
/// A user who set up an "every 2 hours" schedule under the old build has a
/// private per-task entry in Task Scheduler. Under the hybrid that entry is
/// simply not desired any more, so it shows up as something to delete like any
/// other stale registration — no version check, no one-shot upgrade step to get
/// wrong, and the code that keeps things right every day is the code that
/// cleans it up.
const _interval = TaskSchedule(
  kind: ScheduleKind.interval,
  intervalMinutes: 120,
);
const _daily = TaskSchedule(kind: ScheduleKind.daily, hour: 9, minute: 0);

({Set<String> exactTriggerIds, bool needsPoller}) want({
  Set<String> exact = const {},
  bool poller = false,
}) => (exactTriggerIds: exact, needsPoller: poller);

void main() {
  group('planReconcile', () {
    test('nothing wanted, nothing registered, nothing to do', () {
      final p = planReconcile(desired: want(), existing: const {});
      expect(p.toCreate, isEmpty);
      expect(p.toDelete, isEmpty);
    });

    test('creates only what is missing and deletes only what is stale', () {
      final p = planReconcile(
        desired: want(exact: {'daily-a', 'daily-b'}, poller: true),
        existing: {'daily-a', 'gone-task'},
      );
      expect(p.toCreate, ['Run due tasks', 'daily-b']);
      expect(p.toDelete, ['gone-task']);
    });

    test('an already-correct set is a no-op', () {
      // Reconcile runs on every save and on launch; if it churned Task
      // Scheduler each time it would be a worse problem than the one it fixes.
      final p = planReconcile(
        desired: want(exact: {'a'}, poller: true),
        existing: {'a', 'Run due tasks'},
      );
      expect(p.toCreate, isEmpty);
      expect(p.toDelete, isEmpty);
    });

    test(
      'THE MIGRATION: an old per-task entry for an interval schedule goes',
      () {
        // Exactly the upgrade case. The task still exists and is still opted in;
        // it is the SHAPE that changed, so its old entry is stale and the shared
        // poller is missing.
        final desired = desiredRegistrations(
          tasks: [(id: 'every2h', schedule: _interval)],
          runWhileClosed: const {'every2h'},
          operatingSystem: 'windows',
        );
        final p = planReconcile(
          desired: desired,
          existing: {'every2h'}, // what the old build left behind
        );
        expect(p.toDelete, ['every2h']);
        expect(p.toCreate, ['Run due tasks']);
      },
    );

    test('a daily schedule from the old build is left exactly as it was', () {
      // The other half of the migration, and the easy one to get wrong: an
      // exact schedule's entry is STILL the right shape, so churning it would
      // be pure risk for no gain.
      final desired = desiredRegistrations(
        tasks: [(id: 'nightly', schedule: _daily)],
        runWhileClosed: const {'nightly'},
        operatingSystem: 'windows',
      );
      final p = planReconcile(desired: desired, existing: {'nightly'});
      expect(p.toCreate, isEmpty);
      expect(p.toDelete, isEmpty);
    });

    test('turning the last interval schedule off removes the shared job', () {
      // Otherwise it wakes the machine 96 times a day forever to find nothing.
      final p = planReconcile(
        desired: want(exact: {'nightly'}),
        existing: {'nightly', 'Run due tasks'},
      );
      expect(p.toDelete, ['Run due tasks']);
      expect(p.toCreate, isEmpty);
    });

    test('opting everything out clears the folder', () {
      final p = planReconcile(
        desired: want(),
        existing: {'a', 'b', 'Run due tasks'},
      );
      expect(p.toDelete, ['Run due tasks', 'a', 'b']);
    });

    test('an unrecognised entry in OUR folder is residue, and goes', () {
      // The folder is ours. Anything in it we do not want is almost certainly
      // ours from an older build under a name we no longer use.
      final p = planReconcile(
        desired: want(exact: {'a'}),
        existing: {'a', 'airclone-legacy-thing'},
      );
      expect(p.toDelete, ['airclone-legacy-thing']);
    });

    test('the plan is deterministic', () {
      // A log of what changed should read the same way twice, and a test should
      // be able to assert it.
      final a = planReconcile(
        desired: want(exact: {'z', 'a', 'm'}),
        existing: const {},
      );
      expect(a.toCreate, ['a', 'm', 'z']);
    });
  });

  group('parseRegisteredNames', () {
    test('reads the leaf names out of schtasks CSV', () {
      const csv = '''
"\\Airclone\\probe-one","9/9/2026 11:59:00 PM","Ready"
"\\Airclone\\Run due tasks","9/9/2026 11:59:00 PM","Ready"
''';
      expect(parseRegisteredNames(csv), {'probe-one', 'Run due tasks'});
    });

    test('IGNORES everything outside our folder', () {
      // The caller may hand over a query across every task on the machine.
      // Deleting one of those would be catastrophic, so this is the assertion
      // that matters most in the file.
      const csv = '''
"\\Microsoft\\Windows\\UpdateOrchestrator\\Reboot","","Ready"
"\\Airclone\\mine","","Ready"
"\\SomeVendor\\Airclone\\lookalike","","Ready"
"\\AircloneOther\\nope","","Ready"
''';
      expect(parseRegisteredNames(csv), {'mine'});
    });

    test('ignores a nested folder — we only ever create leaves', () {
      const csv =
          '"\\Airclone\\sub\\deeper","","Ready"\n"\\Airclone\\flat","","Ready"';
      expect(parseRegisteredNames(csv), {'flat'});
    });

    test('survives blank lines, headers and junk', () {
      const csv = '''

TaskName,Next Run Time,Status
not a csv row at all
"\\Airclone\\ok","","Ready"
"unterminated
''';
      expect(parseRegisteredNames(csv), {'ok'});
    });

    test('an empty query yields an empty set, not a crash', () {
      expect(parseRegisteredNames(''), isEmpty);
      expect(parseRegisteredNames('\n\n  \n'), isEmpty);
    });

    test('a name containing spaces survives', () {
      // The shared job has one, and losing it would make reconcile delete and
      // recreate it on every single run.
      expect(parseRegisteredNames('"\\Airclone\\Run due tasks","","Ready"'), {
        kDueRunnerTaskName,
      });
    });
  });
}
