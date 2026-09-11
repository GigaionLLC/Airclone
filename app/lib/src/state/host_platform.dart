/// Which platform this build is *running* on, asked in a way the web build can
/// survive.
///
/// `dart:io`'s `Platform.isWindows` and friends compile fine for the web — the
/// web SDK ships `dart:io` as a set of throwing stubs — and then throw
/// `UnsupportedError` the first time anything reads them. `main()` reads one
/// before the first frame, so on web the app died before drawing a pixel.
///
/// Every accessor here is `kIsWeb ? <web answer> : Platform.isX`. Because
/// [kIsWeb] is a compile-time constant:
///
///   * on desktop and mobile it folds to exactly `Platform.isX` — this is a
///     behaviour-preserving rename, not a change in what any branch decides;
///   * on web the `Platform` call is eliminated by the compiler, so it cannot
///     throw and the tree-shaker drops it entirely.
///
/// **Use this instead of `dart:io`'s `Platform` for anything that can run in the
/// UI.** Code that only ever runs host-side — the engine's own provisioning, the
/// Web UI server, the headless task runner — may keep using `Platform` directly,
/// since reaching it from a browser is already impossible.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform predicates that are safe to evaluate in a web build.
///
/// A browser is none of the five host platforms. That is the right answer, not
/// a convenient one: on web every OS-specific branch in the app guards something
/// the browser genuinely cannot do — spawning a process, opening a native
/// window, reading a drive letter — and the host that *can* do those things is
/// reached through the RC seam instead. Ask [isWeb] when you need to know that
/// the renderer is a browser; ask the rest when you need to know what the OS can
/// do for you locally.
abstract final class HostPlatform {
  /// True when this build is running in a browser (the Web UI).
  static const bool isWeb = kIsWeb;

  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isFuchsia => !kIsWeb && Platform.isFuchsia;

  /// The three platforms with a desktop window, a real filesystem and the
  /// ability to spawn `rcd`. The Web UI server is offered only here.
  static bool get isDesktop => isWindows || isMacOS || isLinux;

  /// The two touch platforms.
  static bool get isMobile => isAndroid || isIOS;

  /// `Platform.operatingSystem`, or `'web'` in a browser.
  ///
  /// `'web'` is not one of `dart:io`'s values, so a `switch` on this that was
  /// written against `Platform.operatingSystem` keeps its existing default —
  /// which is what every such switch in the app already wants.
  static String get operatingSystem =>
      kIsWeb ? 'web' : Platform.operatingSystem;

  /// The path separator, or `'/'` in a browser (URLs, not file paths).
  static String get pathSeparator => kIsWeb ? '/' : Platform.pathSeparator;

  /// Process environment, or empty in a browser. A browser has no environment;
  /// returning an empty map lets callers keep their `?? fallback` shape.
  static Map<String, String> get environment =>
      kIsWeb ? const <String, String>{} : Platform.environment;
}
