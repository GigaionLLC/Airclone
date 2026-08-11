/// The local, no-telemetry error log — Airclone's answer to "send us your logs"
/// for a product that refuses to phone home.
///
/// Airclone's privacy position (PRIVACY.md) rules out crash/analytics reporting:
/// nothing about a user's remotes, paths, or failures may leave their device
/// unbidden. But a bug report with no evidence is a bug that never gets fixed,
/// so failures are recorded HERE — a bounded, in-memory ring the user can read,
/// copy, and choose to attach to an issue. Nothing is written to disk unless the
/// user saves a report; nothing is ever transmitted.
///
/// Two rules make this safe to hand to a stranger:
///  * every message passes through [redactSensitive] before it is stored, so a
///    token, password, or bearer header that rclone echoed into an error never
///    reaches the ring in the first place (redaction at INGEST, not at export —
///    a copy path that forgot to redact would otherwise leak);
///  * the report header carries versions and platform only, never a remote name,
///    account, or hostname.
library;

import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How bad an entry is. [error] is what a bug report is usually about; [warning]
/// is a recovered problem; [info] is context that makes the errors readable
/// (engine started, config switched).
enum DiagLevel { info, warning, error }

/// One recorded event.
@immutable
class DiagEntry {
  const DiagEntry({
    required this.time,
    required this.level,
    required this.area,
    required this.message,
    this.detail,
  });

  final DateTime time;
  final DiagLevel level;

  /// Which subsystem produced it — `config-import`, `open-external`, `engine`,
  /// `transfer`. Short and stable so a report is skimmable.
  final String area;

  /// The redacted one-line summary.
  final String message;

  /// Optional redacted extra context (an exception's detail, a stack tail).
  final String? detail;

  /// One report line: `12:04:31  ERROR  config-import  message`.
  String format() {
    final t = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final tag = switch (level) {
      DiagLevel.error => 'ERROR',
      DiagLevel.warning => 'WARN ',
      DiagLevel.info => 'INFO ',
    };
    final head = '$stamp  $tag  $area  $message';
    final d = detail;
    if (d == null || d.isEmpty) return head;
    // Indent continuation lines so multi-line details stay visually attached.
    return '$head\n${d.split('\n').map((l) => '           $l').join('\n')}';
  }
}

// --- Redaction ---------------------------------------------------------------

/// Patterns replaced before anything is stored. Ordered most-specific first: a
/// `token = {...}` blob must be caught before the generic key/value rule reduces
/// it to a partial match.
final List<(RegExp, String Function(Match))> _redactions = [
  // `scheme://user:secret@host` — credentials embedded in a URL.
  (
    RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@'),
    (m) => '${m[1]}<credentials>@',
  ),
  // An OAuth token blob as rclone stores it: `token = {"access_token":...}`.
  (
    RegExp(r'(?<![\w-])(token|refresh_token|access_token)\s*[=:]\s*\{[^}]*\}'),
    (m) => '${m[1]} = <redacted>',
  ),
  // `Authorization: Bearer …` / `Basic …` headers. BEFORE the generic key rule
  // below, which would otherwise match `Authorization:` and redact the word
  // "Bearer" while leaving the token itself in the clear.
  (
    RegExp(r'(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}', caseSensitive: false),
    (m) => '${m[1]} <redacted>',
  ),
  // Any config key whose NAME contains a secret-ish word, in `k = v` or
  // `"k": "v"`. Matching the WHOLE key token (not just the word) is what makes
  // this hold up against rclone's real key names: `secret_access_key`,
  // `client_secret`, `sa_credentials_file`, `chunker_pass`. Over-redacting a
  // harmless `monkey = 3` is a trade we take every time.
  (
    RegExp(
      r'''([\w.-]*(?:pass|token|secret|key|auth|credential|cookie)[\w.-]*)"?'''
      r'''\s*[=:]\s*"?([^\s,"}\]]+)''',
      caseSensitive: false,
    ),
    (m) => '${m[1]} = <redacted>',
  ),
  // Email addresses (a remote's account often appears verbatim in an error).
  // The lookbehind keeps this off a `<credentials>@host` placeholder the URL
  // rule above just wrote — otherwise it would swallow the hostname too, which
  // is the one part of a failing URL worth keeping.
  (RegExp(r'(?<![<>\w.+-])[\w.+-]+@[\w-]+\.[\w.-]+'), (_) => '<email>'),
  // Windows/macOS/Linux home directories, so a report never carries the user's
  // real name. The rest of the path is kept — it is what makes a report useful.
  (
    RegExp(r'([A-Za-z]:\\Users\\)[^\\\s"]+', caseSensitive: false),
    (m) => '${m[1]}<user>',
  ),
  (RegExp(r'(/Users/)[^/\s"]+'), (m) => '${m[1]}<user>'),
  (RegExp(r'(/home/)[^/\s"]+'), (m) => '${m[1]}<user>'),
];

/// Strips secrets and personal identifiers from [text]. Applied to every message
/// and detail BEFORE it enters the ring, so no export path can leak by omission.
/// Pure — exhaustively unit-tested in test/diagnostics_test.dart.
String redactSensitive(String text) {
  var out = text;
  for (final (pattern, replace) in _redactions) {
    out = out.replaceAllMapped(pattern, replace);
  }
  return out;
}

// --- The ring ----------------------------------------------------------------

/// How many entries are kept. Bounded so a long session with a chatty failure
/// can't grow without limit; large enough that the events leading to a problem
/// are still there when the user goes looking.
const int kDiagnosticsCapacity = 300;

/// The in-memory log. A [Notifier] so the settings panel rebuilds as entries
/// arrive; the list it exposes is newest-LAST (chronological, as a log reads).
class DiagnosticsLog extends Notifier<List<DiagEntry>> {
  final Queue<DiagEntry> _entries = Queue<DiagEntry>();

  @override
  List<DiagEntry> build() => const [];

  /// Records one event. [message]/[detail] are redacted here — callers must not
  /// pre-sanitise, and must not assume they can bypass this by other means.
  void record(
    DiagLevel level,
    String area,
    String message, {
    Object? detail,
    DateTime? at,
  }) {
    final entry = DiagEntry(
      time: at ?? DateTime.now(),
      level: level,
      area: area,
      message: redactSensitive(message),
      detail: detail == null ? null : redactSensitive(detail.toString()),
    );
    _entries.addLast(entry);
    while (_entries.length > kDiagnosticsCapacity) {
      _entries.removeFirst();
    }
    state = List<DiagEntry>.unmodifiable(_entries);
  }

  /// Convenience for the overwhelmingly common call.
  void error(String area, String message, {Object? detail}) =>
      record(DiagLevel.error, area, message, detail: detail);

  void warn(String area, String message, {Object? detail}) =>
      record(DiagLevel.warning, area, message, detail: detail);

  void info(String area, String message, {Object? detail}) =>
      record(DiagLevel.info, area, message, detail: detail);

  void clear() {
    _entries.clear();
    state = const [];
  }
}

final diagnosticsProvider = NotifierProvider<DiagnosticsLog, List<DiagEntry>>(
  DiagnosticsLog.new,
);

/// A process-wide handle to the running app's log, so code with no [Ref] —
/// [FlutterError.onError], the platform-dispatcher error hook — can still
/// record. Set once from the app root; null in tests that never build the app.
DiagnosticsLog? _globalLog;

/// Publishes [log] as the process-wide sink (see [_globalLog]).
void attachGlobalDiagnostics(DiagnosticsLog log) => _globalLog = log;

/// Records through the process-wide log if one has been attached, else drops the
/// event. Never throws — a logging failure must not become the user's problem.
void logDiagnostic(
  DiagLevel level,
  String area,
  String message, {
  Object? detail,
}) {
  try {
    _globalLog?.record(level, area, message, detail: detail);
  } catch (_) {
    // The log is a convenience, never a dependency.
  }
}

// --- Report ------------------------------------------------------------------

/// Environment facts a maintainer needs, collected by the UI (which can reach
/// the version providers) and passed to [buildDiagnosticsReport].
@immutable
class DiagnosticsEnvironment {
  const DiagnosticsEnvironment({
    required this.appVersion,
    required this.platform,
    required this.osVersion,
    required this.installChannel,
    this.engineVersion,
    this.engineMode,
  });

  final String appVersion;
  final String platform;
  final String osVersion;

  /// How the app was installed (see install_source.dart) — the single most
  /// useful field for reproducing a packaging-specific bug.
  final String installChannel;
  final String? engineVersion;
  final String? engineMode;
}

/// Reads the OS description without any user-identifying detail
/// (`Platform.operatingSystemVersion` is a build string, not a machine name).
DiagnosticsEnvironment describeEnvironment({
  required String appVersion,
  required String installChannel,
  String? engineVersion,
  String? engineMode,
}) => DiagnosticsEnvironment(
  appVersion: appVersion,
  platform: Platform.operatingSystem,
  osVersion: Platform.operatingSystemVersion,
  installChannel: installChannel,
  engineVersion: engineVersion,
  engineMode: engineMode,
);

/// Renders the copyable/savable report: a short header, then the log oldest
/// first. Everything in [entries] was redacted at ingest; the header is built
/// from version strings only. Pure so its exact shape is unit-tested.
String buildDiagnosticsReport(
  DiagnosticsEnvironment env,
  List<DiagEntry> entries,
) {
  final b = StringBuffer()
    ..writeln('Airclone diagnostics report')
    ..writeln('---------------------------')
    ..writeln('App:      ${env.appVersion}')
    ..writeln('Platform: ${env.platform} ${env.osVersion}')
    ..writeln('Install:  ${env.installChannel}');
  if (env.engineVersion != null) b.writeln('Engine:   ${env.engineVersion}');
  if (env.engineMode != null) b.writeln('Mode:     ${env.engineMode}');
  b
    ..writeln('Entries:  ${entries.length}')
    ..writeln()
    ..writeln(
      'Secrets, emails and home-directory names are removed automatically. '
      'Please still skim this before sharing it.',
    )
    ..writeln();
  if (entries.isEmpty) {
    b.writeln('(nothing recorded this session)');
  } else {
    for (final e in entries) {
      b.writeln(e.format());
    }
  }
  return b.toString();
}
