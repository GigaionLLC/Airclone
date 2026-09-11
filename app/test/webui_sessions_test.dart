import 'package:airclone/src/webui/webui_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebUiSessions', () {
    test('issues a token that validates', () {
      final sessions = WebUiSessions();
      final token = sessions.issue();
      expect(token, isNotEmpty);
      expect(sessions.validate(token), isTrue);
    });

    test('tokens are long, URL-safe and unique', () {
      final sessions = WebUiSessions();
      final tokens = {for (var i = 0; i < 200; i++) sessions.issue()};
      expect(tokens.length, 200);
      for (final t in tokens) {
        // 32 bytes base64url, padding stripped.
        expect(t.length, greaterThanOrEqualTo(42));
        expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(t), isTrue, reason: t);
      }
    });

    test('rejects unknown, empty and null tokens', () {
      final sessions = WebUiSessions();
      expect(sessions.validate('nope'), isFalse);
      expect(sessions.validate(''), isFalse);
      expect(sessions.validate(null), isFalse);
    });

    test('expires after the idle timeout', () {
      var now = DateTime(2026);
      final sessions = WebUiSessions(
        idleTimeout: const Duration(minutes: 30),
        clock: () => now,
      );
      final token = sessions.issue();
      now = now.add(const Duration(minutes: 29));
      expect(sessions.validate(token), isTrue);
      now = now.add(const Duration(minutes: 31));
      expect(sessions.validate(token), isFalse);
    });

    test('use slides the expiry, so an open tab stays signed in', () {
      var now = DateTime(2026);
      final sessions = WebUiSessions(
        idleTimeout: const Duration(minutes: 30),
        clock: () => now,
      );
      final token = sessions.issue();
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(minutes: 20));
        expect(sessions.validate(token), isTrue, reason: 'after ${i + 1}');
      }
    });

    test('revoke ends one session, revokeAll ends every session', () {
      final sessions = WebUiSessions();
      final a = sessions.issue();
      final b = sessions.issue();
      sessions.revoke(a);
      expect(sessions.validate(a), isFalse);
      expect(sessions.validate(b), isTrue);
      sessions.revokeAll();
      expect(sessions.validate(b), isFalse);
      expect(sessions.activeCount, 0);
    });

    test('expired sessions are swept, not merely rejected', () {
      var now = DateTime(2026);
      final sessions = WebUiSessions(
        idleTimeout: const Duration(minutes: 1),
        clock: () => now,
      );
      for (var i = 0; i < 50; i++) {
        sessions.issue();
      }
      expect(sessions.activeCount, 50);
      now = now.add(const Duration(hours: 1));
      // Otherwise a long-lived server grows this map forever.
      expect(sessions.activeCount, 0);
    });
  });

  group('LoginThrottle', () {
    test('allows attempts up to the threshold', () {
      final throttle = LoginThrottle(failuresBeforeBackoff: 3);
      for (var i = 0; i < 2; i++) {
        expect(throttle.allow('1.2.3.4'), isTrue);
        throttle.recordFailure('1.2.3.4');
      }
      expect(throttle.allow('1.2.3.4'), isTrue);
    });

    test('locks out after the threshold and opens again when it expires', () {
      var now = DateTime(2026);
      final throttle = LoginThrottle(
        clock: () => now,
        failuresBeforeBackoff: 3,
        initialBackoff: const Duration(seconds: 10),
      );
      for (var i = 0; i < 3; i++) {
        throttle.recordFailure('1.2.3.4');
      }
      expect(throttle.allow('1.2.3.4'), isFalse);
      expect(throttle.retryAfter('1.2.3.4')!.inSeconds, lessThanOrEqualTo(10));
      now = now.add(const Duration(seconds: 11));
      expect(throttle.allow('1.2.3.4'), isTrue);
    });

    test('backoff doubles and then clamps', () {
      var now = DateTime(2026);
      final throttle = LoginThrottle(
        clock: () => now,
        failuresBeforeBackoff: 1,
        initialBackoff: const Duration(seconds: 10),
        maxBackoff: const Duration(seconds: 60),
      );
      throttle.recordFailure('p');
      expect(throttle.retryAfter('p')!.inSeconds, closeTo(10, 1));
      throttle.recordFailure('p');
      expect(throttle.retryAfter('p')!.inSeconds, closeTo(20, 1));
      throttle.recordFailure('p');
      expect(throttle.retryAfter('p')!.inSeconds, closeTo(40, 1));
      for (var i = 0; i < 20; i++) {
        throttle.recordFailure('p');
      }
      // Never past the cap, however long an attacker keeps going.
      expect(throttle.retryAfter('p')!.inSeconds, lessThanOrEqualTo(60));
    });

    test('one peer cannot lock out another', () {
      // Counting per-username would give a single global counter that anyone
      // could use to lock the real operator out of their own machine.
      final throttle = LoginThrottle(failuresBeforeBackoff: 2);
      throttle.recordFailure('attacker');
      throttle.recordFailure('attacker');
      expect(throttle.allow('attacker'), isFalse);
      expect(throttle.allow('operator'), isTrue);
    });

    test('a success clears the history', () {
      final throttle = LoginThrottle(failuresBeforeBackoff: 2);
      throttle.recordFailure('p');
      throttle.recordSuccess('p');
      throttle.recordFailure('p');
      expect(throttle.allow('p'), isTrue);
    });

    test('sweep drops peers that are no longer locked out', () {
      var now = DateTime(2026);
      final throttle = LoginThrottle(
        clock: () => now,
        failuresBeforeBackoff: 1,
        initialBackoff: const Duration(seconds: 1),
      );
      for (var i = 0; i < 100; i++) {
        throttle.recordFailure('peer$i');
      }
      now = now.add(const Duration(hours: 2));
      throttle.sweep();
      expect(throttle.allow('peer0'), isTrue);
    });
  });
}
