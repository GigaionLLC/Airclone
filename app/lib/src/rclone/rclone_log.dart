/// How the rclone engine layer reports what it has decided is worth keeping.
///
/// The layer below this file knows how to run rclone; it knows nothing about
/// where a host keeps a log, and it must not. So it takes a sink and calls it.
/// Airclone passes one that forwards to `state/diagnostics.dart`, where
/// redaction happens at ingest; a host that passes nothing gets silence.
///
/// **What reaches a sink is already filtered.** At high verbosity (`-vv`,
/// `--dump`) rclone echoes request headers carrying the rc credentials, so the
/// engine client keeps only its own failure lines, de-duplicated and capped,
/// and hands those over. A sink is a destination, never the filter.
library;

/// Severity of an engine event, in the terms the engine layer has.
///
/// Deliberately not the app's `DiagLevel`: an enum is the whole reason this
/// file exists, and mapping it is one `switch` in the host.
enum RcloneLogLevel { info, warning, error }

/// Receives an engine event: a severity, a short area tag (`engine`,
/// `preview`), the message, and optionally the underlying error.
typedef RcloneLogSink =
    void Function(
      RcloneLogLevel level,
      String area,
      String message, {
      Object? detail,
    });

/// The default sink: throws the event away.
///
/// A host that wants engine events says so. Silence is the safe default for a
/// package whose lines can carry credentials — the alternative, printing by
/// default, is how they end up in someone else's log.
void discardRcloneLog(
  RcloneLogLevel level,
  String area,
  String message, {
  Object? detail,
}) {}
