import '../engine_flags.dart';
import 'rclone_commands.dart';

/// A parsed console command line — **argv, never a shell string**.
///
/// We tokenize with [parseEngineFlags] (the same quote-aware tokenizer the
/// engine-flags box uses), take `token[0]` as the verb, and pass everything else
/// through verbatim. Nothing is ever concatenated into a string handed to a
/// shell, so shell-metacharacter injection is a non-issue by construction. All
/// safety classification is done on these parsed tokens.
class ConsoleCommand {
  const ConsoleCommand(this.tokens);

  factory ConsoleCommand.parse(String raw) =>
      ConsoleCommand(parseEngineFlags(raw));

  /// The full tokenization of the command line.
  final List<String> tokens;

  bool get isEmpty => tokens.isEmpty;

  /// The leading verb (`token[0]`), e.g. `ls`, `copy`, `sync`.
  String get verb => tokens.isEmpty ? '' : tokens.first;

  /// Everything after the verb — positional args AND flags, verbatim.
  List<String> get args => tokens.length <= 1 ? const [] : tokens.sublist(1);

  /// Just the flag tokens (start with `-`), for classification/help.
  List<String> get flags => args.where((t) => t.startsWith('-')).toList();

  /// The safety tier, considering the verb and its flags (see [classifyTier]).
  CommandTier get tier => classifyTier(verb, flags);

  bool get isDryRun =>
      flags.map(flagName).contains('--dry-run') || flags.contains('-n');

  /// `core/command` params. `command` is the verb; everything else (positional
  /// args AND flags) goes into `arg` verbatim — rclone parses the flags from the
  /// arg list exactly as it would on a real CLI, so there is no shell and no
  /// opt-splitting to get wrong. `returnType` defaults to the buffered form.
  Map<String, dynamic> toRcParams({String returnType = 'COMBINED_OUTPUT'}) => {
    'command': verb,
    'arg': args,
    'returnType': returnType,
  };

  /// A copy with `--dry-run` appended (idempotent) — the destructive preview run.
  ConsoleCommand withDryRun() =>
      isDryRun ? this : ConsoleCommand([...tokens, '--dry-run']);

  /// The exact command that will run, `rclone`-prefixed, tokens quoted where
  /// they contain spaces. Secret redaction is layered on in Phase 2.
  String preview() => 'rclone ${tokens.map(_quote).join(' ')}';

  static String _quote(String t) => (t.contains(' ') || t.isEmpty) ? '"$t"' : t;
}

/// A flag token's name without any `=value` suffix
/// (`--max-depth=1` → `--max-depth`). Shared with the catalog classifier.
String flagName(String flag) {
  final eq = flag.indexOf('=');
  return eq < 0 ? flag : flag.substring(0, eq);
}
