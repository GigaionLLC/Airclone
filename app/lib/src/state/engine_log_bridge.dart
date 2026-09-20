import 'package:airclone_rc/airclone_rc.dart';
import 'diagnostics.dart';

/// Airclone's [RcloneLogSink]: engine events land in the diagnostics ring.
///
/// The one place the engine layer's vocabulary meets the app's. It exists so
/// the rclone client can stay ignorant of `DiagLevel`, `logDiagnostic` and the
/// ring's existence, and so there is exactly one answer to "where do engine
/// lines go" rather than one per construction site.
///
/// Redaction still happens where it always did — at ingest, inside
/// [logDiagnostic] — so nothing that passes through here can reach an export
/// unredacted. See `state/diagnostics.dart`.
void logEngineEvent(
  RcloneLogLevel level,
  String area,
  String message, {
  Object? detail,
}) {
  logDiagnostic(_level(level), area, message, detail: detail);
}

DiagLevel _level(RcloneLogLevel level) => switch (level) {
  RcloneLogLevel.info => DiagLevel.info,
  RcloneLogLevel.warning => DiagLevel.warning,
  RcloneLogLevel.error => DiagLevel.error,
};
