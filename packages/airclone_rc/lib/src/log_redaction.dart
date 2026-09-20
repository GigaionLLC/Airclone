/// Removing credentials from engine output before anyone sees it.
///
/// **Why the package does this rather than leaving it to the host.** The host
/// receives engine lines through an [RcloneLogSink] it supplies, and a sink is
/// usually the shortest thing in a program: `print`, a logger call, a list the
/// bug-report screen reads. rclone, at `-vv` or under `--dump headers`, echoes
/// the request headers of the rc calls this package makes — which carry the
/// per-session rc password in an `Authorization: Basic` blob. Handing that to a
/// sink and documenting "you should redact this" makes the safe outcome the
/// attentive reader's problem. So it is redacted here, on the way out.
///
/// It is not a general-purpose secret scrubber and does not try to be: it knows
/// **this session's own credentials**, plus the two shapes that carry a
/// credential in rclone's own output regardless of whose it is. A host with a
/// broader redactor should still run it — Airclone does, at the ring's ingest.
library;

/// Replaces every occurrence of [sessionSecrets] in [line], plus the credential
/// shapes rclone emits, with a placeholder.
///
/// [sessionSecrets] are literal strings — this session's rc password, the
/// base64 `user:pass` blob it travels in, a config password. Empty and
/// one-character entries are ignored: a secret that short would match half the
/// line and redact the message into uselessness, and something that short is
/// not protecting anything anyway.
String redactEngineLine(
  String line, {
  Iterable<String> sessionSecrets = const [],
}) {
  var out = line;
  for (final secret in sessionSecrets) {
    if (secret.length < 2) continue;
    out = out.replaceAll(secret, _placeholder);
  }
  for (final (pattern, replace) in _shapes) {
    out = out.replaceAllMapped(pattern, replace);
  }
  return out;
}

const String _placeholder = '<redacted>';

final List<(RegExp, String Function(Match))> _shapes = [
  // `Authorization: Basic dXNlcjpwYXNz` — how this package's own credentials
  // reach rclone's log, and how a backend's reach it too. The scheme is kept
  // because "which kind of auth failed" is the useful half of the line.
  (
    RegExp(
      r'(Authorization\s*:\s*)(Basic|Bearer|Digest|AWS4-HMAC-SHA256)\s+\S+',
      caseSensitive: false,
    ),
    (m) => '${m[1]}${m[2]} $_placeholder',
  ),
  // The argv shape, which has no separator for a key/value rule to find.
  // rclone prints its own command line at high verbosity, and a host can pass
  // anything through `extraArgs` — including the flags this matches.
  (
    RegExp(
      r'(--[\w-]*(?:pass|token|secret|key|auth|credential|cookie)[\w-]*)(\s+|=)(?!-)(\S+)',
      caseSensitive: false,
    ),
    (m) => '${m[1]}${m[2]}$_placeholder',
  ),
  // `scheme://user:secret@host`, which is a whole credential in one token.
  (
    RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@'),
    (m) => '${m[1]}<credentials>@',
  ),
];
