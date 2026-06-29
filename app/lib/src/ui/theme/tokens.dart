import 'package:flutter/material.dart';

/// Design tokens — the single source of truth for spacing, radius, and color.
/// Mirrors `wiki/core/06-design-system.md`. UI must reference these, never raw hex.

/// 4px-base spacing scale.
abstract final class Space {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 24;
  static const double x6 = 32;
  static const double x8 = 48;
}

/// Corner radii.
abstract final class Radii {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double full = 999;
}

/// Semantic color palette. Two instances: [AircloneColors.light] / `.dark`.
@immutable
class AircloneColors {
  const AircloneColors({
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.primary,
    required this.primaryHover,
    required this.onPrimary,
    required this.secondary,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.error,
    required this.errorBg,
    required this.info,
  });

  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color primary;
  final Color primaryHover;
  final Color onPrimary;
  final Color secondary;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color error;
  final Color errorBg;
  final Color info;

  static const light = AircloneColors(
    surface: Color(0xFFF7F8FA),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEDEFF3),
    border: Color(0xFFE2E5EB),
    borderStrong: Color(0xFFC4C9D4),
    text: Color(0xFF1A1D23),
    textMuted: Color(0xFF5C6470),
    textFaint: Color(0xFF8A929E),
    primary: Color(0xFF2F7DF6),
    primaryHover: Color(0xFF1F6AE0),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF7C5CFC),
    success: Color(0xFF1FA672),
    successBg: Color(0xFFE4F7EF),
    warning: Color(0xFFD9882B),
    warningBg: Color(0xFFFBF0E1),
    error: Color(0xFFE14B4B),
    errorBg: Color(0xFFFBE6E6),
    info: Color(0xFF3B82C4),
  );

  static const dark = AircloneColors(
    surface: Color(0xFF16181D),
    surfaceRaised: Color(0xFF1F2229),
    surfaceSunken: Color(0xFF101216),
    border: Color(0xFF2C313B),
    borderStrong: Color(0xFF3C434F),
    text: Color(0xFFECEEF2),
    textMuted: Color(0xFF9AA2AF),
    textFaint: Color(0xFF6B7280),
    primary: Color(0xFF5C9CFF),
    primaryHover: Color(0xFF7AB0FF),
    onPrimary: Color(0xFF0B1220),
    secondary: Color(0xFFA48BFF),
    success: Color(0xFF3FD49A),
    successBg: Color(0xFF10322A),
    warning: Color(0xFFF0B45E),
    warningBg: Color(0xFF3A2C14),
    error: Color(0xFFFF6B6B),
    errorBg: Color(0xFF3A1A1A),
    info: Color(0xFF6BA6E0),
  );
}

/// Exposes [AircloneColors] through the widget tree via `Theme.of`.
@immutable
class AircloneTheme extends ThemeExtension<AircloneTheme> {
  const AircloneTheme({required this.colors});
  final AircloneColors colors;

  static AircloneColors of(BuildContext context) =>
      Theme.of(context).extension<AircloneTheme>()!.colors;

  @override
  AircloneTheme copyWith({AircloneColors? colors}) =>
      AircloneTheme(colors: colors ?? this.colors);

  @override
  AircloneTheme lerp(ThemeExtension<AircloneTheme>? other, double t) => this;
}
