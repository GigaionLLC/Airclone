import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/backup_prune.dart';
import '../state/backup_restore.dart';
import '../state/backup_retention.dart';
import '../state/browser_controller.dart';
import '../state/remotes_provider.dart';
import '../state/tasks_controller.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// Opens a backup's destination in the other pane, ready to copy out of.
///
/// This IS the restore. A backup destination is an ordinary remote folder, so
/// pointing the browser at it and letting the user copy back is a restore that
/// inherits the conflict preflight, the transfer options, the job list and the
/// progress UI — instead of a parallel implementation that would have to grow
/// each of those again, later and worse.
///
/// Returns a message to show, or null on success. The caller owns the SnackBar
/// because it has the messenger; this function owns the decisions.
Future<String?> openBackupForRestore(WidgetRef ref, TransferTask task) async {
  if (!canRestoreFrom(task)) {
    return 'Only backups can be restored from.';
  }
  final split = splitFs(task.dstFs);
  if (split == null) return 'That backup has no usable destination.';

  final remotes = await ref.read(remotesProvider.future);
  final remote = restoreRemoteFor(task, remotes);
  if (remote == null) {
    // Naming the remote is the useful half: "gdrive is gone" tells the user
    // what to reconnect, where "could not open backup" tells them nothing.
    return 'The remote "${split.remoteName}" no longer exists, '
        'so this backup cannot be opened.';
  }

  // The OTHER pane, deliberately: restoring is copying from the backup into
  // wherever the user already is, and putting the backup where they were
  // standing would take away the destination.
  final active = ref.read(activePaneProvider);
  final target = active == 0 ? 1 : 0;
  final pane = ref.read(paneProvider(target).notifier);
  await pane.open(remote);
  if (split.path.isNotEmpty) await pane.navigateTo(split.path);
  return null;
}

/// Shows what a version cleanup would delete, and deletes it only if asked.
///
/// The dialog is the dry run. [BackupPruner.prune] defaults to reporting rather
/// than deleting, so the list a user is looking at was produced by exactly the
/// code that will act on it — not by a separate preview that could disagree.
Future<void> showVersionCleanup(
  BuildContext context,
  WidgetRef ref,
  TransferTask task,
) async {
  final days = ref.read(backupRetentionProvider);
  final pruner = ref.read(backupPrunerProvider);

  // Dry run first, always.
  final preview = await pruner.prune(fs: task.dstFs, retentionDays: days);
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dctx) {
      final c = AircloneTheme.of(dctx);
      final n = preview.candidates.length;
      // versionBytes, not a fold written again here: the figure the user is
      // shown must come from the same place every other version total does.
      final bytes = versionBytes(preview.candidates);
      return AlertDialog(
        backgroundColor: c.surfaceRaised,
        title: const Text('Clean up old versions'),
        content: DialogBody(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preview.error != null)
                  Text(
                    'Could not read the backup folder, so nothing will be '
                    'deleted.\n\n${preview.error}',
                    style: TextStyle(color: c.error, fontSize: 12),
                  )
                else if (preview.abortedOverCap)
                  Text(
                    // The refusal explained rather than reported: a pass this
                    // large is more likely a bug than a real backlog.
                    '$n old versions would be deleted, which is more than one '
                    'cleanup will do at once. Nothing has been deleted. This '
                    'is unusual enough to be worth looking at the folder '
                    'yourself before continuing.',
                    style: TextStyle(color: c.warning, fontSize: 12),
                  )
                else if (n == 0)
                  Text(
                    'Nothing to clean up. Versions are kept for $days days.',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  )
                else ...[
                  Text(
                    'Delete $n old version${n == 1 ? '' : 's'} '
                    '(${_mb(bytes)}), kept from more than $days days ago?',
                    style: TextStyle(color: c.text, fontSize: 13),
                  ),
                  const SizedBox(height: Space.x2),
                  Text(
                    'Current files are never touched, and neither is a version '
                    'whose current file no longer exists — that one is the last '
                    'copy left.',
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                  const SizedBox(height: Space.x3),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: c.surfaceSunken,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.border),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(Space.x2),
                      children: [
                        for (final v in preview.candidates)
                          Text(
                            v.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(n == 0 || preview.error != null ? 'Close' : 'Cancel'),
          ),
          if (n > 0 && preview.error == null && !preview.abortedOverCap)
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              child: const Text('Delete them'),
            ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return;

  final done = await pruner.prune(
    fs: task.dstFs,
    retentionDays: days,
    dryRun: false,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        done.error != null
            ? 'Deleted ${done.deleted} before stopping: ${done.error}'
            : 'Deleted ${done.deleted} old version'
                  '${done.deleted == 1 ? '' : 's'}, '
                  'freeing ${_mb(done.bytesFreed)}.',
      ),
    ),
  );
}

String _mb(int bytes) {
  if (bytes <= 0) return '0 MB';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
