import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/remote.dart';

/// Whether visited folders are remembered at all. **Off by default.**
///
/// A trail of where you have been is a convenience for some people and a
/// surprise for others — it puts remote and folder names on the Home screen
/// where anyone glancing at the window can read them, and nobody asked for it.
/// A history feature nobody opted into is the kind that should be opt-in, so
/// this is the switch and the default is no.
///
/// Persisted (unlike the trail itself, which is session-only): the choice must
/// survive a restart, while the list deliberately does not.
class RecentsEnabled extends Notifier<bool> {
  static const _key = 'recents_enabled';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getBool(_key) ?? false;
    } catch (_) {
      // keep the private default
    }
  }

  Future<void> set(bool v) async {
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {
      // best-effort
    }
  }
}

final recentsEnabledProvider = NotifierProvider<RecentsEnabled, bool>(
  RecentsEnabled.new,
);

/// A place the user has visited this session: a remote + folder path.
@immutable
class RecentLocation {
  const RecentLocation({required this.remote, required this.path});

  final Remote remote;
  final String path;

  /// Same `fs|path` shape as [Bookmark.key], so recents can be de-duplicated
  /// against pinned favorites in the command palette.
  String get key => '${remote.fs}|$path';

  /// e.g. `gdrive/Work/Q1` (or just `gdrive` at the root).
  String get label => path.isEmpty ? remote.name : '${remote.name}/$path';
}

/// Most-recently-visited folders, newest first, capped and de-duplicated by
/// [RecentLocation.key]. Session-only (not persisted) — it changes on every
/// navigation, so disk churn isn't worth it.
class RecentLocations extends Notifier<List<RecentLocation>> {
  static const _cap = 12;

  @override
  List<RecentLocation> build() {
    // Turning the setting off must also DROP what was already collected —
    // otherwise the trail the user just opted out of stays on the Home screen
    // until the app restarts, which is the opposite of what they asked for.
    ref.listen(recentsEnabledProvider, (_, on) {
      if (!on) state = const [];
    });
    return const [];
  }

  /// Push [remote]+[path] to the front (removing any prior entry for it).
  /// A no-op while [recentsEnabledProvider] is off — nothing is collected and
  /// then filtered later; it is never collected at all.
  void record(Remote remote, String path) {
    if (!ref.read(recentsEnabledProvider)) return;
    final loc = RecentLocation(remote: remote, path: path);
    final next = [loc, ...state.where((l) => l.key != loc.key)];
    state = next.length > _cap ? next.sublist(0, _cap) : next;
  }
}

final recentLocationsProvider =
    NotifierProvider<RecentLocations, List<RecentLocation>>(
      RecentLocations.new,
    );
