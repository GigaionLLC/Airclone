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

/// The language the player should prefer for audio or subtitles, remembered
/// from the last pick (player format plan, Q4).
///
/// Global, not per file: "I watch films in English with German subtitles" is a
/// fact about the person, and it is what makes the NEXT file open right. Null
/// means no preference — libmpv's own default/forced-track choice stands.
/// Stored as ISO 639-2/B (`ger`, see `canonicalLanguage`), or `off` for
/// subtitles the person switched off.
///
/// Applied to libmpv as `alang` / `slang` (and `sid=no` for `off`) before a
/// file opens — see `MediaPreviewBody`.
abstract class _PreferredLanguage extends Notifier<String?> {
  String get _key;

  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      if (v != null && v.isNotEmpty) state = v;
    } catch (_) {
      // keep the default
    }
  }

  /// Remembers [value]; null forgets the preference.
  Future<void> set(String? value) async {
    final v = value?.trim().toLowerCase();
    final next = v == null || v.isEmpty ? null : v;
    if (next == state) return;
    state = next;
    try {
      final p = await SharedPreferences.getInstance();
      if (next == null) {
        await p.remove(_key);
      } else {
        await p.setString(_key, next);
      }
    } catch (_) {
      // best-effort
    }
  }
}

class PreferredAudioLanguage extends _PreferredLanguage {
  @override
  String get _key => 'media_audio_language';
}

class PreferredSubtitleLanguage extends _PreferredLanguage {
  @override
  String get _key => 'media_subtitle_language';
}

/// See [_PreferredLanguage]. Never `off`: there is no "no audio" pick.
final preferredAudioLanguageProvider =
    NotifierProvider<PreferredAudioLanguage, String?>(
      PreferredAudioLanguage.new,
    );

/// See [_PreferredLanguage]. `off` when the person switched subtitles off.
final preferredSubtitleLanguageProvider =
    NotifierProvider<PreferredSubtitleLanguage, String?>(
      PreferredSubtitleLanguage.new,
    );
