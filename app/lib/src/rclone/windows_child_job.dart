/// Platform seam for the Windows child-process Job Object.
///
/// `dart:ffi` is a **compile error** on the web target — not a runtime one, the
/// way `dart:io` is — so every library that reaches for it has to sit behind a
/// conditional import or the Web UI build cannot be produced at all. The real
/// implementation is in `windows_child_job_io.dart`; the web build gets the
/// do-nothing one, which costs it exactly nothing: a browser has no child
/// processes to adopt.
///
/// Importers see one name, [WindowsChildJob], and never learn which half they
/// got. See `dev/plans/webui-plan.md` §"Stage A".
library;

export 'windows_child_job_io.dart'
    if (dart.library.js_interop) 'windows_child_job_web.dart';
