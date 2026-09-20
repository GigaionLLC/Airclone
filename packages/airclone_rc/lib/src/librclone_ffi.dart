/// Platform seam for the in-process rclone engine.
///
/// `dart:ffi` is a **compile error** on the web target, and the real binding in
/// `librclone_ffi_io.dart` is built entirely out of it. Without this seam the
/// Web UI build could not be produced at all — which would be an odd way to
/// lose a feature, given that the web build has no use for an in-process engine
/// in the first place: it drives the engine already running on the host that
/// served the page.
///
/// So `librclone_ffi_web.dart` answers "no library here" and throws if anyone
/// tries to start one. `EngineController` never gets that far on web — it takes
/// the [WebRcloneClient] branch — so the throw is a backstop, not a path.
///
/// See `dev/plans/webui-plan.md` §"Stage A".
library;

export 'librclone_ffi_io.dart'
    if (dart.library.js_interop) 'librclone_ffi_web.dart';
