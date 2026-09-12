import 'package:airclone/src/webui/webui_rc_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _uploadStaysOutOfTheAllowlist();
  group('the three that must never be reachable', () {
    test('core/command is refused', () {
      // This is the method that makes rclone's rc "equivalent to shell access
      // as the user running rclone". If this test ever goes green-by-deletion,
      // the Web UI has become a remote shell.
      final decision = rcPolicyFor('core/command');
      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('shell access'));
    });

    test('core/quit is refused', () {
      expect(isRcMethodAllowed('core/quit'), isFalse);
    });

    test('config/setpath is refused', () {
      expect(isRcMethodAllowed('config/setpath'), isFalse);
    });
  });

  group('fail closed', () {
    test('an unknown method is refused', () {
      expect(isRcMethodAllowed('operations/notARealMethod'), isFalse);
      expect(isRcMethodAllowed(''), isFalse);
      expect(isRcMethodAllowed('rc/noop'), isFalse);
    });

    test('a future rclone method is refused until someone adds it', () {
      // The allowlist must not widen on its own when rclone ships new methods.
      expect(isRcMethodAllowed('core/somethingAddedIn2027'), isFalse);
    });

    test('case and whitespace do not sneak past the list', () {
      expect(isRcMethodAllowed('Core/Command'), isFalse);
      expect(isRcMethodAllowed(' core/command'), isFalse);
      expect(isRcMethodAllowed('core/command '), isFalse);
    });

    test('a refusal explains itself without leaking host detail', () {
      final reason = rcPolicyFor('made/up').reason!;
      expect(reason, contains('made/up'));
      expect(reason, contains('does not allow'));
    });
  });

  group('what the app actually needs', () {
    test('browsing, transferring and mounting are all allowed', () {
      for (final method in const [
        'core/version',
        'config/listremotes',
        'operations/list',
        'operations/stat',
        'operations/mkdir',
        'operations/copyfile',
        'sync/copy',
        'sync/move',
        'job/status',
        'mount/mount',
        'mount/unmount',
        'vfs/refresh',
      ]) {
        expect(isRcMethodAllowed(method), isTrue, reason: method);
      }
    });

    test('every allowed method is namespaced, never a bare word', () {
      for (final method in kAllowedRcMethods) {
        expect(method.contains('/'), isTrue, reason: method);
        expect(method.trim(), method, reason: method);
        expect(
          method.toLowerCase().startsWith(method.split('/').first),
          isTrue,
          reason: method,
        );
      }
    });
  });

  group('policy consistency', () {
    test('the two lists never overlap', () {
      // Guards the specific mistake of pasting a method into the allowlist to
      // fix a bug while its "never allow this" comment sits there, still true
      // and no longer enforcing anything.
      expect(debugAssertRcPolicyConsistent, returnsNormally);
      for (final denied in kDeniedRcMethods.keys) {
        expect(kAllowedRcMethods.contains(denied), isFalse, reason: denied);
      }
    });

    test('every denial carries a reason', () {
      for (final entry in kDeniedRcMethods.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });
  });
}

/// Upload was added to the Web UI without widening this list, and that was the
/// point. The browser posts to an app endpoint and the APP talks to the engine,
/// so `operations/uploadfile` never becomes something a stolen session can call
/// directly. This guards the decision, because the obvious way to implement
/// upload is to forward the RC method, and the obvious way is the wrong one.
void _uploadStaysOutOfTheAllowlist() {
  test('operations/uploadfile is NOT browser-reachable', () {
    expect(kAllowedRcMethods.contains('operations/uploadfile'), isFalse);
  });
}
