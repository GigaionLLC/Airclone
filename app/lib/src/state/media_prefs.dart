import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences for the in-app media player (see `ui/media_preview.dart`).

/// Whether a previewed video/audio file restarts when it reaches the end.
///
/// Persisted, and deliberately app-wide rather than per-file: it is a "how I
/// like my player to behave" choice, like a music app's loop button, so the
/// next preview honours what you set on the last one. Off by default —
/// a preview that silently restarts forever would be a surprise.
class RepeatPlayback extends Notifier<bool> {
  static const _key = 'media_repeat';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(_key);
      if (v != null) state = v;
    } catch (_) {
      // keep the default
    }
  }

  Future<void> set(bool value) async {
    if (value == state) return;
    state = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, value);
    } catch (_) {
      // best-effort
    }
  }

  Future<void> toggle() => set(!state);
}

/// Whether media previews repeat on reaching the end, persisted across
/// launches.
final repeatPlaybackProvider = NotifierProvider<RepeatPlayback, bool>(
  RepeatPlayback.new,
);
