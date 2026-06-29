import 'package:flutter/material.dart';
import 'tokens.dart';

/// Builds [ThemeData] for a [Skin] × light/dark from the Airclone design tokens.
abstract final class AppTheme {
  /// Default (Airclone) skin — kept for call sites/tests that don't pick a skin.
  static ThemeData light() => build(Skin.airclone, Brightness.light);
  static ThemeData dark() => build(Skin.airclone, Brightness.dark);

  static ThemeData build(Skin skin, Brightness brightness) {
    final c = AircloneColors.forSkin(skin, brightness);
    final t = SkinTokens.of(skin);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.secondary,
      onSecondary: c.onPrimary,
      error: c.error,
      onError: c.onPrimary,
      surface: c.surface,
      onSurface: c.text,
    );

    final typography = Typography.material2021(
      platform: TargetPlatform.windows,
    );
    final baseText = brightness == Brightness.dark
        ? typography.white
        : typography.black;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.surface,
      fontFamily: t.fontFamily,
      fontFamilyFallback: t.fontFamilyFallback,
      visualDensity: t.density,
      dividerColor: c.border,
      extensions: [
        AircloneTheme(colors: c, tokens: t, chrome: SkinChrome.of(skin)),
      ],
      textTheme: baseText.apply(bodyColor: c.text, displayColor: c.text),
    );
  }
}
