import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_locations.dart';

/// Bridge to the few Android facts/actions Dart can't reach on its own
/// (see MainActivity.kt). Every call is a safe no-op off Android.
const _channel = MethodChannel('airclone/native');

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
