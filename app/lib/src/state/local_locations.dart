import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/remote.dart';
import 'mac_bookmarks.dart';

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
  const LocalLocation({
    required this.remote,
    required this.kind,
    this.bookmark,
  });
  final Remote remote;
  final LocalKind kind;

  /// Base64 security-scoped bookmark, on the sandboxed Mac App Store build only.
  ///
  /// There, the path in [remote] is not enough: a sandboxed app may only read a
  /// folder it holds a live grant for, and the grant does not survive a
  /// relaunch. This token is what re-acquires it. Null everywhere else, and null
  /// on a MAS entry that predates the bookmark (which then needs re-granting
  /// rather than silently failing). See state/mac_bookmarks.dart.
  final String? bookmark;

  LocalLocation copyWith({String? bookmark}) => LocalLocation(
    remote: remote,
    kind: kind,
    bookmark: bookmark ?? this.bookmark,
  );

  Map<String, dynamic> toJson() => {
    'name': remote.name,
    'fs': remote.fs,
    'kind': kind.name,
    if (bookmark != null) 'bookmark': bookmark,
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
    // Absent for every pre-bookmark entry and on every non-MAS platform.
    bookmark: j['bookmark'] as String?,
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

/// The app's own Documents directory on iOS — the entirety of "local" there.
///
/// iOS has no arbitrary filesystem to browse and no folder picker to grant one
/// (`file_selector` implements `getDirectoryPath` on desktop and Android only),
/// so the container is the whole story. It is not a private hole, though: with
/// `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` in Info.plist,
/// this exact directory is what the Files app shows as *On My iPhone → Airclone*,
/// so the user can put files into it from outside and see what Airclone wrote.
///
/// Resolved once in `main()` via [initIosDocumentsRoot], for the same reason
/// [androidStorageRoot] is: it keeps the location providers synchronous. Empty
/// off iOS, and empty on iOS until that call lands - hence the guard before it
/// is ever turned into a Location.
String iosDocumentsRoot = '';

/// Resolve [iosDocumentsRoot]. Call once in `main()` before `runApp`; no-op
/// everywhere else. Failure leaves it empty, which shows an empty Locations
/// list rather than a row pointing somewhere wrong.
Future<void> initIosDocumentsRoot() async {
  if (!Platform.isIOS) return;
  try {
    iosDocumentsRoot = (await getApplicationDocumentsDirectory()).path;
  } catch (_) {
    // keep the default
  }
}

/// The iOS seed set: exactly the container's Documents directory, and nothing
/// else.
///
/// Falling through to the `$HOME` branch of [buildDefaultUserFolders] would seed
/// a "Home" pointing at the container ROOT, exposing `Library/` and `tmp/` -
/// app plumbing the user has no business browsing and no way to use. Returns
/// empty when [documentsRoot] has not been resolved, which shows an empty
/// Locations list rather than a row pointing somewhere wrong.
///
/// Pure (takes the root) so the "exactly one, and it points there" contract is
/// testable without a device.
List<LocalLocation> buildIosUserFolders(String documentsRoot) {
  if (documentsRoot.isEmpty) return const [];
  return [
    LocalLocation(
      remote: Remote(
        name: 'On My Device',
        type: 'local',
        fs: fsRoot(documentsRoot),
        isLocal: true,
      ),
      kind: LocalKind.documents,
    ),
  ];
}

/// The default set of user folders (Home + standard XDG-ish folders) for first run.
List<LocalLocation> buildDefaultUserFolders() {
  final out = <LocalLocation>[];

  // A sandboxed build must seed NOTHING. Under the sandbox `$HOME` is redirected
  // into the app's container, and macOS pre-creates Desktop/Documents/Downloads
  // there - so every default would pass its existsSync() check, render happily
  // in the sidebar, and point at an empty folder that is not the user's. That is
  // worse than an empty sidebar: it looks like the app works and lost your
  // files. First run is "add your first folder", granted through NSOpenPanel.
  if (bookmarksRequired) return out;

  if (Platform.isIOS) return buildIosUserFolders(iosDocumentsRoot);

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
  } else if (!bookmarksRequired && !Platform.isIOS) {
    // "/" is unbrowsable under the sandbox and no grant can ever cover it, so a
    // MAS build must not offer it. On iOS it is not browsable by anyone at any
    // privilege, so offering it would just be a row that always fails to open.
    // Elsewhere it is the POSIX filesystem root.
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

  /// Re-acquire the sandbox grant for every persisted Location, on a MAS build.
  ///
  /// A path alone is worthless to a sandboxed app after relaunch, so every
  /// Location that came back from disk has to have its bookmark resolved and
  /// started before anything tries to read it. Grants are held for the session
  /// rather than per operation: transfers run as `_async` RC jobs that outlive
  /// the call that started them, so releasing early would revoke access
  /// mid-copy.
  ///
  /// A Location whose bookmark will not resolve is KEPT, not dropped - silently
  /// deleting somebody's folder list because macOS invalidated a token would be
  /// far worse than showing an entry that needs re-granting. A stale bookmark
  /// still works and is re-created here so the staleness does not compound.
  Future<void> _reacquireGrants() async {
    if (!bookmarksRequired) return;
    for (final loc in state) {
      final b = loc.bookmark;
      if (b == null || b.isEmpty) continue;
      final resolved = await resolveBookmark(b);
      if (resolved == null) continue; // needs re-granting; entry stays visible
      await startAccess(b);
    }
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
      await _reacquireGrants();
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
  /// Add a folder Location.
  ///
  /// [bookmark] is the security-scoped token from `grantFolder` and is REQUIRED
  /// on a sandboxed build - without it the entry would be unusable after the
  /// next launch. The existsSync() gate is skipped when a bookmark is supplied,
  /// because the user just picked the folder through PowerBox: the grant is
  /// live, and a stat is not what proves it.
  void addFolder(String path, {String? bookmark}) {
    if (bookmark == null && !Directory(path).existsSync()) return;
    if (bookmarksRequired && bookmark == null) return;
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
        bookmark: bookmark,
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
