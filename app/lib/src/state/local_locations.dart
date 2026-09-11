import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/remote.dart';
import 'host_platform.dart';
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

/// `Directory.existsSync()`, but total.
///
/// **`existsSync` is not a predicate on Windows — it throws.** The SDK returns
/// an `OSError` for anything the OS refuses to stat and the getter turns that
/// into a `FileSystemException` (`directory_impl.dart`: *"Exists failed"*).
/// Reproduced on Windows 11: `Directory('CON:/').existsSync()` throws rather
/// than answering false. A drive letter is enough to reach that class of error —
/// a mapped network drive whose server is unreachable, a card reader with no
/// media, a locked volume.
///
/// That matters far more than it looks, because these stats run inside
/// [drivesProvider] and [userLocationsProvider]. A throw in a Riverpod provider
/// body puts the provider in an error state, and every `ref.watch` of it then
/// RETHROWS into the watching widget's build — which takes out the sidebar and
/// both pane bodies at once, since those are the three things that watch it. In
/// a release build the result is not an error message: Flutter's default
/// `ErrorWidget` paints a flat `0xF0C0C0C0` grey rectangle with no text. An
/// unreadable drive letter could therefore blank the whole app.
///
/// A path we cannot stat is simply not offered. "I could not look" and "it is
/// not there" lead to the same UI, and neither is worth a crash.
bool _dirExists(String path) => _statTotal(_rawExists, path);

/// The real, throwing stat. Named so the guarded path below can be handed a
/// fake one in a test without also faking away the guard.
bool _rawExists(String path) => Directory(path).existsSync();

/// Runs [stat] and treats a refusal to answer as "not there".
///
/// [Directory.existsSync] is typed as a plain bool and reads like a total
/// function, but it is not one: on Windows the OS can refuse the question
/// outright and it throws instead of returning false.
bool _statTotal(bool Function(String) stat, String path) {
  try {
    return stat(path);
  } catch (_) {
    return false;
  }
}

LocalLocation? _folder(String name, String path, LocalKind kind) {
  if (path.isEmpty || !_dirExists(path)) return null;
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
  if (!HostPlatform.isIOS) return;
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

  if (HostPlatform.isIOS) return buildIosUserFolders(iosDocumentsRoot);

  if (HostPlatform.isAndroid) {
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

  final env = HostPlatform.environment;
  final home =
      (HostPlatform.isWindows ? env['USERPROFILE'] : env['HOME']) ?? '';
  final sep = HostPlatform.isWindows ? '\\' : '/';

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

/// The Windows drive letters that answer, C through Z.
///
/// Takes its stat as a parameter so the awkward half is testable without an
/// awkward machine. A user on Windows 10 reported Airclone opening completely
/// blank, and their diagnostics report named the cause exactly:
///
/// ```
/// FileSystemException: Exists failed, path = 'E:/'
///     (OS Error: The device is not ready, errno = 21)
///   #3  _Sidebar.build      (home_screen.dart)
///   #3  _HomeViewState.build (home_view.dart)
/// ```
///
/// `errno 21` is `ERROR_NOT_READY` — a card reader or optical drive sitting
/// empty. Stat'ing it throws rather than answering, the throw escaped this
/// sweep into [drivesProvider], and because a synchronous provider has no
/// `AsyncValue` to park an error in, every `ref.watch` rethrew it into the
/// watching widget's build. Three widgets watch it, so the sidebar and both file
/// panes became Flutter's release error box — a flat grey rectangle with no
/// text. An empty card reader blanked the application.
///
/// A letter that cannot be stat'ed is simply not offered. One unreadable drive
/// costs that drive, not the window.
@visibleForTesting
List<LocalLocation> windowsDrives({bool Function(String)? existsSync}) {
  // Deliberately the RAW stat, guarded here by _statTotal: a seam that took the
  // already-guarded _dirExists would let a test inject a throw that never
  // reaches the try/catch, and would prove nothing about the drive sweep.
  final stat = existsSync ?? _rawExists;
  final out = <LocalLocation>[];
  for (var ch = 'C'.codeUnitAt(0); ch <= 'Z'.codeUnitAt(0); ch++) {
    final letter = String.fromCharCode(ch);
    final root = '$letter:/';
    if (_statTotal(stat, root)) {
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
  return out;
}

/// Auto-detected disk drives (Windows letters, or `/` on POSIX). Not editable.
final drivesProvider = Provider<List<LocalLocation>>((ref) {
  final out = <LocalLocation>[];
  if (HostPlatform.isAndroid) {
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
  if (HostPlatform.isWindows) {
    out.addAll(windowsDrives());
  } else if (!bookmarksRequired && !HostPlatform.isIOS) {
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
    if (bookmark == null && !_dirExists(path)) return;
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

/// Heading for the section listing the machine's own disks and folders.
///
/// On the Web UI this is the **host's** storage, never the viewer's. A phone
/// showing the Web UI is a screen: the disks under this heading belong to the
/// machine running Airclone, and a mount made from here appears there too. The
/// phone shell used to head that list "This phone", which told the user the
/// opposite of the truth about where their files were — the one piece of
/// wording in the app that a remote UI makes actively false.
///
/// [phoneShell] is which layout is asking (the width-gated phone shell, or the
/// desktop one), not which device it is running on; an Android tablet gets the
/// desktop shell and still wants "This device".
String localStorageSectionTitle({
  required bool isTelevision,
  required bool phoneShell,
}) {
  if (HostPlatform.isWeb) return 'Host computer';
  if (isTelevision) return 'This TV';
  if (phoneShell) return 'This phone';
  // iPads get the desktop layout via the 700px width gate, so without the iOS
  // test here it called an iPad "This computer".
  return (HostPlatform.isAndroid || HostPlatform.isIOS)
      ? 'This device'
      : 'This computer';
}
