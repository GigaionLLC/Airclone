/// Security-scoped bookmarks — how a sandboxed macOS build keeps access to a
/// user's folder across launches.
///
/// Under the App Sandbox, Airclone may read a local folder only after the user
/// picks it in an `NSOpenPanel`. That grant dies with the process; a bookmark is
/// the token that survives it. Native side: `macos/Runner/SecurityScopedBookmarks.swift`.
///
/// Two things make this unlike an ordinary platform channel, and both are why
/// the picker cannot simply be `file_selector`:
///
/// 1. **`file_selector` throws the grant away.** It returns a bare `String`
///    path; the `NSURL` that carries the sandbox extension never reaches Dart,
///    so there is nothing left to create a bookmark from. The grant works for
///    the current run and is gone at the next launch.
/// 2. **A resolved bookmark must be started and stopped on the SAME native URL
///    instance**, which is why the Swift side caches by bookmark string rather
///    than re-resolving. Calling stop on an equal-looking URL silently fails to
///    release, and the OS ceiling on simultaneously-held resources is real
///    (low thousands) — so grants are held per Location, never per file.
///
/// Every function here is a safe no-op where bookmarks do not apply (Windows,
/// Linux, Android, and the non-sandboxed macOS DMG), so callers need no platform
/// branch of their own. Nothing throws.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'build_flavor.dart';

const _channel = MethodChannel('airclone/native');

/// Whether this build needs bookmarks at all.
///
/// Only the sandboxed Mac App Store build does. The DMG runs unsandboxed and can
/// read a path forever, so asking it to manage grants would be pure overhead —
/// and would break, since the native handler's panel is only wired for MAS.
bool get bookmarksRequired => Platform.isMacOS && kMacAppStoreBuild;

/// A folder the user just granted, plus the token that outlives the process.
class MacGrant {
  const MacGrant({required this.path, required this.bookmark});
  final String path;

  /// Base64 bookmark data. Persist this beside the path — the path alone is
  /// useless to a sandboxed build after relaunch.
  final String bookmark;
}

/// A resolved bookmark.
class MacResolved {
  const MacResolved({required this.path, required this.isStale});
  final String path;

  /// macOS asking us to re-create and re-persist this bookmark. It still works
  /// right now, so this is not an error — but ignoring it is how a Location
  /// quietly stops working after an OS update.
  final bool isStale;
}

/// Show the native folder picker and return the grant, or null if the user
/// cancelled (or this build does not use bookmarks).
Future<MacGrant?> grantFolder({String? initialPath}) async {
  if (!bookmarksRequired) return null;
  try {
    final res = await _channel.invokeMapMethod<String, dynamic>('grantFolder', {
      if (initialPath != null && initialPath.isNotEmpty)
        'initialPath': initialPath,
    });
    if (res == null) return null; // cancelled
    final path = res['path'] as String?;
    final bookmark = res['bookmark'] as String?;
    if (path == null || bookmark == null) return null;
    return MacGrant(path: path, bookmark: bookmark);
  } catch (_) {
    // A failed grant is indistinguishable from a cancelled one to the caller,
    // and both mean "no new Location" — surfacing an exception here would just
    // put a crash dialog in front of someone who pressed Cancel.
    return null;
  }
}

/// Resolve a persisted bookmark. Null means the Location needs re-granting —
/// the bookmark is broken, or the folder is gone.
Future<MacResolved?> resolveBookmark(String bookmark) async {
  if (!bookmarksRequired || bookmark.isEmpty) return null;
  try {
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'resolveBookmark',
      {'bookmark': bookmark},
    );
    final path = res?['path'] as String?;
    if (path == null) return null;
    return MacResolved(
      path: path,
      isStale: (res?['isStale'] as bool?) ?? false,
    );
  } catch (_) {
    return null;
  }
}

/// Begin using a resolved grant. [resolveBookmark] must have succeeded first.
///
/// Hold this for as long as the Location is in use — NOT just for the duration
/// of one call. Transfers run as `_async` RC jobs that outlive the `rpc()`
/// future that started them, so a naive start/rpc/stop revokes access midway
/// through a copy.
Future<bool> startAccess(String bookmark) async {
  if (!bookmarksRequired || bookmark.isEmpty) return false;
  try {
    return await _channel.invokeMethod<bool>('startAccess', {
          'bookmark': bookmark,
        }) ??
        false;
  } catch (_) {
    return false;
  }
}

/// Release a grant. Safe to call for a bookmark that was never started.
Future<void> stopAccess(String bookmark) async {
  if (!bookmarksRequired || bookmark.isEmpty) return;
  try {
    await _channel.invokeMethod<void>('stopAccess', {'bookmark': bookmark});
  } catch (_) {
    /* teardown path — nothing useful to do with a failure */
  }
}
