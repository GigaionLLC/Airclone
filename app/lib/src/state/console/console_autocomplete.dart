import '../engine_flags.dart';
import 'console_docs.dart';
import 'rclone_commands.dart';

/// What a suggestion inserts, for icon/styling + doc-link routing.
enum SuggestionKind { command, flag, remote }

/// One autocomplete suggestion under the cursor.
class Suggestion {
  const Suggestion({
    required this.value,
    required this.kind,
    this.help = '',
    this.docUrl,
    this.destructive = false,
  });

  /// The text inserted for the current token (e.g. `lsjson`, `--transfers`,
  /// `gdrive:`).
  final String value;
  final SuggestionKind kind;
  final String help;
  final String? docUrl;

  /// A danger hint (a destructive verb or a delete flag) for styling.
  final bool destructive;
}

/// A small curated set of the most-used global flags (Phase 2 MVP). Phase 2.5
/// swaps this for the full `options/info` + `config/providers` tables.
class _Flag {
  const _Flag(this.name, this.help, {this.destructive = false});
  final String name;
  final String help;
  final bool destructive;
}

const List<_Flag> _commonFlags = [
  _Flag('--dry-run', 'Do a trial run with no permanent changes'),
  _Flag('--verbose', 'Print lots more stuff (repeat for more)'),
  _Flag('--progress', 'Show progress during transfer'),
  _Flag('--transfers', 'Number of file transfers to run in parallel'),
  _Flag('--checkers', 'Number of checkers to run in parallel'),
  _Flag('--fast-list', 'Use recursive list if available; uses more memory'),
  _Flag('--max-depth', 'If set limits the recursion depth'),
  _Flag('--include', 'Include files matching pattern'),
  _Flag('--exclude', 'Exclude files matching pattern'),
  _Flag('--filter', 'Add a file filtering rule'),
  _Flag('--max-age', 'Only transfer files younger than this'),
  _Flag('--min-age', 'Only transfer files older than this'),
  _Flag('--files-only', 'Only list files (lsf)'),
  _Flag('--dirs-only', 'Only list directories'),
  _Flag('--recursive', 'Recurse into the listing'),
  _Flag('--human-readable', 'Print sizes in human-readable format'),
  _Flag('--dry-run', 'Do a trial run with no permanent changes'),
  _Flag(
    '--delete-excluded',
    'Delete files on dest excluded from sync',
    destructive: true,
  ),
  _Flag(
    '--delete-during',
    'When synchronizing, delete files during transfer',
    destructive: true,
  ),
];

/// The position + partial text of the token the cursor is completing.
class _Cursor {
  const _Cursor(this.index, this.partial);
  final int index; // token index being completed (0 = the verb)
  final String partial; // what's typed so far for this token
}

_Cursor _cursorOf(String draft) {
  final tokens = parseEngineFlags(draft);
  // A trailing space (or empty draft) means we're starting a NEW token.
  final atNew = draft.isEmpty || draft.endsWith(' ');
  if (atNew) return _Cursor(tokens.length, '');
  return _Cursor(tokens.length - 1, tokens.isEmpty ? '' : tokens.last);
}

/// Rank + return suggestions for the current cursor position in [draft].
///
/// - completing token[0] → subcommands (blocked verbs hidden),
/// - a `-`-prefixed token → global flags,
/// - otherwise → configured [remotes] as `name:`.
/// Prefix matches rank above substring matches; capped at [limit].
List<Suggestion> suggestFor(
  String draft, {
  List<String> remotes = const [],
  // Generous cap so the whole remote list is offered (users often have many
  // remotes); the popover is height-bounded and scrolls. Prefix filtering
  // narrows commands/flags well below this anyway.
  int limit = 50,
}) {
  final cur = _cursorOf(draft);
  final q = cur.partial.toLowerCase();

  Iterable<Suggestion> pool;
  if (cur.index == 0) {
    pool = kRcloneCommands.values
        .where((c) => c.tier != CommandTier.blocked)
        .map(
          (c) => Suggestion(
            value: c.name,
            kind: SuggestionKind.command,
            help: c.help,
            docUrl: RcloneDocs.commandUrl(c.name),
            destructive: c.tier == CommandTier.destructive,
          ),
        );
  } else if (cur.partial.startsWith('-')) {
    pool = _commonFlags.map(
      (f) => Suggestion(
        value: f.name,
        kind: SuggestionKind.flag,
        help: f.help,
        docUrl: RcloneDocs.flagUrl(f.name),
        destructive: f.destructive,
      ),
    );
  } else {
    pool = remotes.map(
      (r) =>
          Suggestion(value: '$r:', kind: SuggestionKind.remote, help: 'remote'),
    );
  }

  final matches = pool.where((s) => s.value.toLowerCase().contains(q)).toList()
    ..sort((a, b) {
      final ap = a.value.toLowerCase().startsWith(q) ? 0 : 1;
      final bp = b.value.toLowerCase().startsWith(q) ? 0 : 1;
      if (ap != bp) return ap - bp;
      return a.value.compareTo(b.value);
    });

  // De-dupe (the flag list intentionally repeats --dry-run for grouping).
  final seen = <String>{};
  final unique = [
    for (final s in matches)
      if (seen.add(s.value)) s,
  ];
  return unique.take(limit).toList();
}

/// Replace the current token in [draft] with [value] and append a trailing
/// space, ready for the next token. Used when a suggestion is accepted.
String applySuggestion(String draft, String value) {
  final cur = _cursorOf(draft);
  final tokens = parseEngineFlags(draft);
  final atNew = draft.isEmpty || draft.endsWith(' ');
  final kept = atNew ? tokens : tokens.take(cur.index).toList();
  // Re-quote tokens that contain spaces so a previously-quoted path isn't split
  // into multiple args when the line is re-tokenized.
  String q(String t) => (t.contains(' ') || t.isEmpty) ? '"$t"' : t;
  return '${[...kept, value].map(q).join(' ')} ';
}
