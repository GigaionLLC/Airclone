import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_ops.dart';
import 'transfer_options.dart';

/// What a transfer WOULD do, worked out before it does it.
///
/// A dry run already existed and told you almost nothing: it dispatched a real
/// job with `DryRun` set, which arrives in the Transfers dock as a row reading
/// "Done" and a byte count. The one number a sync's dry run exists to produce —
/// how many files it would DELETE on the destination — was nowhere.
///
/// Measured with `operations/check` rather than by reading a dry run's
/// transfer log. That was an evidence-based choice: `core/transferred` does
/// carry the deletions (`what: "deleting"`), and its numbers match the real run
/// exactly, but it is a ring buffer capped at ~100 entries per group and
/// returned in completion order. A 300-file dry run comes back as 104 entries,
/// all deletions, with the transfers evicted — so a preview built on it quietly
/// lies on any sync big enough to need one. `operations/check` is uncapped,
/// sorted, and returns the buckets explicitly.
@immutable
class SyncPreview {
  const SyncPreview({
    required this.mode,
    required this.wouldCreate,
    required this.wouldOverwrite,
    required this.wouldDelete,
    required this.unchanged,
    required this.errors,
    required this.overwritesRecoverable,
    required this.someMayBeSkipped,
    required this.maxDeleteFiles,
  });

  final TransferMode mode;

  /// On the destination: files the source has and it does not.
  final List<String> wouldCreate;

  /// Present on both, with different content.
  final List<String> wouldOverwrite;

  /// Files the DESTINATION has and the source does not — removed by a one-way
  /// Sync, and by nothing else. Empty for Copy and Move.
  final List<String> wouldDelete;

  /// Files already identical; nothing happens to them.
  final int unchanged;

  /// Paths rclone could not compare at all (permissions, unreadable object).
  /// Reported rather than folded into "identical", because an unknown is not a
  /// match.
  final List<String> errors;

  /// `keepReplaced` is on, so an overwritten file is renamed `.replaced` rather
  /// than lost.
  final bool overwritesRecoverable;

  /// `skipNewer` is on, so some of [wouldOverwrite] may be left alone after all.
  /// A comparison cannot say which: rclone decides per file at run time, and
  /// saying "some of these" is honest where naming them would not be.
  final bool someMayBeSkipped;

  /// The run's `--max-delete` cap, if any.
  final int? maxDeleteFiles;

  bool get changesNothing =>
      wouldCreate.isEmpty && wouldOverwrite.isEmpty && wouldDelete.isEmpty;

  /// True when the deletions alone would trip `--max-delete` and rclone would
  /// ABORT the run. Worth knowing before starting rather than after: the cap is
  /// a guard, and tripping it means the sync does not happen at all.
  bool get wouldAbortOnMaxDelete =>
      maxDeleteFiles != null && wouldDelete.length > maxDeleteFiles!;
}

/// Maps a comparison onto what [o] would actually do with it.
///
/// The buckets are not the answer on their own — the same difference means
/// different things under different flags, and a preview that ignored them
/// would describe a transfer nobody asked for:
///  * only Sync deletes, so Copy and Move report no deletions at all;
///  * `skipExisting` (`--ignore-existing`) means a differing file is left
///    alone, so nothing would be overwritten.
///
/// Pure, so the mapping is tested without an engine.
SyncPreview previewFrom(CompareResult r, TransferOptions o) => SyncPreview(
  mode: o.mode,
  wouldCreate: r.missingOnDst,
  wouldOverwrite: o.skipExisting ? const [] : r.differ,
  wouldDelete: o.mode == TransferMode.sync ? r.missingOnSrc : const [],
  unchanged: r.match.length,
  errors: r.error,
  overwritesRecoverable: o.keepReplaced,
  someMayBeSkipped: o.skipNewer && !o.skipExisting && r.differ.isNotEmpty,
  maxDeleteFiles: o.mode == TransferMode.sync ? o.maxDeleteFiles : null,
);

/// The `_config` a preview must compare under, so its idea of "differs" is the
/// transfer's idea of it.
///
/// Only the keys that change the COMPARISON travel: `--size-only` and
/// `--checksum` decide whether two files count as equal, and the probe run
/// confirmed `operations/check` honours both. Everything else in a transfer's
/// config (transfers, checkers, order-by, the delete cap) changes what happens
/// to a difference, not whether there is one, and belongs in [previewFrom].
Map<String, dynamic> previewConfig(TransferOptions o) => switch (o.compare) {
  CompareMode.size => {'SizeOnly': true},
  CompareMode.checksum => {'Checksum': true},
  CompareMode.sizeModTime || null => const {},
};

/// Runs the comparison behind a preview. Null when the engine isn't ready.
Future<SyncPreview?> buildSyncPreview(
  WidgetRef ref, {
  required String srcFs,
  required String dstFs,
  required TransferOptions options,
}) async {
  final result = await ref
      .read(fileOpsProvider)
      .compare(
        srcFs,
        dstFs,
        config: previewConfig(options),
        filter: filterBlock(options),
      );
  return result == null ? null : previewFrom(result, options);
}
