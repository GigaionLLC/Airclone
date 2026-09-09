import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which mount point each remote path was last pinned to, so a remote that
/// belongs on `K:` lands on `K:` every time.
///
/// rclone's `*` picks the next free letter, which is right for a one-off and
/// wrong for a drive you have shortcuts, scripts or muscle memory pointed at:
/// mount two remotes in a different order and yesterday's `K:` is today's `L:`.
///
/// Keyed by the full fs (`gdrive:` or `gdrive:work`), not the remote name, so
/// two folders of one remote can hold different letters instead of fighting
/// over one. Opt-in per mount — an unticked box removes any stored pin rather
/// than leaving a stale one behind.
///
/// Stored as one JSON object for the same reason [MountDefaults] is: adding a
/// key later needs no migration.
class MountLetters extends Notifier<Map<String, String>> {
  static const _key = 'mount_letters_v1';

  @override
  Map<String, String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        state = {
          for (final e in decoded.entries)
            if (e.value is String) '${e.key}': e.value as String,
        };
      }
    } catch (_) {
      // Unreadable preferences just mean no pins; mounting still works.
    }
  }

  /// The pinned mount point for [fs], or null when it has none.
  String? forFs(String fs) => state[fs];

  /// Pin [fs] to [mountPoint]. A `*` is not a pin — it is the absence of one —
  /// so it forgets instead, which is what makes the checkbox's two states
  /// symmetric.
  Future<void> remember(String fs, String mountPoint) async {
    if (mountPoint.isEmpty || mountPoint == '*') return forget(fs);
    if (state[fs] == mountPoint) return;
    state = {...state, fs: mountPoint};
    await _persist();
  }

  Future<void> forget(String fs) async {
    if (!state.containsKey(fs)) return;
    state = {...state}..remove(fs);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state));
    } catch (_) {
      // Best-effort: the pin still applies for this session.
    }
  }
}

final mountLettersProvider =
    NotifierProvider<MountLetters, Map<String, String>>(MountLetters.new);
