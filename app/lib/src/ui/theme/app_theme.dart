import 'package:flutter/material.dart';
import 'tokens.dart';

/// Builds [ThemeData] for light/dark from the Airclone design tokens.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, AircloneColors.light);
  static ThemeData dark() => _build(Brightness.dark, AircloneColors.dark);

  static ThemeData _build(Brightness brightness, AircloneColors c) {
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
      fontFamily: 'Segoe UI',
      dividerColor: c.border,
      extensions: [AircloneTheme(colors: c)],
      textTheme: baseText.apply(bodyColor: c.text, displayColor: c.text),
    );
  }
}
