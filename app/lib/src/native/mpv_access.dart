/// Platform seam for talking to libmpv directly: properties and commands
/// media_kit has no API for (`aid`/`sid` read-back, `alang`/`slang`,
/// `sub-add`, the capability lists).
///
/// They live behind `NativePlayer`, and on the web media_kit swaps in a stub
/// `NativePlayer` that has none of those methods, so calling them anywhere in
/// shared code is a compile error for the Web UI build — which is how the
/// v0.23.0 tag's desktop builds first failed. One conditional import keeps
/// every caller web-clean, the same way `native_probes.dart` does for FFI.
library;

export 'mpv_access_io.dart' if (dart.library.js_interop) 'mpv_access_web.dart';
