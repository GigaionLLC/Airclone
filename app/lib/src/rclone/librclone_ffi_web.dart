/// Web build of the librclone binding — see `librclone_ffi.dart` for why this
/// file exists.
///
/// There is no in-process rclone in a browser and there never will be: the Web
/// UI drives the engine on the host that served it, through `/api/rc`. These
/// are therefore honest answers rather than stubs — "no library is available
/// here" is simply true — and [LibrcloneEngine] exists only so the shared call
/// sites keep compiling.
library;

/// The platform filename of the librclone shared library. Kept pure and
/// OS-driven so the shared unit tests cover the same table on every target.
String librcloneFileName(String operatingSystem) {
  switch (operatingSystem) {
    case 'macos':
      return 'librclone.dylib';
    case 'windows':
      return 'librclone.dll';
    default: // linux (and any other unix)
      return 'librclone.so';
  }
}

/// Whether librclone is statically linked into the executable on
/// [operatingSystem]. Only iOS does that; see the native implementation for why.
bool librcloneIsStaticallyLinked(String operatingSystem) =>
    operatingSystem == 'ios';

/// Empty: there is no filesystem path to a native library from a browser.
String defaultLibrclonePath() => '';

/// False — and this is the answer that matters. `EngineController` asks it
/// before considering the in-process engine at all, so returning false keeps
/// the web build on its own branch without a `kIsWeb` test at the call site.
bool librcloneLibraryAvailable() => false;

/// Thrown for a catastrophic FFI/worker failure. Retained on web so the shared
/// `catch (e) on LibrcloneFfiException` clauses still compile.
class LibrcloneFfiException implements Exception {
  LibrcloneFfiException(this.message);

  final String message;

  @override
  String toString() => 'LibrcloneFfiException: $message';
}

/// Non-functional stand-in for the worker-isolate engine.
///
/// Reaching any method here means something tried to start an in-process engine
/// in a browser, which is a programming error rather than a user-visible state —
/// [librcloneLibraryAvailable] returns false, so the normal paths never get
/// here. It throws rather than failing silently so such a bug is loud.
class LibrcloneEngine {
  bool get isStarted => false;

  Future<void> start({
    required String libPath,
    String? configPath,
    String? configPass,
  }) async => throw LibrcloneFfiException(
    'The in-process rclone engine is not available in the Web UI build; '
    'the engine runs on the host.',
  );

  Future<(int, String)> rpc(String method, String input) => Future.error(
    LibrcloneFfiException(
      'The in-process rclone engine is not available in the Web UI build.',
    ),
  );

  /// Idempotent no-op: nothing was ever started.
  Future<void> stop() async {}
}
