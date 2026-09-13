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

  /// Found by an adversarial pass over the Web UI's authorization surface, and
  /// reproduced against the pinned rclone before it was believed.
  ///
  /// `options/get` was on the allowlist and had NO CALLER anywhere in
  /// `app/lib`. It returns rclone's whole global option tree, and that tree
  /// includes the `rc` block: `rc.Auth.BasicUser`, `rc.Auth.BasicPass`,
  /// `rc.HTTP.ListenAddr`. Those are the ENGINE's own credentials - the ones
  /// this allowlist exists to stand in front of. One allowed call gave a Web UI
  /// session everything it needed to talk to rcd directly and ignore the
  /// allowlist entirely, `core/command` included - which this policy file's own
  /// comment calls "the method that makes the rc API equivalent to shell
  /// access".
  ///
  /// Reproduced exactly as Airclone runs it, the password supplied through
  /// RCLONE_RC_PASS, which is the route http_rclone_client.dart uses:
  ///
  ///     RCLONE_RC_PASS=PROVE_THIS_LEAKS_274a80b8 rclone rc --loopback options/get
  ///     -> rc.Auth.BasicPass = "PROVE_THIS_LEAKS_274a80b8"
  ///
  /// The lesson generalises past this one method: an entry with no call site
  /// cannot be justified by the rule at the top of the policy file, and that is
  /// exactly how this one survived review. Absence of a caller is the signal.
  group('options/get never comes back', () {
    test('it is not allowed', () {
      expect(kAllowedRcMethods, isNot(contains('options/get')));
      expect(rcPolicyFor('options/get').allowed, isFalse);
    });

    /// In the DENIED map rather than merely absent, so
    /// debugAssertRcPolicyConsistent fails at startup if anyone adds it back.
    /// A comment would not.
    test('it is denied on the record, with the reason', () {
      expect(kDeniedRcMethods, contains('options/get'));
      final why = kDeniedRcMethods['options/get']!;
      expect(why, contains('rc.Auth.BasicPass'));
      expect(why.toLowerCase(), contains('credential'));
    });

    test('the startup assertion still passes', () {
      expect(debugAssertRcPolicyConsistent, returnsNormally);
    });
  });

  /// The three methods the same sweep found with no literal rpc() call site.
  /// Recorded so the next reader knows they were looked at rather than missed.
  test('methods with no call site are accounted for', () {
    // Removed: it handed out the engine credentials.
    expect(kAllowedRcMethods, isNot(contains('options/get')));
    // Kept: read-only status calls, no parameters, no host paths. Reached
    // through helpers rather than a literal rpc('x/y') string, which is why
    // the grep missed them.
    expect(kAllowedRcMethods, contains('job/list'));
    expect(kAllowedRcMethods, contains('vfs/stats'));
  });
}
