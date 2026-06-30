/// What to do when pasted/dropped files collide with existing names.
enum ConflictChoice { skip, overwrite, keepBoth, cancel }

/// A planned paste: copy/move source name [src] to destination name [dst].
typedef PastePlan = ({String src, String dst});

/// Resolves [names] against [destNames] under [choice] into the concrete set of
/// transfers to run:
/// - [ConflictChoice.skip]: colliding names are dropped.
/// - [ConflictChoice.overwrite]: every name kept as-is (rclone replaces).
/// - [ConflictChoice.keepBoth]: each name routed through [uniqueName] against a
///   running set so nothing (existing or newly-assigned) is clobbered.
/// [ConflictChoice.cancel] is handled by the caller and yields an empty plan.
List<PastePlan> planPaste(
  List<String> names,
  Set<String> destNames,
  ConflictChoice choice,
) {
  if (choice == ConflictChoice.cancel) return const [];
  final out = <PastePlan>[];
  final taken = {...destNames};
  for (final name in names) {
    final collides = destNames.contains(name);
    if (collides && choice == ConflictChoice.skip) continue;
    var dst = name;
    if (choice == ConflictChoice.keepBoth) {
      dst = uniqueName(name, taken);
      taken.add(dst);
    }
    out.add((src: name, dst: dst));
  }
  return out;
}

/// Returns [name] if free, else the first `name (2)`, `name (3)`… not in
/// [existing]. The numeric suffix goes before the extension (the last `.`),
/// matching how desktop file managers de-duplicate: `report.pdf` →
/// `report (2).pdf`. Dotfiles (`.gitignore`) and extension-less names get the
/// suffix at the end.
String uniqueName(String name, Set<String> existing) {
  if (!existing.contains(name)) return name;
  final dot = name.lastIndexOf('.');
  final hasExt = dot > 0; // dot == 0 → dotfile, treat as no extension
  final base = hasExt ? name.substring(0, dot) : name;
  final ext = hasExt ? name.substring(dot) : '';
  for (var i = 2; ; i++) {
    final candidate = '$base ($i)$ext';
    if (!existing.contains(candidate)) return candidate;
  }
}
