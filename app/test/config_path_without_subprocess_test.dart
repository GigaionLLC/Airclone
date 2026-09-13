import 'package:airclone/src/state/build_flavor.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Issue #5](https://github.com/GigaionLLC/Airclone/issues/5): importing a
/// config on iOS failed with *"Couldn't locate the active config file to
/// replace"*, by QR and by encrypted file alike.
///
/// Nothing was wrong with either import method. The controller located the
/// active config by running `rclone config file` as a SUBPROCESS, guarded by a
/// hardcoded `HostPlatform.isAndroid` special case. iOS is not Android, so it
/// fell into the subprocess branch — on the one platform where a subprocess is
/// forbidden outright by the OS. The Mac App Store build had the same fault for
/// the same reason.
///
/// [configMustBeAppPrivateFor] was written precisely to prevent this; its own
/// documentation names this error string. The single function that produced the
/// string was the one that never called it.
///
/// So the test worth having is not "iOS works now" — it is the INVARIANT that
/// was silently violated, which catches the next platform added to one predicate
/// and forgotten in the other.
void main() {
  /// Every platform combination the two predicates are asked about.
  const combos = [
    (name: 'desktop', android: false, mas: false, ios: false),
    (name: 'Android', android: true, mas: false, ios: false),
    (name: 'Mac App Store', android: false, mas: true, ios: false),
    (name: 'iOS', android: false, mas: false, ios: true),
  ];

  group('a platform that cannot spawn must not need to', () {
    /// THE INVARIANT. Locating the active config falls back to
    /// `Process.run(rclone, ['config', 'file'])`. Any platform that cannot run
    /// that must therefore have an explicit app-private path instead, or config
    /// import, backup, restore, merge and export all fail on a build that is
    /// otherwise working perfectly.
    test('no subprocess implies an app-private config path', () {
      for (final c in combos) {
        final canSpawn = subprocessAllowedFor(macAppStore: c.mas, isIOS: c.ios);
        final appPrivate = configMustBeAppPrivateFor(
          isAndroid: c.android,
          macAppStore: c.mas,
          isIOS: c.ios,
        );
        if (!canSpawn) {
          expect(
            appPrivate,
            isTrue,
            reason:
                '${c.name} cannot spawn a subprocess, so the config path must '
                'be resolvable without one',
          );
        }
      }
    });

    test('iOS and the Mac App Store are both in that set', () {
      expect(subprocessAllowedFor(macAppStore: false, isIOS: true), isFalse);
      expect(subprocessAllowedFor(macAppStore: true, isIOS: false), isFalse);
      expect(
        configMustBeAppPrivateFor(
          isAndroid: false,
          macAppStore: false,
          isIOS: true,
        ),
        isTrue,
      );
      expect(
        configMustBeAppPrivateFor(
          isAndroid: false,
          macAppStore: true,
          isIOS: false,
        ),
        isTrue,
      );
    });

    /// Desktop deliberately keeps rclone's own default, so Airclone and the
    /// `rclone` CLI share one config. It can spawn, so it is allowed to look.
    test('desktop still resolves the path the way it always did', () {
      expect(subprocessAllowedFor(macAppStore: false, isIOS: false), isTrue);
      expect(
        configMustBeAppPrivateFor(
          isAndroid: false,
          macAppStore: false,
          isIOS: false,
        ),
        isFalse,
      );
    });
  });

  group('resolveConfigPath on a confined platform', () {
    test('returns the app-private path', () {
      expect(
        resolveConfigPath(
          appPrivateOnly: true,
          appPrivateConfigPath: '/containers/app/rclone.conf',
        ),
        '/containers/app/rclone.conf',
      );
    });

    /// A confined build has no config-path picker (Settings hides it), so a
    /// stale override must not win and send the import at a path outside the
    /// container that the engine is not reading.
    test('an override does not override it', () {
      expect(
        resolveConfigPath(
          appPrivateOnly: true,
          appPrivateConfigPath: '/containers/app/rclone.conf',
          override: '/somewhere/else/rclone.conf',
        ),
        '/containers/app/rclone.conf',
      );
    });

    test('null when there is no app-private path to use', () {
      expect(resolveConfigPath(appPrivateOnly: true), isNull);
    });
  });
}
