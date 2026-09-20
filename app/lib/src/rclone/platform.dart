/// The two platform questions the rclone engine layer actually asks.
///
/// A deliberately tiny replacement for the app's `HostPlatform`: this layer is
/// becoming a package (see `dev/plans/airclone-rc-package-plan.md`) and cannot
/// import the app, or Flutter, to learn which OS it is on.
///
/// The web guard is the same constant Flutter defines `kIsWeb` as, so the
/// answers are identical to the ones `HostPlatform` gives.
library;

import 'dart:io' show Platform;

/// True when this was compiled for the web, where `Platform` throws.
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Where the engine layer asks about the host OS.
abstract final class EnginePlatform {
  /// Android needs its own answers twice: `systemTemp` is not app-writable
  /// there, and the OS kills the app's whole process group anyway.
  static bool get isAndroid => !_isWeb && Platform.isAndroid;

  /// For joining cache paths. `/` on the web, where nothing joins anything.
  static String get pathSeparator => _isWeb ? '/' : Platform.pathSeparator;
}
