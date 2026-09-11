/// Platform seam for the app's small, one-off native probes.
///
/// Four unrelated questions share this file for one reason: each is answered by
/// a `dart:ffi` call, and `dart:ffi` is a **compile error** on the web target.
/// Left where they were — inline in `rclone_engine.dart`, `install_source.dart`
/// and `cloud_placeholder.dart` — any one of them would stop the Web UI build
/// from being produced. Collected here, one conditional import covers all four
/// and those three files stay web-clean.
///
/// The real bindings live in `native_probes_io.dart`; `native_probes_web.dart`
/// answers the way a browser must. See `dev/plans/webui-plan.md` §"Stage A".
///
/// This is the seam for *small* probes. The rclone engine's own FFI surface is
/// large and engine-specific, so it keeps its own: see `librclone_ffi.dart`.
library;

export 'native_probes_io.dart'
    if (dart.library.js_interop) 'native_probes_web.dart';
