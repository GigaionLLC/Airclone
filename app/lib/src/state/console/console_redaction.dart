import 'console_command.dart';

/// Placeholder that replaces any redacted secret. Re-run of a stored command
/// containing this sentinel prompts for the secret rather than replaying it.
const String kRedacted = '‹redacted›';

/// Flag names whose VALUE is a secret. The secret keyword may appear ANYWHERE in
/// the flag name (not just at the end), so `--crypt-password2`,
/// `--drive-service-account-credentials`, and `--sftp-key-pem` are all caught.
/// Redaction is display-only (the real command runs with the real value), so
/// over-matching a non-secret flag is a safe default.
final RegExp _secretFlag = RegExp(
  r'^--.*(pass|password|key|secret|token|auth|credential|sas-url|account-key|client-secret|client-id|pem)'
  r'|^--rc-(pass|user)$',
  caseSensitive: false,
);

/// Secret keys inside an rclone connection string
/// (`:sftp,host=h,pass=xxx:path` or `:s3,secret_access_key=…:path`) — redact
/// their `=value`. Matches compound keys (the secret word anywhere in the key).
final RegExp _connStringSecret = RegExp(
  r'(?<=[,:])([^,:=]*(?:pass(?:word)?|secret|token|key|sas[_-]?url|credential)[^,:=]*)=([^,:]*)',
  caseSensitive: false,
);

bool isSecretFlag(String name) => _secretFlag.hasMatch(name);

/// Redacts secrets in a tokenized command, returning display-safe tokens:
/// - a secret flag's value (`--sftp-pass X` → `--sftp-pass ‹redacted›`, and the
///   `--sftp-pass=X` form),
/// - secret `key=value` pairs embedded in a connection-string arg token.
List<String> redactTokens(List<String> tokens) {
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.startsWith('-')) {
      final eq = t.indexOf('=');
      final name = eq < 0 ? t : t.substring(0, eq);
      if (isSecretFlag(name)) {
        if (eq >= 0) {
          out.add('$name=$kRedacted');
        } else {
          out.add(t);
          // The value is the next token, if it isn't itself another flag.
          if (i + 1 < tokens.length && !tokens[i + 1].startsWith('-')) {
            out.add(kRedacted);
            i++;
          }
        }
        continue;
      }
    }
    out.add(t.replaceAllMapped(_connStringSecret, (m) => '${m[1]}=$kRedacted'));
  }
  return out;
}

/// True if the command asks for DEBUG-level verbosity or a header/body dump that
/// can echo credentials — the console REFUSES these (block over scrub). Catches:
/// any `--dump*`; `--log-level DEBUG`; and an effective `-v` count >= 2 whether
/// written as `-vv`/`-vvvv`, a combined cluster (`-vvP`), repeated `-v -v`, or
/// `--verbose 2`.
bool hasCredentialDump(ConsoleCommand cmd) {
  final args = cmd.args;
  var vCount = 0;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    final name = flagName(a);
    if (name == '--dump' || name.startsWith('--dump-')) return true;
    if (name == '--log-level') {
      final eq = a.indexOf('=');
      final val =
          (eq >= 0
                  ? a.substring(eq + 1)
                  : (i + 1 < args.length ? args[i + 1] : ''))
              .toUpperCase();
      if (val == 'DEBUG') return true;
      continue;
    }
    if (name == '--verbose') {
      final eq = a.indexOf('=');
      final val = eq >= 0
          ? a.substring(eq + 1)
          : (i + 1 < args.length ? args[i + 1] : '');
      vCount += int.tryParse(val) ?? 1; // bare --verbose == 1
    } else if (RegExp(r'^-[a-zA-Z]*v[a-zA-Z]*$').hasMatch(a)) {
      // A short-flag cluster containing v(s): -v, -vv, -vvvv, -vvP, -Pv, …
      vCount += a.substring(1).split('').where((ch) => ch == 'v').length;
    }
  }
  return vCount >= 2;
}

/// A redacted, display-safe rendering of a command (the exact-command preview +
/// stored history use this).
String redactedPreview(ConsoleCommand cmd) =>
    'rclone ${redactTokens(cmd.tokens).map((t) => (t.contains(' ') || t.isEmpty) ? '"$t"' : t).join(' ')}';

/// Patterns of secrets that can appear in a command's OUTPUT (auth headers,
/// bearer tokens, AWS sig credentials, `token=` query params). Applied to every
/// output line BEFORE it enters the scrollback or persisted history.
final List<(RegExp, String Function(Match))> _outputScrubbers = [
  (
    RegExp(r'(Authorization:\s*)(\S+.*)', caseSensitive: false),
    (m) => '${m[1]}$kRedacted',
  ),
  (
    RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]+', caseSensitive: false),
    (m) => '${m[1]}$kRedacted',
  ),
  (
    RegExp(r'(X-Auth-Token:\s*)(\S+)', caseSensitive: false),
    (m) => '${m[1]}$kRedacted',
  ),
  (
    RegExp(r'(Credential=)[A-Za-z0-9/\-]+', caseSensitive: false),
    (m) => '${m[1]}$kRedacted',
  ),
  (
    RegExp(
      r'((?:access_?token|token|password|pass|secret)=)[^&\s"]+',
      caseSensitive: false,
    ),
    (m) => '${m[1]}$kRedacted',
  ),
];

/// Scrubs known secret shapes from one output line before display/persist.
String redactOutputLine(String line) {
  var s = line;
  for (final (re, repl) in _outputScrubbers) {
    s = s.replaceAllMapped(re, repl);
  }
  return s;
}
