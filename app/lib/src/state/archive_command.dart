import 'package:flutter/foundation.dart';

/// The three `rclone archive` actions Airclone exposes from the file browser's
/// right-click menu. rclone has NO RC method for these (verified against
/// v1.74 `rc/list`), so — like config encryption — they run as a real `rclone`
/// subprocess (desktop + Android; not the pure-FFI engine, which has no binary).
/// Source and destination are ordinary `remote:path` strings, so archiving or
/// extracting ACROSS remotes (e.g. `gdrive:dir` → `s3:backup.zip`) works natively.
enum ArchiveOp { create, extract, list }

/// The archive formats `rclone archive create` supports (v1.74), each with its
/// canonical extension and a human label for the picker. `--format` is optional
/// (rclone guesses from the destination extension), but Airclone always passes it
/// explicitly so the result never depends on how the user typed the name.
enum ArchiveFormat {
  zip('zip', '.zip', 'Zip (.zip)'),
  tar('tar', '.tar', 'Tar (.tar)'),
  tarGz('tar.gz', '.tar.gz', 'Tar + gzip (.tar.gz)'),
  tarBz2('tar.bz2', '.tar.bz2', 'Tar + bzip2 (.tar.bz2)'),
  tarXz('tar.xz', '.tar.xz', 'Tar + xz (.tar.xz)'),
  tarZst('tar.zst', '.tar.zst', 'Tar + zstd (.tar.zst)'),
  tarLz4('tar.lz4', '.tar.lz4', 'Tar + lz4 (.tar.lz4)'),
  tarBr('tar.br', '.tar.br', 'Tar + brotli (.tar.br)');

  const ArchiveFormat(this.flag, this.ext, this.label);

  /// The value passed to `--format`.
  final String flag;

  /// The canonical file extension (with leading dot).
  final String ext;

  /// Human-readable picker label.
  final String label;
}

/// All extensions rclone recognises, longest-first so `.tar.gz` matches before
/// `.gz`/`.tar`. Maps to the [ArchiveFormat] that produced it. `.tgz` etc. alias
/// onto their canonical format.
const Map<String, ArchiveFormat> _extToFormat = {
  '.tar.gz': ArchiveFormat.tarGz,
  '.tgz': ArchiveFormat.tarGz,
  '.taz': ArchiveFormat.tarGz,
  '.tar.bz2': ArchiveFormat.tarBz2,
  '.tbz': ArchiveFormat.tarBz2,
  '.tbz2': ArchiveFormat.tarBz2,
  '.tar.xz': ArchiveFormat.tarXz,
  '.txz': ArchiveFormat.tarXz,
  '.tar.zst': ArchiveFormat.tarZst,
  '.tzst': ArchiveFormat.tarZst,
  '.tar.lz4': ArchiveFormat.tarLz4,
  '.tar.br': ArchiveFormat.tarBr,
  '.tar': ArchiveFormat.tar,
  '.zip': ArchiveFormat.zip,
};

/// A validated archive invocation: the argv to hand the rclone binary, plus the
/// human labels the job row shows. Pure data so [buildArchiveCommand] is
/// unit-tested without spawning anything.
@immutable
class ArchiveCommand {
  const ArchiveCommand({
    required this.args,
    required this.sourceLabel,
    required this.destLabel,
  });

  final List<String> args;
  final String sourceLabel;
  final String destLabel;
}

/// Guesses the [ArchiveFormat] from a file name's extension (longest match wins),
/// or null when it isn't a recognised archive extension. Used to drive the create
/// picker from a typed name and to decide whether a browser entry is extractable.
ArchiveFormat? archiveFormatForName(String name) {
  final lower = name.toLowerCase();
  for (final entry in _extToFormat.entries) {
    if (lower.endsWith(entry.key)) return entry.value;
  }
  return null;
}

/// True when [name] looks like an archive rclone can extract/list.
bool looksLikeArchive(String name) => archiveFormatForName(name) != null;

/// A default archive file name for compressing something called [sourceLeaf]
/// (a file or folder leaf name, no path) into [format] — e.g. `Photos` +
/// `tar.gz` → `Photos.tar.gz`.
String defaultArchiveName(String sourceLeaf, ArchiveFormat format) {
  final base = sourceLeaf.isEmpty ? 'archive' : sourceLeaf;
  return '$base${format.ext}';
}

/// Backslash-escapes the characters rclone treats as filter-glob metacharacters
/// (`\ * ? [ ] { }`) so a literal file name used as an `--include` pattern matches
/// ITSELF, not a glob. Without this, a multi-select compress of a file named e.g.
/// `data[1].csv` would emit `--include /data[1].csv`, whose `[1]` is a char class
/// matching `data1.csv` — silently archiving the wrong files. `replaceAllMapped`
/// scans the ORIGINAL string, so escaping `\`→`\\` and `*`→`\*` is unambiguous.
String escapeRcloneGlob(String name) =>
    name.replaceAllMapped(RegExp(r'[\\*?\[\]{}]'), (m) => '\\${m[0]}');

/// Builds the `rclone archive <op>` argv. Pure + total, so every branch and guard
/// is unit-tested without a process.
///
/// - [source]/[dest] are `remote:path` strings (cross-remote allowed).
/// - create/extract REQUIRE a [dest]; list must NOT have one.
/// - create passes `--format` (from [format]) and optional `--full-path`.
/// - [extraFlags] are already-tokenized advanced global flags (`--include`,
///   `--transfers N`, …) appended verbatim; the caller is responsible for their
///   validity (they come from a curated advanced UI, never raw user text here).
///
/// Throws [ArgumentError] on a missing/empty source, a missing dest for
/// create/extract, a dest supplied for list, or a create without a format.
ArchiveCommand buildArchiveCommand({
  required ArchiveOp op,
  required String source,
  String? dest,
  ArchiveFormat? format,
  bool fullPath = false,
  List<String> extraFlags = const [],
}) {
  if (source.trim().isEmpty) {
    throw ArgumentError.value(source, 'source', 'a source is required');
  }
  final needsDest = op != ArchiveOp.list;
  final hasDest = dest != null && dest.trim().isNotEmpty;
  if (needsDest && !hasDest) {
    throw ArgumentError.value(
      dest,
      'dest',
      'a destination is required for ${op.name}',
    );
  }
  if (op == ArchiveOp.list && hasDest) {
    throw ArgumentError.value(dest, 'dest', 'list takes no destination');
  }
  if (op == ArchiveOp.create && format == null) {
    throw ArgumentError.value(
      format,
      'format',
      'create needs an explicit format',
    );
  }

  final args = <String>['archive', op.name, source];
  if (hasDest) args.add(dest);
  if (op == ArchiveOp.create) {
    args
      ..add('--format')
      ..add(format!.flag);
    if (fullPath) args.add('--full-path');
  }
  args.addAll(extraFlags);

  return ArchiveCommand(
    args: args,
    sourceLabel: source,
    destLabel: hasDest ? dest : '',
  );
}
