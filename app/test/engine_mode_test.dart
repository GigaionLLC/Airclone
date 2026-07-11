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
}
