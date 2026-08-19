import 'package:airclone/src/state/build_flavor.dart';
import 'package:airclone/src/state/native_actions_policy.dart';
import 'package:airclone/src/state/engine_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveEngineMode', () {
    test('a disallowed subprocess (iOS/MAS) forces the in-process library', () {
      for (final s in EngineMode.values) {
        expect(
          resolveEngineMode(
            setting: s,
            subprocessAllowed: false,
            libraryAvailable: true,
            binaryAvailable: true,
          ),
          EngineMode.inProcess,
          reason: 'setting $s must not override the subprocess ban',
        );
      }
    });

    test('explicit binary always resolves to binary', () {
      expect(
        resolveEngineMode(
          setting: EngineMode.binary,
          subprocessAllowed: true,
          libraryAvailable: true,
          binaryAvailable: true,
        ),
        EngineMode.binary,
      );
    });

    test(
      'explicit in-process resolves to in-process when the lib is present',
      () {
        expect(
          resolveEngineMode(
            setting: EngineMode.inProcess,
            subprocessAllowed: true,
            libraryAvailable: true,
            binaryAvailable: true,
          ),
          EngineMode.inProcess,
        );
      },
    );

    test(
      'explicit in-process falls back to binary when the lib is missing',
      () {
        expect(
          resolveEngineMode(
            setting: EngineMode.inProcess,
            subprocessAllowed: true,
            libraryAvailable: false,
            binaryAvailable: true,
          ),
          EngineMode.binary,
        );
      },
    );

    test('auto prefers the binary on desktop when one is available', () {
      expect(
        resolveEngineMode(
          setting: EngineMode.auto,
          subprocessAllowed: true,
          libraryAvailable: true,
          binaryAvailable: true,
        ),
        EngineMode.binary,
      );
    });

    test('auto uses the library when no binary but the lib is bundled', () {
      expect(
        resolveEngineMode(
          setting: EngineMode.auto,
          subprocessAllowed: true,
          libraryAvailable: true,
          binaryAvailable: false,
        ),
        EngineMode.inProcess,
      );
    });

    test(
      'auto with neither available resolves to binary (provisioning path)',
      () {
        expect(
          resolveEngineMode(
            setting: EngineMode.auto,
            subprocessAllowed: true,
            libraryAvailable: false,
            binaryAvailable: false,
          ),
          EngineMode.binary,
        );
      },
    );
  });

  group('engineModeFromName', () {
    test('round-trips known names', () {
      for (final m in EngineMode.values) {
        expect(engineModeFromName(m.name), m);
      }
    });
    test('absent / unknown defaults to auto', () {
      expect(engineModeFromName(null), EngineMode.auto);
      expect(engineModeFromName(''), EngineMode.auto);
      expect(engineModeFromName('nonsense'), EngineMode.auto);
    });
  });
  group('build flavour policy', () {
    test(
      'a subprocess is allowed on desktop, and nowhere Apple forbids it',
      () {
        expect(subprocessAllowedFor(macAppStore: false, isIOS: false), isTrue);
        expect(subprocessAllowedFor(macAppStore: true, isIOS: false), isFalse);
        expect(subprocessAllowedFor(macAppStore: false, isIOS: true), isFalse);
      },
    );

    test('MAS resolves to the in-process engine whatever the user picked', () {
      for (final setting in EngineMode.values) {
        expect(
          resolveEngineMode(
            setting: setting,
            subprocessAllowed: subprocessAllowedFor(
              macAppStore: true,
              isIOS: false,
            ),
            libraryAvailable: true,
            binaryAvailable: true,
          ),
          EngineMode.inProcess,
          reason: 'setting $setting must not defeat the sandbox constraint',
        );
      }
    });

    test('the config is app-private exactly on the confined platforms', () {
      bool f({bool a = false, bool m = false, bool i = false}) =>
          configMustBeAppPrivateFor(isAndroid: a, macAppStore: m, isIOS: i);
      expect(f(), isFalse, reason: 'desktop shares rclone CLI default');
      expect(f(a: true), isTrue);
      expect(f(m: true), isTrue);
      expect(f(i: true), isTrue);
    });

    test(
      'subprocess-spawning OS actions are off exactly where spawning is',
      () {
        expect(revealInFileManagerAllowedFor(subprocessAllowed: true), isTrue);
        expect(
          revealInFileManagerAllowedFor(subprocessAllowed: false),
          isFalse,
        );
        expect(archiveAllowedFor(subprocessAllowed: true), isTrue);
        expect(archiveAllowedFor(subprocessAllowed: false), isFalse);
        // The MAS build is the case that matters: both must be off.
        final mas = subprocessAllowedFor(macAppStore: true, isIOS: false);
        expect(revealInFileManagerAllowedFor(subprocessAllowed: mas), isFalse);
        expect(archiveAllowedFor(subprocessAllowed: mas), isFalse);
      },
    );
  });
}
