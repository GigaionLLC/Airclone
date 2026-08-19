import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/settings_controller.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Pure decision bits behind the config-path override (plan §1): the resolution
// order the engine spawns with, the pre-switch validation argv, and the settings
// persistence round-trip. No Process.run and no engine is spawned here — the
// runtime path (validate → persist → restart) is exercised end-to-end elsewhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveConfigPath — resolution order', () {
    test('desktop uses the override when set', () {
      expect(
        resolveConfigPath(appPrivateOnly: false, override: '/etc/rclone.conf'),
        '/etc/rclone.conf',
      );
    });

    test('desktop with no override → null (rclone default)', () {
      expect(resolveConfigPath(appPrivateOnly: false, override: null), isNull);
    });

    test('desktop treats an empty override as unset → null', () {
      expect(resolveConfigPath(appPrivateOnly: false, override: ''), isNull);
    });

    test('desktop preserves a path containing spaces verbatim', () {
      const p = r'C:/Users/Jo Smith/rclone.conf';
      expect(resolveConfigPath(appPrivateOnly: false, override: p), p);
    });

    test('android always uses its app-private path, ignoring the override', () {
      expect(
        resolveConfigPath(
          appPrivateOnly: true,
          appPrivateConfigPath: '/data/app/rclone.conf',
          override: '/sdcard/other.conf',
        ),
        '/data/app/rclone.conf',
      );
    });

    test('android with an unknown app-private path → null', () {
      expect(
        resolveConfigPath(appPrivateOnly: true, appPrivateConfigPath: null),
        isNull,
      );
    });
  });

  group('configDumpArgs — validation argv builder', () {
    test('builds `config dump --config <path>` as discrete argv elements', () {
      expect(configDumpArgs('/home/me/rclone.conf'), [
        'config',
        'dump',
        '--config',
        '/home/me/rclone.conf',
      ]);
    });

    test('a path with spaces stays ONE argv element (no shell splitting)', () {
      const p = r'C:\Users\Jo Smith\rclone.conf';
      final args = configDumpArgs(p);
      expect(args.length, 4);
      expect(args.last, p);
    });
  });

  group('SettingsState.copyWith — nullable override semantics', () {
    test('omitting the argument preserves the current override', () {
      const s = SettingsState(configPathOverride: '/a/b.conf');
      // Changing an unrelated field must NOT wipe the override.
      expect(
        s.copyWith(themeMode: ThemeMode.dark).configPathOverride,
        '/a/b.conf',
      );
    });

    test('passing null explicitly clears the override', () {
      const s = SettingsState(configPathOverride: '/a/b.conf');
      expect(s.copyWith(configPathOverride: null).configPathOverride, isNull);
    });
  });

  group('configPathOverride — persistence round-trip', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to null and persists a set value across containers', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Let the fire-and-forget hydration finish before mutating, so its (empty)
      // disk read can't race-clobber the value we set next.
      await c.read(settingsControllerProvider.notifier).ensureLoaded();
      expect(c.read(settingsControllerProvider).configPathOverride, isNull);

      await c
          .read(settingsControllerProvider.notifier)
          .setConfigPathOverride('/tmp/custom.conf');
      expect(
        c.read(settingsControllerProvider).configPathOverride,
        '/tmp/custom.conf',
      );

      // A fresh container hydrates the persisted value from disk.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      await c2.read(settingsControllerProvider.notifier).ensureLoaded();
      expect(
        c2.read(settingsControllerProvider).configPathOverride,
        '/tmp/custom.conf',
      );
    });

    test('clearing (null) removes the key → reloads as null', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(settingsControllerProvider.notifier).ensureLoaded();
      // Establish a stored override, then clear it.
      await c
          .read(settingsControllerProvider.notifier)
          .setConfigPathOverride('/tmp/old.conf');
      expect(
        c.read(settingsControllerProvider).configPathOverride,
        '/tmp/old.conf',
      );

      await c
          .read(settingsControllerProvider.notifier)
          .setConfigPathOverride(null);
      expect(c.read(settingsControllerProvider).configPathOverride, isNull);

      // Persisted removal survives a reload (a fresh container reads null).
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      await c2.read(settingsControllerProvider.notifier).ensureLoaded();
      expect(c2.read(settingsControllerProvider).configPathOverride, isNull);
    });

    test('an empty string is treated as a clear, not a stored value', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(settingsControllerProvider.notifier).ensureLoaded();
      await c
          .read(settingsControllerProvider.notifier)
          .setConfigPathOverride('');
      expect(c.read(settingsControllerProvider).configPathOverride, isNull);

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      await c2.read(settingsControllerProvider.notifier).ensureLoaded();
      expect(c2.read(settingsControllerProvider).configPathOverride, isNull);
    });
  });
}
