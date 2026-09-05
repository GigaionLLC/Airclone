import 'dart:async';

import 'package:airclone/src/rclone/http_rclone_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// A retry is the kind of fix that can be worse than the bug it removes, so the
/// policy is pinned here rather than trusted.
///
/// It exists because of one line in a real field report:
///
///     ClientException: Connection closed before full header was received
///
/// — a keep-alive socket that died before the response started. The 1 Hz stats
/// poller healed it a second later and nothing was lost, which is exactly why
/// it was worth handling: the same race on a call the USER made surfaces as a
/// failed listing or a failed copy, with no poller to quietly try again.
void main() {
  /// A sender that fails the first [failures] calls, then succeeds.
  ({Future<String> Function() send, List<int> calls}) flaky(
    int failures, {
    Object Function()? error,
  }) {
    final calls = <int>[];
    var n = 0;
    return (
      calls: calls,
      send: () async {
        calls.add(++n);
        if (n <= failures) {
          throw error?.call() ?? const SocketishException();
        }
        return 'ok';
      },
    );
  }

  group('a connection-level failure on a read-only method', () {
    test('is retried once, and the caller never sees it', () async {
      final f = flaky(1);
      final out = await sendWithConnectionRetry('core/stats', f.send);
      expect(out, 'ok');
      expect(f.calls.length, 2);
    });

    test('is reported as RECOVERED, not as a failure', () async {
      final seen = <(String, bool)>[];
      await sendWithConnectionRetry(
        'core/stats',
        flaky(1).send,
        onTransportFailure: (e, {required recovered}) =>
            seen.add(('$e', recovered)),
      );
      expect(seen.length, 1);
      expect(seen.single.$2, isTrue);
    });

    test('rethrows when the retry fails too, reported as a failure', () async {
      final seen = <bool>[];
      final f = flaky(2);
      await expectLater(
        sendWithConnectionRetry(
          'core/stats',
          f.send,
          onTransportFailure: (e, {required recovered}) => seen.add(recovered),
        ),
        throwsA(isA<SocketishException>()),
      );
      // Once, not forever: two attempts total.
      expect(f.calls.length, 2);
      expect(seen, [false]);
    });
  });

  group('what is NOT retried', () {
    test('a method that moves data is never sent twice', () async {
      // The whole hazard: a doubled copy is worse than a visible error.
      for (final method in const [
        'operations/copyfile',
        'operations/movefile',
        'operations/purge',
        'operations/deletefile',
        'sync/copy',
        'sync/move',
        'config/create',
        'config/delete',
        'mount/mount',
        'mount/unmount',
        'job/stop',
        'core/quit',
      ]) {
        final f = flaky(1);
        await expectLater(
          sendWithConnectionRetry(method, f.send),
          throwsA(isA<SocketishException>()),
          reason: '$method must not be repeated',
        );
        expect(f.calls.length, 1, reason: '$method was sent twice');
      }
    });

    test('a TIMEOUT is not retried, even on a read-only method', () async {
      // A timeout means the engine TOOK the request and did not answer. A
      // second copy piles work onto an engine already struggling.
      final f = flaky(1, error: () => TimeoutException('30s'));
      await expectLater(
        sendWithConnectionRetry('core/stats', f.send),
        throwsA(isA<TimeoutException>()),
      );
      expect(f.calls.length, 1);
    });
  });

  group('the allowlist', () {
    test('covers the pollers that run continuously', () {
      // These are the calls a dropped socket is most likely to catch, because
      // they are the ones always in flight.
      for (final m in const [
        'core/stats',
        'core/version',
        'mount/listmounts',
        'job/status',
        'operations/list',
      ]) {
        expect(isRetryableRcMethod(m), isTrue, reason: m);
      }
    });

    test('excludes everything that changes something', () {
      for (final m in const [
        'operations/copyfile',
        'sync/sync',
        'config/create',
        'config/update',
        'mount/mount',
        'core/command',
        'vfs/refresh',
        'core/bwlimit',
      ]) {
        expect(isRetryableRcMethod(m), isFalse, reason: m);
      }
    });

    test('an unknown method is not retried', () {
      // Fail closed: a method added later is not repeated until someone has
      // decided it is safe to repeat.
      expect(isRetryableRcMethod('operations/somethingNew'), isFalse);
      expect(isRetryableRcMethod(''), isFalse);
    });
  });

  test('no failure at all means one call and no report', () async {
    final seen = <bool>[];
    final f = flaky(0);
    final out = await sendWithConnectionRetry(
      'core/stats',
      f.send,
      onTransportFailure: (e, {required recovered}) => seen.add(recovered),
    );
    expect(out, 'ok');
    expect(f.calls.length, 1);
    expect(seen, isEmpty);
  });
}

/// Stands in for `http.ClientException` — the class the real dropped-socket
/// failure arrives as. The policy keys off "not a TimeoutException", so the
/// concrete type does not matter and the test avoids depending on package:http.
class SocketishException implements Exception {
  const SocketishException();
  @override
  String toString() =>
      'ClientException: Connection closed before full header was received';
}
