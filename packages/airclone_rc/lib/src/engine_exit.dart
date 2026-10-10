/// What it means when the `rcd` child exits without being asked to.
///
/// A problem report used to show only the symptom: the next rc call failing
/// with "Connection refused". That reads like a bug, and on Android it almost
/// never is one. Android closes a backgrounded app's child processes to save
/// memory (the low-memory killer, and Android 12+'s phantom-process limit), and
/// it does so with SIGKILL. So the exit itself is recorded, with the one fact
/// that separates the two cases: how the process ended.
///
/// Pure, so the classification is unit-tested without spawning anything.
library;

import 'rclone_log.dart';

/// SIGKILL: the signal every Android process killer uses, and on desktop the
/// one the Linux OOM killer and "End task"/`kill -9` use.
const int kSigKill = 9;

const Map<int, String> _signalNames = {
  1: 'SIGHUP',
  2: 'SIGINT',
  6: 'SIGABRT',
  9: 'SIGKILL',
  11: 'SIGSEGV',
  13: 'SIGPIPE',
  15: 'SIGTERM',
};

/// One unexpected engine exit, classified.
class EngineExit {
  const EngineExit({
    required this.exitCode,
    required this.level,
    required this.message,
    required this.closedByOs,
    this.uptime,
  });

  /// As `Process.exitCode` reports it: negative is "killed by signal -N" on
  /// POSIX; anything else is the process's own exit status.
  final int exitCode;

  /// [RcloneLogLevel.notice] when the OS closed it (expected, not a bug);
  /// [RcloneLogLevel.fatal] otherwise (it crashed or quit on its own).
  final RcloneLogLevel level;

  /// The diagnostics line, written for the person reading the report.
  final String message;

  /// True when this is the OS reclaiming a background process. The host words
  /// its "start it again" prompt differently for this case.
  final bool closedByOs;

  /// How long the process had been running, when known.
  final Duration? uptime;

  /// The machine-readable half, for the report's detail line.
  String get detail {
    final named = _signalNames[-exitCode];
    final how = exitCode >= 0
        ? 'exit code $exitCode'
        : named == null
        ? 'signal ${-exitCode}'
        : 'signal ${-exitCode} ($named)';
    final up = uptime;
    return up == null ? how : '$how after ${formatUptime(up)}';
  }
}

/// `SIGKILL` for 9; `signal 42` for one without a common name.
String signalName(int signal) => _signalNames[signal] ?? 'signal $signal';

/// `42s`, `5m 03s`, `2h 07m`: short, and precise where it matters.
String formatUptime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}h ${two(d.inMinutes % 60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${two(d.inSeconds % 60)}s';
  return '${d.inSeconds}s';
}

/// Classifies an exit that Airclone did not ask for.
///
/// Only Android + SIGKILL counts as the OS closing it. On desktop a SIGKILL is
/// the OOM killer or someone killing the process by hand: worth a look, so it
/// stays fatal. Every other signal (SIGSEGV, SIGABRT) and every exit status is
/// the engine stopping on its own, which is exactly what a report is for.
EngineExit describeEngineExit(
  int exitCode, {
  required bool android,
  Duration? uptime,
}) {
  final closedByOs = android && exitCode == -kSigKill;
  if (closedByOs) {
    return EngineExit(
      exitCode: exitCode,
      level: RcloneLogLevel.notice,
      message:
          'Android closed the engine to save memory while Airclone was in '
          'the background. This is normal and not a bug.',
      closedByOs: true,
      uptime: uptime,
    );
  }
  final message = exitCode < 0
      ? 'the engine was stopped by ${signalName(-exitCode)}'
      : 'the engine exited unexpectedly';
  return EngineExit(
    exitCode: exitCode,
    level: RcloneLogLevel.fatal,
    message: message,
    closedByOs: false,
    uptime: uptime,
  );
}
