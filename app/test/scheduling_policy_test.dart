import 'package:airclone/src/state/scheduling_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// The point of this file is one place deciding what "scheduled" means, so the
/// tests are about the DECISION, not the plumbing: the pure function takes an
/// OS name so it can be checked for every platform from any platform.
void main() {
  group('schedulingSupportFor', () {
    test('Windows is the only platform with background execution today', () {
      expect(
        schedulingSupportFor('windows'),
        SchedulingSupport.background,
        reason: 'Task Scheduler + the headless --run-task entry point',
      );
    });

    test('macOS and Linux run while open, and must not claim more', () {
      // launchd and systemd-user are planned, not built. Claiming background
      // here has a data-loss shape: a user closes the app expecting a backup
      // to run overnight, and it does not.
      for (final os in ['macos', 'linux']) {
        expect(
          schedulingSupportFor(os),
          SchedulingSupport.whileOpen,
          reason: os,
        );
      }
    });

    test('Android runs in the background since v0.8 Phase F', () {
      // WorkManager + a headless FlutterEngine, proven on an emulator: an
      // OS-timed wake with the app process dead ran a due task to completion.
      expect(schedulingSupportFor('android'), SchedulingSupport.background);
    });

    test('iOS still has no scheduling at all', () {
      // iOS does not permit what this needs, and is explicitly out of scope.
      expect(schedulingSupportFor('ios'), SchedulingSupport.none);
    });

    test('an unknown platform gets none, not a guess', () {
      // Promising a background run we never wired is the failure this file
      // exists to prevent, so the default must be the pessimistic one.
      for (final os in ['fuchsia', '', 'plan9', 'WINDOWS']) {
        expect(schedulingSupportFor(os), SchedulingSupport.none, reason: os);
      }
    });
  });

  group('derived answers', () {
    test('canRunWhileClosed is background only', () {
      expect(
        schedulingSupportFor('windows') == SchedulingSupport.background,
        isTrue,
      );
      expect(
        schedulingSupportFor('macos') == SchedulingSupport.background,
        isFalse,
      );
    });

    test('every support level has its own non-empty sentence', () {
      final seen = <String>{};
      for (final s in SchedulingSupport.values) {
        final line = schedulingSummaryFor(s);
        expect(line, isNotEmpty, reason: '$s');
        expect(
          line.endsWith('.'),
          isTrue,
          reason: '$s should read as a sentence',
        );
        expect(
          seen.add(line),
          isTrue,
          reason: '$s repeats another level\'s text',
        );
      }
    });

    test('the whileOpen sentence says what happens to a missed run', () {
      // This is the sentence users act on: it must not stop at "runs while
      // open" and leave them guessing what a closed laptop costs them.
      final line = schedulingSummaryFor(SchedulingSupport.whileOpen);
      expect(line.toLowerCase(), contains('next launch'));
    });

    test('the none sentence does not pretend saved tasks are gone too', () {
      final line = schedulingSummaryFor(SchedulingSupport.none);
      expect(line.toLowerCase(), contains('by hand'));
    });
  });
}
