import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sentinel distinguishing "argument omitted" from "explicitly passed null" in
/// [SettingsState.copyWith], so the nullable [SettingsState.configPathOverride]
/// can be CLEARED back to the rclone default (pass null) without every other
/// `copyWith` call accidentally wiping it (omit the argument → keep current).
/// `Object()`'s default constructor is const, so this is a compile-time value.
const Object _kUnset = Object();

/// Persisted user preferences: the app theme mode, an optional override for the
/// rclone engine binary path, and an optional override for the rclone *config
/// file* path. Backed by `shared_preferences`.
@immutable
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.rclonePathOverride = '',
    this.configPathOverride,
  });

  /// Which Material theme to apply (system / light / dark).
  final ThemeMode themeMode;

  /// Optional absolute path to an rclone binary, overriding auto-discovery.
  /// Empty when unset.
  final String rclonePathOverride;

  /// Optional absolute path to an rclone **config file**, overriding rclone's
  /// default location (Settings → Config → "Use a different config file…").
  /// Null means "use rclone's own default" on desktop (and the app-private
  /// config on Android). The engine spawns with `--config <override>` when set —
  /// see [resolveConfigPath] / `EngineController._platformSetup`.
  final String? configPathOverride;

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? rclonePathOverride,
    Object? configPathOverride = _kUnset,
  }) => SettingsState(
    themeMode: themeMode ?? this.themeMode,
    rclonePathOverride: rclonePathOverride ?? this.rclonePathOverride,
    configPathOverride: identical(configPathOverride, _kUnset)
        ? this.configPathOverride
        : configPathOverride as String?,
  );
}

/// SharedPreferences keys.
const _kThemeMode = 'themeMode';
const _kRclonePath = 'rclonePath';
const _kConfigPath = 'configPath';

/// Owns the user's settings: returns defaults synchronously, then hydrates from
/// disk and persists every change. The shell watches [themeMode] for the
/// `MaterialApp`.
class SettingsController extends Notifier<SettingsState> {
  /// The single in-flight/completed hydration future, cached so [ensureLoaded]
  /// is idempotent — every caller awaits the SAME disk read rather than racing
  /// the synchronous defaults returned by [build].
  Future<void>? _loading;

  @override
  SettingsState build() {
    // Load persisted values without blocking the first frame.
    ensureLoaded();
    return const SettingsState();
  }

  /// Awaitable hydration: completes once [state] reflects the persisted values.
  /// [build] returns defaults synchronously and fills from disk on a later
  /// microtask, so any consumer that makes a start-time decision on a persisted
  /// value — notably `EngineController._platformSetup` reading
  /// [SettingsState.configPathOverride] to pick the engine's `--config` — must
  /// `await` this first, or a cold-start bootstrap would spawn against the
  /// DEFAULT config while the override is still loading. Idempotent: [_load] is
  /// kicked off once in [build].
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = _themeModeFromName(prefs.getString(_kThemeMode));
    final path = prefs.getString(_kRclonePath) ?? '';
    // Absent key → null → clears the override (via the copyWith sentinel).
    final configPath = prefs.getString(_kConfigPath);
    state = state.copyWith(
      themeMode: mode,
      rclonePathOverride: path,
      configPathOverride: configPath,
    );
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

  /// Persist the rclone config-file override. A null or empty [path] clears it
  /// (the key is removed, so a reload resolves back to null = rclone default),
  /// mirroring the remembered-download-folder handling in download_settings.dart.
  Future<void> setConfigPathOverride(String? path) async {
    final v = (path == null || path.isEmpty) ? null : path;
    state = state.copyWith(configPathOverride: v);
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_kConfigPath);
    } else {
      await prefs.setString(_kConfigPath, v);
    }
  }

  static ThemeMode _themeModeFromName(String? name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
