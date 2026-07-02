import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/remote.dart';

/// What a [LocalLocation] represents — drives the sidebar icon. [folder] is a
/// user-added custom location.
enum LocalKind {
  home,
  desktop,
  documents,
  downloads,
  pictures,
  videos,
  music,
  drive,
  root,
  folder,
}

/// A local-filesystem shortcut surfaced in the sidebar. Browsing it uses rclone's
/// `local` backend (same list/copy/preview/thumbnail machinery as a cloud remote),
/// with [Remote.fs] rooted at the folder/drive.
@immutable
class LocalLocation {
  const LocalLocation({required this.remote, required this.kind});
  final Remote remote;
  final LocalKind kind;

  Map<String, dynamic> toJson() => {
    'name': remote.name,
    'fs': remote.fs,
    'kind': kind.name,
  };

  factory LocalLocation.fromJson(Map<String, dynamic> j) => LocalLocation(
    remote: Remote(
      name: (j['name'] ?? '') as String,
      type: 'local',
      fs: (j['fs'] ?? '') as String,
      isLocal: true,
    ),
    kind: LocalKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => LocalKind.folder,
    ),
  );
}

/// Forward-slashed root with a trailing slash — the shape rclone's local backend
/// expects as an `fs`.
String fsRoot(String path) {
  var p = path.replaceAll('\\', '/');
  if (!p.endsWith('/')) p = '$p/';
  return p;
}

String _basename(String path) {
  var s = path.replaceAll('\\', '/');
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  final i = s.lastIndexOf('/');
  final name = i >= 0 ? s.substring(i + 1) : s;
  return name.isEmpty ? path : name;
}

LocalLocation? _folder(String name, String path, LocalKind kind) {
  if (path.isEmpty || !Directory(path).existsSync()) return null;
  return LocalLocation(
    remote: Remote(name: name, type: 'local', fs: fsRoot(path), isLocal: true),
    kind: kind,
  );
}

/// Android's shared-storage root. Folders under it are only readable once the
/// user grants All Files Access (rclone's `local` backend uses real paths).
/// Resolved from Environment.getExternalStorageDirectory() at startup (see
/// initAndroidStorageRoot) — the default only holds for user 0; secondary
/// users / work profiles live under a different index.
String androidStorageRoot = '/storage/emulated/0';

/// The default set of user folders (Home + standard XDG-ish folders) for first run.
List<LocalLocation> buildDefaultUserFolders() {
  final out = <LocalLocation>[];

  if (Platform.isAndroid) {
    // Android's fixed shared-storage folder names (Download is singular).
    // No existsSync gate: these standard folders always exist, and a stat
    // before the storage permission is granted can lie — seeding must not
    // depend on grant order.
    void add(String name, String sub, LocalKind kind) {
      out.add(
        LocalLocation(
          remote: Remote(
            name: name,
            type: 'local',
            fs: fsRoot('$androidStorageRoot/$sub'),
            isLocal: true,
          ),
          kind: kind,
        ),
      );
    }

    add('Download', 'Download', LocalKind.downloads);
    add('Documents', 'Documents', LocalKind.documents);
    add('Pictures', 'Pictures', LocalKind.pictures);
    add('Camera (DCIM)', 'DCIM', LocalKind.pictures);
    add('Movies', 'Movies', LocalKind.videos);
    add('Music', 'Music', LocalKind.music);
    return out;
  }

  final env = Platform.environment;
  final home = (Platform.isWindows ? env['USERPROFILE'] : env['HOME']) ?? '';
  final sep = Platform.isWindows ? '\\' : '/';

  void add(String name, String sub, LocalKind kind) {
    final loc = _folder(name, sub.isEmpty ? home : '$home$sep$sub', kind);
    if (loc != null) out.add(loc);
  }

  add('Home', '', LocalKind.home);
  add('Desktop', 'Desktop', LocalKind.desktop);
  add('Documents', 'Documents', LocalKind.documents);
  add('Downloads', 'Downloads', LocalKind.downloads);
  add('Pictures', 'Pictures', LocalKind.pictures);
  add('Videos', 'Videos', LocalKind.videos);
  add('Music', 'Music', LocalKind.music);
  return out;
}

/// Auto-detected disk drives (Windows letters, or `/` on POSIX). Not editable.
final drivesProvider = Provider<List<LocalLocation>>((ref) {
  final out = <LocalLocation>[];
  if (Platform.isAndroid) {
    // The phone's shared storage. "/" exists but is mostly unreadable noise on
    // Android, so it is deliberately not offered.
    out.add(
      LocalLocation(
        remote: Remote(
          name: 'Internal storage',
          type: 'local',
          fs: '$androidStorageRoot/',
          isLocal: true,
        ),
        kind: LocalKind.drive,
      ),
    );
    return out;
  }
  if (Platform.isWindows) {
    for (var ch = 'C'.codeUnitAt(0); ch <= 'Z'.codeUnitAt(0); ch++) {
      final letter = String.fromCharCode(ch);
      final root = '$letter:/';
      if (Directory(root).existsSync()) {
        out.add(
          LocalLocation(
            remote: Remote(
              name: 'Disk ($letter:)',
              type: 'local',
              fs: root,
              isLocal: true,
            ),
            kind: LocalKind.drive,
          ),
        );
      }
    }
  } else {
    out.add(
      const LocalLocation(
        remote: Remote(name: 'Computer', type: 'local', fs: '/', isLocal: true),
        kind: LocalKind.root,
      ),
    );
  }
  return out;
});

/// The editable, persisted list of user folder Locations. Seeded with the defaults
/// on first run; the user can add (folder picker / drag-drop) or remove any.
class UserLocations extends Notifier<List<LocalLocation>> {
  static const _key = 'user_locations';

  @override
  List<LocalLocation> build() {
    _load();
    return buildDefaultUserFolders();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return; // first run — keep the seeded defaults
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(LocalLocation.fromJson)
          .toList();
      state = list;
    } catch (_) {
      // leave the defaults in place on any failure
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // best-effort
    }
  }

  /// Add a folder by absolute path (no-op if it doesn't exist or is already present).
  void addFolder(String path) {
    if (!Directory(path).existsSync()) return;
    final fs = fsRoot(path);
    if (state.any((l) => l.remote.fs == fs)) return;
    state = [
      ...state,
      LocalLocation(
        remote: Remote(
          name: _basename(path),
          type: 'local',
          fs: fs,
          isLocal: true,
        ),
        kind: LocalKind.folder,
      ),
    ];
    _persist();
  }

  /// Remove the location with this `fs` from the sidebar.
  void remove(String fs) {
    state = state.where((l) => l.remote.fs != fs).toList();
    _persist();
  }
}

final userLocationsProvider =
    NotifierProvider<UserLocations, List<LocalLocation>>(UserLocations.new);

/// Which sidebar sections are collapsed (by key: `locations`/`disks`/`cloud`).
/// Persisted so a collapsed section stays collapsed across launches.
class CollapsedSections extends Notifier<Set<String>> {
  static const _key = 'collapsed_sidebar_sections';

  @override
  Set<String> build() {
    _load();
    return <String>{};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      state = (jsonDecode(raw) as List).whereType<String>().toSet();
    } catch (_) {
      // default: nothing collapsed
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.toList()));
    } catch (_) {
      // best-effort
    }
  }

  void toggle(String key) {
    final next = Set<String>.of(state);
    next.contains(key) ? next.remove(key) : next.add(key);
    state = next;
    _persist();
  }

  bool isCollapsed(String key) => state.contains(key);
}

final collapsedSectionsProvider =
    NotifierProvider<CollapsedSections, Set<String>>(CollapsedSections.new);
