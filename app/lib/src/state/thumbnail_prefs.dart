import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/remote.dart';

const String _prefsKey = 'thumb_disabled';

/// Per-remote thumbnail **opt-out** (by `fs`), persisted to SharedPreferences.
/// Thumbnails are ON by default everywhere; a remote is in this set only if the
/// user has disabled previews for it (e.g. a metered cloud backend).
class ThumbnailPrefs extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return <String>{};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        state = decoded.whereType<String>().toSet();
      }
    } catch (_) {
      // leave state as-is on failure
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(state.toList()));
    } catch (_) {
      // best-effort persistence
    }
  }

  /// Enable/disable thumbnails for remote [fs], then persist.
  Future<void> toggle(String fs) async {
    final next = Set<String>.of(state);
    if (next.contains(fs)) {
      next.remove(fs);
    } else {
      next.add(fs);
    }
    state = next;
    await _persist();
  }

  bool isDisabled(String fs) => state.contains(fs);
}

/// The set of remote `fs` strings with thumbnails **disabled** (default: none).
final thumbnailsDisabledProvider =
    NotifierProvider<ThumbnailPrefs, Set<String>>(ThumbnailPrefs.new);

/// Whether thumbnails should be generated for [remote], given the [disabled] set.
/// Local folders are always on (no bandwidth cost); cloud remotes are on unless
/// the user has opted out.
bool thumbnailsOn(Remote remote, Set<String> disabled) =>
    remote.isLocal || !disabled.contains(remote.fs);
