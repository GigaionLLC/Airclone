import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/mount_options.dart';

/// The [MountOptions] a NEW mount starts from, persisted across launches.
///
/// Two levels on purpose, and only two: this is the default, and the mount
/// dialog edits a transient copy of it for one mount. Nothing here is written
/// back from the dialog — a per-mount tweak must not silently redefine the
/// default, and a changed default must not reach into a mount that is already
/// running (rclone fixes a VFS's options at mount time; there is no RC to
/// change them afterwards). The Settings copy says so out loud.
///
/// Stored as ONE JSON string rather than nine keys, so adding an option later
/// needs no migration: [MountOptions.fromJson] fills anything absent from the
/// shipped defaults.
class MountDefaults extends Notifier<MountOptions> {
  static const _key = 'mount_options_defaults';

  @override
  MountOptions build() {
    _load();
    return MountOptions.defaults;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        state = MountOptions.fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {
      // Unreadable or malformed preferences keep the shipped defaults. The
      // mount dialog opening is worth more than a remembered setting.
    }
  }

  Future<void> set(MountOptions next) async {
    if (next == state) return;
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(next.toJson()));
    } catch (_) {
      // Best-effort: the in-memory value still applies for this session.
    }
  }

  /// Back to what Airclone ships, and forget the stored override entirely so a
  /// later change to the shipped defaults reaches this user.
  Future<void> reset() async {
    state = MountOptions.defaults;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      /* best effort */
    }
  }
}

final mountDefaultsProvider = NotifierProvider<MountDefaults, MountOptions>(
  MountDefaults.new,
);
