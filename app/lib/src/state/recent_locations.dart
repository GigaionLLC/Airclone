import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';

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
  List<RecentLocation> build() => const [];

  /// Push [remote]+[path] to the front (removing any prior entry for it).
  void record(Remote remote, String path) {
    final loc = RecentLocation(remote: remote, path: path);
    final next = [loc, ...state.where((l) => l.key != loc.key)];
    state = next.length > _cap ? next.sublist(0, _cap) : next;
  }
}

final recentLocationsProvider =
    NotifierProvider<RecentLocations, List<RecentLocation>>(
      RecentLocations.new,
    );
