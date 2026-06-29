import 'package:airclone/src/state/skin.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default skin is Airclone and reproduces today\'s look', () {
    final t = AppTheme.build(Skin.airclone, Brightness.light);
    expect(t.textTheme.bodyMedium, isNotNull);
    final ext = t.extension<AircloneTheme>()!;
    expect(ext.tokens.fontFamily, 'Segoe UI');
    expect(ext.tokens.rowHeight, 36);
    expect(ext.colors.primary, AircloneColors.light.primary);
  });

  test('SkinTokens.of returns the right bundle per skin', () {
    expect(SkinTokens.of(Skin.airclone).rowHeight, 36);
    expect(SkinTokens.of(Skin.windows).rowHeight, 28);
    expect(SkinTokens.of(Skin.macos).rowHeight, 24);
    expect(SkinTokens.of(Skin.gnome).bodySize, 14);
  });

  test('AircloneTheme.lerp actually interpolates colors (not a no-op)', () {
    const a = AircloneTheme(colors: AircloneColors.light);
    const b = AircloneTheme(colors: AircloneColors.dark);
    final mid = a.lerp(b, 0.5);
    expect(
      mid.colors.surface,
      Color.lerp(
        AircloneColors.light.surface,
        AircloneColors.dark.surface,
        0.5,
      ),
    );
    expect(mid.colors.surface, isNot(AircloneColors.light.surface));
  });

  test('skinProvider persists + round-trips, defaulting to Airclone', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(skinProvider), Skin.airclone);
    await c.read(skinProvider.notifier).set(Skin.windows);
    expect(c.read(skinProvider), Skin.windows);

    // A fresh container loads the persisted value.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(skinProvider); // trigger build + async load
    await Future<void>.delayed(Duration.zero);
    expect(c2.read(skinProvider), Skin.windows);
  });

  test('skin labels are human-readable', () {
    expect(Skin.airclone.label, 'Airclone');
    expect(Skin.windows.label, 'Windows Explorer');
  });
}
