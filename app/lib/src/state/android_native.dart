import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_locations.dart';

/// Bridge to the few Android facts/actions Dart can't reach on its own
/// (see MainActivity.kt). Every call is a safe no-op off Android.
const _channel = MethodChannel('airclone/native');

/// Whether the app is running on an Android TV. Resolved once in main() before
/// runApp, exactly like [androidStorageRoot] and for the same reason: the shell
/// is chosen inside a synchronous build().
///
/// False on every other platform and false until [initAndroidIsTelevision]
/// completes, so nothing can accidentally get the TV shell.
bool androidIsTelevision = false;

/// Asks Android whether this is a television (see MainActivity.kt).
Future<void> initAndroidIsTelevision() async {
  if (!Platform.isAndroid) return;
  try {
    androidIsTelevision =
        await _channel.invokeMethod<bool>('isTelevision') ?? false;
  } catch (_) {
    // An old build without the method, or a channel failure. Staying false
    // means a TV renders the existing touch shell - degraded, not broken.
  }
}

/// Resolves the device's real shared-storage root (differs from
/// /storage/emulated/0 for secondary users and work profiles). Called once in
/// main() before runApp; keeps the location providers synchronous.
Future<void> initAndroidStorageRoot() async {
  if (!Platform.isAndroid) return;
  try {
    final dir = await _channel.invokeMethod<String>('externalStorageDir');
    if (dir != null && dir.isNotEmpty) androidStorageRoot = dir;
  } catch (_) {
    // keep the default
  }
}

/// Whether the app may read real filesystem paths under shared storage
/// (All Files Access on Android 11+; implicitly true before that and on
/// desktop). rclone's `local` backend needs this for anything outside the
/// app's own directories.
final allFilesAccessProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isAndroid) return true;
  try {
    return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
  } catch (_) {
    return false;
  }
});

/// PNG bytes of a representative frame from the video at [url] (fetched with
/// [headers], scaled into a [size]-px box), or null when Android can't decode
/// one — or off Android entirely.
///
/// This exists because libmpv, which captures keyframes on every other
/// platform, decodes into a Surface on Android: its `screenshot` command has
/// no CPU-readable frame to return, so video tiles never got one. Android's
/// own MediaMetadataRetriever does (see MainActivity.kt).
Future<Uint8List?> androidVideoThumbnail(
  String url,
  Map<String, String> headers,
  int size,
) async {
  if (!Platform.isAndroid) return null;
  try {
    return await _channel.invokeMethod<Uint8List>('videoThumbnail', {
      'url': url,
      'headers': headers,
      'size': size,
    });
  } catch (_) {
    // Undecodable media, a dead engine, an old build without the method —
    // all mean the same thing here: no thumbnail.
    return null;
  }
}

/// Opens Android's All Files Access settings screen for this app. The user
/// grants it there and returns; call `ref.invalidate(allFilesAccessProvider)`
/// on resume/next build to pick up the new state.
Future<void> requestAllFilesAccess() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('requestAllFilesAccess');
  } catch (_) {
    // settings screen unavailable — nothing else to do
  }
}
