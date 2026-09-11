/// Web build of [WindowsChildJob] — see `windows_child_job.dart` for why this
/// file exists.
///
/// The Web UI build never spawns anything: the engine runs on the host, and the
/// browser reaches it through `/api/rc`. So there is no child to tie to this
/// process's lifetime and [WindowsChildJob.adopt] is a no-op that keeps the
/// call sites free of `kIsWeb` branches.
library;

/// No-op stand-in for the Windows Job Object. API-identical to the real one so
/// callers compile unchanged; see `windows_child_job_io.dart` for the mechanism
/// and for why losing it costs only orphan cleanup, never a feature.
class WindowsChildJob {
  WindowsChildJob._();

  /// Does nothing. There are no child processes in a browser.
  static void adopt(int pid) {}
}
