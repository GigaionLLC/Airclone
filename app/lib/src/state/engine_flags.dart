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
