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

  test('each skin maps to its own palette; Airclone is the fallback', () {
    expect(
      AircloneColors.forSkin(Skin.windows, Brightness.dark),
      AircloneColors.windowsDark,
    );
    expect(
      AircloneColors.forSkin(Skin.macos, Brightness.dark),
      AircloneColors.macosDark,
    );
    expect(
      AircloneColors.forSkin(Skin.macos, Brightness.light),
      AircloneColors.macosLight,
    );
    expect(
      AircloneColors.forSkin(Skin.gnome, Brightness.dark),
      AircloneColors.gnomeDark,
    );
    expect(
      AircloneColors.forSkin(Skin.gnome, Brightness.light),
      AircloneColors.gnomeLight,
    );
    expect(
      AircloneColors.forSkin(Skin.airclone, Brightness.dark),
      AircloneColors.dark,
    );
    // Each OS palette really differs from the default.
    for (final s in [Skin.windows, Skin.macos, Skin.gnome]) {
      expect(
        AircloneColors.forSkin(s, Brightness.dark).surface,
        isNot(AircloneColors.dark.surface),
        reason: '$s should have its own surface',
      );
    }
  });

  test('SkinChrome.of returns the right delegate; Airclone is unchanged', () {
    // Airclone default keeps its exact look.
    const a = SkinChrome.airclone;
    expect(a.sidebarSelection, SidebarSelection.leftAccentBar);
    expect(a.sectionHeaderStyle, SectionHeaderStyle.caps);
    expect(a.tileShowsSubtitle, isTrue);
    expect(a.colouredFolderIcons, isFalse);
    expect(SkinChrome.of(Skin.airclone), same(a));
    // Finder: accent-fill pill selection; Explorer: rounded pill + coloured icons.
    expect(
      SkinChrome.of(Skin.macos).sidebarSelection,
      SidebarSelection.accentFillPill,
    );
    expect(
      SkinChrome.of(Skin.windows).sidebarSelection,
      SidebarSelection.roundedPill,
    );
    expect(SkinChrome.of(Skin.windows).colouredFolderIcons, isTrue);
    expect(SkinChrome.of(Skin.gnome).colouredFolderIcons, isFalse);
    // OS skins drop the rclone-type subtitle + use Title Case headers.
    for (final s in [Skin.windows, Skin.macos, Skin.gnome]) {
      expect(SkinChrome.of(s).tileShowsSubtitle, isFalse, reason: '$s');
      expect(
        SkinChrome.of(s).sectionHeaderStyle,
        SectionHeaderStyle.titleCase,
        reason: '$s',
      );
    }
    // The theme carries the chrome.
    expect(
      AppTheme.build(
        Skin.macos,
        Brightness.dark,
      ).extension<AircloneTheme>()!.chrome,
      SkinChrome.macos,
    );
  });

  test('OS skins render dividerless rounded rows; Airclone keeps dividers', () {
    expect(SkinTokens.airclone.rowDividers, isTrue);
    for (final s in [Skin.windows, Skin.macos, Skin.gnome]) {
      expect(SkinTokens.of(s).rowDividers, isFalse, reason: '$s');
    }
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
