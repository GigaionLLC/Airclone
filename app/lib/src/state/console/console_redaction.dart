import 'console_command.dart';

/// Placeholder that replaces any redacted secret. Re-run of a stored command
/// containing this sentinel prompts for the secret rather than replaying it.
const String kRedacted = '‹redacted›';

/// Flag names whose VALUE is a secret (matched case-insensitively on the name,
/// before any `=value`). Covers backend password/key/token/secret flags plus the
/// rc auth flags. Deny-list shaped — the output scrubber ([redactOutputLine]) is
/// the backstop for anything a novel flag name misses.
final RegExp _secretFlag = RegExp(
  r'^--(.*-)?(pass|password|key|secret|token|auth|sas-url|account-key|client-secret|client-id)$'
  r'|^--rc-(pass|user)$',
  caseSensitive: false,
);

/// Secret keys inside an rclone connection string
/// (`:sftp,host=h,pass=xxx:path`) — redact their `=value`.
final RegExp _connStringSecret = RegExp(
  r'(?<=[,:])(pass|password|key|secret|token|client_secret|sas_url)=([^,:]*)',
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

/// True if the command asks for high-verbosity dumps that can echo credentials
/// (`-vv`, `--verbose 2`+, any `--dump …`). The console refuses these rather than
/// trying to scrub freeform dump output (block-over-scrub).
bool hasCredentialDump(ConsoleCommand cmd) {
  for (var i = 0; i < cmd.args.length; i++) {
    final a = cmd.args[i];
    final name = flagName(a);
    if (name == '--dump' || name.startsWith('--dump-')) return true;
    if (a == '-vv' || a == '-vvv') return true;
    if (name == '--verbose' || name == '-v') {
      // --verbose 2 / -v 2 (a following numeric >= 2), or --verbose=2
      final eq = a.indexOf('=');
      final val = eq >= 0
          ? a.substring(eq + 1)
          : (i + 1 < cmd.args.length ? cmd.args[i + 1] : '');
      if ((int.tryParse(val) ?? 0) >= 2) return true;
    }
  }
  return false;
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
