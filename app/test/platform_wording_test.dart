import 'package:airclone/src/state/registration_policy.dart';
import 'package:airclone/src/state/scheduling_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Airclone runs on five platforms that schedule differently, and the scheduling
/// UI used to carry two sentences that were simply typed in rather than chosen
/// per platform. On an Android phone, live testing showed both at once:
///
///  * the "Also run while Airclone is closed" checkbox said Airclone would
///    register "a Windows Scheduled Task" and that missed runs start "as soon as
///    the PC is available" — on a phone, with no PC involved, directly above the
///    correct Android explanation; and
///  * the Saved tasks footer said scheduled tasks "run only while Airclone is
///    open", which is false on precisely the two platforms where background
///    execution works, and contradicted the Settings section above it.
///
/// A wrong sentence about scheduling is worse than a vague one: it tells someone
/// their backup did not run for a reason that is not true. These pin the rule
/// that the wording is derived, never typed.
void main() {
  group('background registration blurb', () {
    test('Windows describes the Scheduled Task it really creates', () {
      final s = backgroundRegistrationBlurb('windows');
      expect(s, contains('Scheduled Task'));
      expect(s, contains('PC'));
    });

    test('Android never mentions Windows or a PC', () {
      final s = backgroundRegistrationBlurb('android');
      expect(s, isNot(contains('Windows')));
      expect(s, isNot(contains('PC')));
      expect(s, isNot(contains('Scheduled Task')));
      expect(s.toLowerCase(), contains('android'));
    });

    test('a platform without background scheduling promises nothing', () {
      for (final os in ['macos', 'linux', 'ios', 'fuchsia']) {
        final s = backgroundRegistrationBlurb(os);
        expect(s, isNot(contains('Windows')), reason: os);
        expect(s, isNot(contains('Scheduled Task')), reason: os);
        expect(s, contains('next launch'), reason: os);
      }
    });

    test('every platform gets a non-empty, distinct-enough sentence', () {
      for (final os in ['windows', 'android', 'macos', 'linux', 'ios']) {
        expect(backgroundRegistrationBlurb(os), isNotEmpty, reason: os);
      }
      expect(
        backgroundRegistrationBlurb('windows'),
        isNot(equals(backgroundRegistrationBlurb('android'))),
      );
    });
  });

  group('scheduling summary', () {
    test('the two background platforms do NOT say "only while open"', () {
      // The bug this replaces: a hardcoded "run only while Airclone is open"
      // shown on Windows and Android, where it is false.
      final s = schedulingSummaryFor(SchedulingSupport.background);
      expect(s, isNot(contains('only while')));
      expect(s, contains('even with Airclone closed'));
    });

    test('whileOpen says so, and says what happens to a missed run', () {
      final s = schedulingSummaryFor(SchedulingSupport.whileOpen);
      expect(s, contains('while Airclone is open'));
      expect(s, contains('next launch'));
    });

    test('Windows and Android both map to background support', () {
      expect(schedulingSupportFor('windows'), SchedulingSupport.background);
      expect(schedulingSupportFor('android'), SchedulingSupport.background);
    });
  });
}
