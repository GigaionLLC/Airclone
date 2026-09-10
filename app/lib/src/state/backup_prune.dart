import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import 'backup_retention.dart';
import 'engine_controller.dart';

/// The most deletions one prune pass will perform before refusing.
///
/// The same reasoning as the scheduled delete cap, for the same reason: a prune
/// is a delete loop over a remote, and the case worth guarding is not a slightly
/// large backup but a bug or a misconfiguration that makes *everything* look
/// prunable. Aborting at 500 and saying so is recoverable; deleting 40,000
/// files is not.
const int kMaxPrunePerPass = 500;

/// What a prune did, or would do.
typedef PruneResult = ({
  /// The versions identified as prunable.
  List<RcloneFile> candidates,

  /// How many were actually deleted. Zero for a dry run.
  int deleted,

  /// Bytes the deleted versions were holding.
  int bytesFreed,

  /// Set when the pass refused because [kMaxPrunePerPass] was exceeded. The
  /// candidates are still reported so a human can look at them.
  bool abortedOverCap,

  /// The first engine error, if deleting stopped early.
  String? error,
});

/// Deletes old versions from a backup folder, or reports what it would delete.
///
/// **Dry run by default.** Every caller has to opt in to deleting, which is the
/// right default for the most destructive operation in the app — and it means
/// the UI can show the user what is about to happen using exactly the code that
/// will happen.
///
/// The decision about *what* to delete is not here: it is
/// [prunableVersionsRecursive], which is pure and tested without a network. This
/// class only lists, asks, and deletes.
class BackupPruner {
  BackupPruner(this._ref);

  final Ref _ref;

  /// Lists [fs] recursively and prunes versions older than [retentionDays].
  ///
  /// [now] is injected so a caller (and a test) controls the cutoff rather than
  /// inheriting whatever the clock says mid-run.
  Future<PruneResult> prune({
    required String fs,
    required int retentionDays,
    bool dryRun = true,
    int maxPerPass = kMaxPrunePerPass,
    DateTime? now,
  }) async {
    const empty = <RcloneFile>[];
    final client = _ref.read(engineControllerProvider).client;
    if (client == null) {
      return (
        candidates: empty,
        deleted: 0,
        bytesFreed: 0,
        abortedOverCap: false,
        error: 'The rclone engine is not running.',
      );
    }

    final List<RcloneFile> entries;
    try {
      final res = await client.rpc('operations/list', {
        'fs': fs,
        'remote': '',
        // Recursive, files only: a folder is never a version and listing them
        // would only add noise the grouping then has to ignore.
        'opt': {'recurse': true, 'filesOnly': true, 'showHash': false},
      });
      final list = res['list'];
      if (list is! List) {
        return (
          candidates: empty,
          deleted: 0,
          bytesFreed: 0,
          abortedOverCap: false,
          error: 'The backup folder could not be listed.',
        );
      }
      entries = [
        for (final e in list)
          if (e is Map<String, dynamic>) RcloneFile.fromJson(e),
      ];
    } catch (e) {
      // A listing that failed means we do not know what is there, and deleting
      // on a guess is exactly what must not happen.
      return (
        candidates: empty,
        deleted: 0,
        bytesFreed: 0,
        abortedOverCap: false,
        error: '$e',
      );
    }

    final candidates = prunableVersionsRecursive(
      entries: entries,
      retentionDays: retentionDays,
      now: now ?? DateTime.now(),
    );

    if (candidates.length > maxPerPass) {
      // Deliberately not "delete the first 500". A pass this large is more
      // likely a bug than a real backlog, and truncating would destroy data
      // while hiding the reason.
      return (
        candidates: candidates,
        deleted: 0,
        bytesFreed: 0,
        abortedOverCap: true,
        error: null,
      );
    }

    if (dryRun) {
      return (
        candidates: candidates,
        deleted: 0,
        bytesFreed: 0,
        abortedOverCap: false,
        error: null,
      );
    }

    var deleted = 0;
    var freed = 0;
    for (final v in candidates) {
      try {
        await client.rpc('operations/deletefile', {'fs': fs, 'remote': v.path});
        deleted++;
        freed += v.size < 0 ? 0 : v.size;
      } catch (e) {
        // Stop at the first failure rather than pressing on: whatever broke may
        // break the next one differently, and a partial prune the user can see
        // beats a long one they cannot explain.
        return (
          candidates: candidates,
          deleted: deleted,
          bytesFreed: freed,
          abortedOverCap: false,
          error: '$e',
        );
      }
    }
    return (
      candidates: candidates,
      deleted: deleted,
      bytesFreed: freed,
      abortedOverCap: false,
      error: null,
    );
  }
}

final backupPrunerProvider = Provider<BackupPruner>(BackupPruner.new);
