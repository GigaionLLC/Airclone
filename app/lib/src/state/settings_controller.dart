import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted user preferences: the app theme mode and an optional override for
/// the rclone engine binary path. Backed by `shared_preferences`.
@immutable
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.rclonePathOverride = '',
  });

  /// Which Material theme to apply (system / light / dark).
  final ThemeMode themeMode;

  /// Optional absolute path to an rclone binary, overriding auto-discovery.
  /// Empty when unset.
  final String rclonePathOverride;

  SettingsState copyWith({ThemeMode? themeMode, String? rclonePathOverride}) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        rclonePathOverride: rclonePathOverride ?? this.rclonePathOverride,
      );
}

/// SharedPreferences keys.
const _kThemeMode = 'themeMode';
const _kRclonePath = 'rclonePath';

/// Owns the user's settings: returns defaults synchronously, then hydrates from
/// disk and persists every change. The shell watches [themeMode] for the
/// `MaterialApp`.
class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    // Load persisted values without blocking the first frame.
    _load();
    return const SettingsState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = _themeModeFromName(prefs.getString(_kThemeMode));
    final path = prefs.getString(_kRclonePath) ?? '';
    state = state.copyWith(themeMode: mode, rclonePathOverride: path);
  }

  /// Persist and apply the chosen theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  /// Persist the rclone path override (empty string clears it).
  Future<void> setRclonePath(String path) async {
    state = state.copyWith(rclonePathOverride: path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRclonePath, path);
  }

  static ThemeMode _themeModeFromName(String? name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
