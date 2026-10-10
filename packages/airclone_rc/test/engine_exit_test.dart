import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

/// #36: a report used to show only "Connection refused" after the engine went
/// away, which reads like a bug. Android closing a backgrounded engine is not
/// one; a crash is. The exit code is what tells them apart.
void main() {
  group('describeEngineExit', () {
    test('Android SIGKILL is the OS closing it: a notice, not a bug', () {
      final e = describeEngineExit(
        -9,
        android: true,
        uptime: const Duration(minutes: 5, seconds: 3),
      );
      expect(e.closedByOs, isTrue);
      expect(e.level, RcloneLogLevel.notice);
      expect(e.message, contains('not a bug'));
      expect(e.detail, 'signal 9 (SIGKILL) after 5m 03s');
    });

    test('SIGKILL on desktop is still worth a look', () {
      // The OOM killer or a manual kill -9: not routine the way Android is.
      final e = describeEngineExit(-9, android: false);
      expect(e.closedByOs, isFalse);
      expect(e.level, RcloneLogLevel.fatal);
      expect(e.message, contains('SIGKILL'));
    });

    test('a crash signal is fatal everywhere', () {
      for (final android in [true, false]) {
        final e = describeEngineExit(-11, android: android);
        expect(e.level, RcloneLogLevel.fatal, reason: 'android=$android');
        expect(e.closedByOs, isFalse);
        expect(e.detail, 'signal 11 (SIGSEGV)');
      }
    });

    test('exiting on its own is fatal, with the status', () {
      final e = describeEngineExit(
        2,
        android: true,
        uptime: const Duration(seconds: 42),
      );
      expect(e.level, RcloneLogLevel.fatal);
      expect(e.message, 'the engine exited unexpectedly');
      expect(e.detail, 'exit code 2 after 42s');
    });

    test('an unnamed signal still reads', () {
      final e = describeEngineExit(-42, android: false);
      expect(e.detail, 'signal 42');
      expect(e.message, 'the engine was stopped by signal 42');
    });
  });

  test('formatUptime stays short', () {
    expect(formatUptime(const Duration(seconds: 7)), '7s');
    expect(formatUptime(const Duration(minutes: 1, seconds: 5)), '1m 05s');
    expect(formatUptime(const Duration(hours: 2, minutes: 7)), '2h 07m');
  });
}
