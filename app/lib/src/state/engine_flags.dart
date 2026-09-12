import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-provided extra command-line flags appended when Airclone spawns the
/// rclone engine (`rclone rcd ...`). Stored as a raw string; tokenize with
/// [parseEngineFlags] before passing to the process.
class EngineFlags extends Notifier<String> {
  static const _key = 'engine_flags';

  @override
  String build() {
    _load();
    return '';
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getString(_key) ?? '';
    } catch (_) {
      // keep default
    }
  }

  Future<void> set(String value) async {
    state = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, value);
    } catch (_) {
      // best-effort
    }
  }
}

final engineFlagsProvider = NotifierProvider<EngineFlags, String>(
  EngineFlags.new,
);

/// Whether [flag]'s leading token (e.g. `--fast-list` or the `--transfers` of
/// `--transfers 8`) is present in [raw].
bool hasEngineFlag(String raw, String flag) {
  final name = flag.split(' ').first;
  return parseEngineFlags(raw).contains(name);
}

/// Toggles a preset [flag] (a bare `--name` or a `--name value` pair) in [raw]:
/// removes it (and its value, for the pair form) if its leading token is already
/// present, otherwise appends it. Returns the new flags string. Used by the
/// engine-flag preset chips; the free-text field stays the source of truth, so
/// the two never desync.
String toggleEngineFlag(String raw, String flag) {
  final parts = flag.split(' ').where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return raw;
  final name = parts.first;
  final tokens = parseEngineFlags(raw);
  if (!tokens.contains(name)) {
    return [...tokens, ...parts].join(' ');
  }
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] == name) {
      if (parts.length > 1 && i + 1 < tokens.length) i++; // also drop its value
      continue;
    }
    out.add(tokens[i]);
  }
  return out.join(' ');
}

/// Tokenizes a raw flags string into argv-style tokens.
///
/// Splits on whitespace, but a double-quoted substring becomes ONE token with
/// its surrounding quotes stripped. Repeated whitespace is collapsed and empty
/// tokens are ignored. An unbalanced opening quote treats the remainder of the
/// string as a single token.
///
/// Examples:
///   parseEngineFlags('--transfers 8 --bwlimit "10 M"')
///     => ['--transfers', '8', '--bwlimit', '10 M']
///   parseEngineFlags('')        => []
///   parseEngineFlags('  --fast-list ') => ['--fast-list']
List<String> parseEngineFlags(String raw) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  var hasToken = false;

  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == '"') {
      // Toggle quote mode; the quote itself is stripped. Entering quotes marks
      // the start of a token even if the quoted run is empty ("").
      inQuotes = !inQuotes;
      hasToken = true;
    } else if (!inQuotes &&
        (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r')) {
      if (hasToken) {
        tokens.add(buffer.toString());
        buffer.clear();
        hasToken = false;
      }
    } else {
      buffer.write(ch);
      hasToken = true;
    }
  }

  if (hasToken) {
    tokens.add(buffer.toString());
  }

  return tokens;
}

/// Flags a user may not put in front of the engine, because each one unpicks
/// the rc listener's own protection.
///
/// Applied by [stripRcHardeningOverrides] at the point the ENGINE argv is built
/// — deliberately NOT inside [parseEngineFlags]. That function is the shared
/// quote-aware tokenizer, and the command console uses it too: stripping there
/// removed the tokens the console's own safety classifier looks for, so a
/// blocked flag became an invisible one and two of its tests went red. A
/// tokenizer should tokenize; policy belongs where the policy applies.
///
/// **Why a denylist and not flag ordering.** The engine builds its argv with the
/// user's flags FIRST and its own after, on the rule that rclone's parser lets
/// the last occurrence win. That defends against a REPEAT of the same flag — a
/// second `--rc-addr` cannot move the listener off loopback. It does nothing
/// about a DIFFERENT flag that changes the same behaviour: `--rc-no-auth` turns
/// authentication off outright and there is no later flag that turns it back
/// on, so ordering never protected against it at all.
///
/// The listener is loopback-bound with per-session credentials because rclone's
/// own documentation equates rc access to shell access as the user running it.
/// Anything that widens who may reach it, or removes the need to authenticate,
/// is refused rather than ordered around.
const Set<String> kRefusedEngineFlags = {
  '--rc-no-auth',
  '--rc-htpasswd',
  '--rc-allow-origin',
  '--rc-user',
  '--rc-pass',
  '--rc-addr',
  '--rc-cert',
  '--rc-key',
  '--rc-client-ca',
};

/// Drops any [kRefusedEngineFlags] from [tokens], and the value that follows a
/// flag which takes one.
///
/// Silent by design at this layer: this is a safety net under a settings field,
/// not the place to explain a refusal. The settings UI is where a user is told.
List<String> stripRcHardeningOverrides(List<String> tokens) {
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    // `--flag=value` carries its value with it; `--flag value` does not.
    final name = token.contains('=') ? token.split('=').first : token;
    if (!kRefusedEngineFlags.contains(name)) {
      out.add(token);
      continue;
    }
    // A refused flag that takes a separate value must swallow that value too,
    // or the value is left behind as a stray positional argument.
    final takesValue = name != '--rc-no-auth';
    if (takesValue && !token.contains('=') && i + 1 < tokens.length) i++;
  }
  return out;
}
