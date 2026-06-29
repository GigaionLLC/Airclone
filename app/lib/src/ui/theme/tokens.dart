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

  /// Windows 11 File Explorer palette — neutral grays + the Windows blue accent.
  static const windowsLight = AircloneColors(
    surface: Color(0xFFF3F3F3),
    surfaceRaised: Color(0xFFFBFBFB),
    surfaceSunken: Color(0xFFEAEAEA),
    border: Color(0xFFE2E2E2),
    borderStrong: Color(0xFFCCCCCC),
    text: Color(0xFF1B1B1B),
    textMuted: Color(0xFF5A5A5A),
    textFaint: Color(0xFF8A8A8A),
    primary: Color(0xFF005FB8),
    primaryHover: Color(0xFF0078D4),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF005FB8),
    success: Color(0xFF0F7B0F),
    successBg: Color(0xFFE3F2E3),
    warning: Color(0xFF9D5D00),
    warningBg: Color(0xFFFBF0E1),
    error: Color(0xFFC42B1C),
    errorBg: Color(0xFFFDE7E9),
    info: Color(0xFF005FB8),
  );

  static const windowsDark = AircloneColors(
    surface: Color(0xFF202020),
    surfaceRaised: Color(0xFF2B2B2B),
    surfaceSunken: Color(0xFF303030),
    border: Color(0xFF393939),
    borderStrong: Color(0xFF4A4A4A),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFFC8C8C8),
    textFaint: Color(0xFF919191),
    primary: Color(0xFF4CC2FF),
    primaryHover: Color(0xFF6FD0FF),
    onPrimary: Color(0xFF00344D),
    secondary: Color(0xFF4CC2FF),
    success: Color(0xFF6CCB5F),
    successBg: Color(0xFF11301B),
    warning: Color(0xFFFCE100),
    warningBg: Color(0xFF3A3416),
    error: Color(0xFFFF99A4),
    errorBg: Color(0xFF442726),
    info: Color(0xFF4CC2FF),
  );

  /// The palette for a given [skin] + [brightness]. Skins without a dedicated
  /// palette fall back to the default Airclone look.
  static AircloneColors forSkin(Skin skin, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (skin) {
      Skin.windows => dark ? windowsDark : windowsLight,
      _ => dark ? AircloneColors.dark : AircloneColors.light,
    };
  }

  /// Interpolates every channel — used by [AircloneTheme.lerp] so theme/skin
  /// switches animate smoothly instead of snapping.
  static AircloneColors lerp(AircloneColors a, AircloneColors b, double t) =>
      AircloneColors(
        surface: Color.lerp(a.surface, b.surface, t)!,
        surfaceRaised: Color.lerp(a.surfaceRaised, b.surfaceRaised, t)!,
        surfaceSunken: Color.lerp(a.surfaceSunken, b.surfaceSunken, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        borderStrong: Color.lerp(a.borderStrong, b.borderStrong, t)!,
        text: Color.lerp(a.text, b.text, t)!,
        textMuted: Color.lerp(a.textMuted, b.textMuted, t)!,
        textFaint: Color.lerp(a.textFaint, b.textFaint, t)!,
        primary: Color.lerp(a.primary, b.primary, t)!,
        primaryHover: Color.lerp(a.primaryHover, b.primaryHover, t)!,
        onPrimary: Color.lerp(a.onPrimary, b.onPrimary, t)!,
        secondary: Color.lerp(a.secondary, b.secondary, t)!,
        success: Color.lerp(a.success, b.success, t)!,
        successBg: Color.lerp(a.successBg, b.successBg, t)!,
        warning: Color.lerp(a.warning, b.warning, t)!,
        warningBg: Color.lerp(a.warningBg, b.warningBg, t)!,
        error: Color.lerp(a.error, b.error, t)!,
        errorBg: Color.lerp(a.errorBg, b.errorBg, t)!,
        info: Color.lerp(a.info, b.info, t)!,
      );
}

/// A visual "skin". [Skin.airclone] is the default brand look; the others are
/// optional, opt-in approximations of each OS's native file manager.
enum Skin {
  airclone,
  windows,
  macos,
  gnome;

  String get label => switch (this) {
    Skin.airclone => 'Airclone',
    Skin.windows => 'Windows Explorer',
    Skin.macos => 'macOS Finder',
    Skin.gnome => 'Linux (GNOME)',
  };
}

/// Per-skin visual axes that the file managers actually differ on (typography,
/// density). Folded into [AircloneTheme]; the default [SkinTokens.airclone]
/// reproduces today's exact look. The OS variants are starting points, refined
/// when each skin is built out.
@immutable
class SkinTokens {
  const SkinTokens({
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.bodySize,
    required this.rowHeight,
    required this.density,
    required this.selectionRadius,
    required this.rowDividers,
  });

  /// Primary UI font (falls back through [fontFamilyFallback] when absent).
  final String fontFamily;
  final List<String> fontFamilyFallback;

  /// List/Details body text size.
  final double bodySize;

  /// Details-row height.
  final double rowHeight;

  final VisualDensity density;

  /// Corner radius of the row selection/hover highlight (0 = square).
  final double selectionRadius;

  /// Whether Details rows are separated by a thin divider line. When false
  /// (Explorer/Finder style) the selection + hover are rounded fills instead.
  final bool rowDividers;

  static SkinTokens of(Skin skin) => switch (skin) {
    Skin.airclone => airclone,
    Skin.windows => windows,
    Skin.macos => macos,
    Skin.gnome => gnome,
  };

  /// Discrete axes (font family) can't interpolate, so snap at the midpoint.
  static SkinTokens lerp(SkinTokens a, SkinTokens b, double t) =>
      t < 0.5 ? a : b;

  static const airclone = SkinTokens(
    fontFamily: 'Segoe UI',
    fontFamilyFallback: ['Segoe UI', 'Inter', 'Roboto'],
    bodySize: 13,
    rowHeight: 36,
    density: VisualDensity.standard,
    selectionRadius: 0,
    rowDividers: true,
  );

  static const windows = SkinTokens(
    fontFamily: 'Segoe UI Variable Text',
    fontFamilyFallback: ['Segoe UI Variable Text', 'Segoe UI', 'Inter'],
    bodySize: 13,
    rowHeight: 28,
    density: VisualDensity.compact,
    selectionRadius: 4,
    rowDividers: false,
  );

  static const macos = SkinTokens(
    fontFamily: 'SF Pro Text',
    fontFamilyFallback: [
      'SF Pro Text',
      '.AppleSystemUIFont',
      'Helvetica Neue',
      'Inter',
    ],
    bodySize: 13,
    rowHeight: 24,
    density: VisualDensity.compact,
    selectionRadius: 6,
    rowDividers: true,
  );

  static const gnome = SkinTokens(
    fontFamily: 'Adwaita Sans',
    fontFamilyFallback: ['Adwaita Sans', 'Cantarell', 'Inter', 'Roboto'],
    bodySize: 14,
    rowHeight: 38,
    density: VisualDensity.standard,
    selectionRadius: 8,
    rowDividers: true,
  );
}

/// Exposes [AircloneColors] + the active skin's [SkinTokens] through the widget
/// tree via `Theme.of`.
@immutable
class AircloneTheme extends ThemeExtension<AircloneTheme> {
  const AircloneTheme({
    required this.colors,
    this.tokens = SkinTokens.airclone,
  });
  final AircloneColors colors;
  final SkinTokens tokens;

  /// The semantic palette (the common lookup — most widgets use `c.primary`).
  static AircloneColors of(BuildContext context) =>
      Theme.of(context).extension<AircloneTheme>()!.colors;

  /// The active skin's layout/typography tokens.
  static SkinTokens tokensOf(BuildContext context) =>
      Theme.of(context).extension<AircloneTheme>()!.tokens;

  @override
  AircloneTheme copyWith({AircloneColors? colors, SkinTokens? tokens}) =>
      AircloneTheme(
        colors: colors ?? this.colors,
        tokens: tokens ?? this.tokens,
      );

  @override
  AircloneTheme lerp(ThemeExtension<AircloneTheme>? other, double t) {
    if (other is! AircloneTheme) return this;
    return AircloneTheme(
      colors: AircloneColors.lerp(colors, other.colors, t),
      tokens: SkinTokens.lerp(tokens, other.tokens, t),
    );
  }
}
