import 'package:flutter/material.dart';

import '../state/sync_preview.dart';
import '../state/transfer_options.dart';
import 'dialog_body.dart';
import 'disclosure.dart';
import 'theme/tokens.dart';

/// Shows what a transfer would do and offers to run it for real.
///
/// Resolves true when the user chooses to go ahead, false/null otherwise.
///
/// The dry run this replaces dispatched a real job with `DryRun` set and left
/// the answer in the Transfers dock as a row saying "Done" beside a byte count.
/// For a Sync — the one mode that deletes — the number that matters was not on
/// screen anywhere. Here the deletions lead, and they are the only bucket
/// coloured like a warning.
Future<bool?> showSyncPreviewDialog(
  BuildContext context, {
  required SyncPreview preview,
  required String fromLabel,
  required String toLabel,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _SyncPreviewDialog(
    preview: preview,
    fromLabel: fromLabel,
    toLabel: toLabel,
  ),
);

class _SyncPreviewDialog extends StatefulWidget {
  const _SyncPreviewDialog({
    required this.preview,
    required this.fromLabel,
    required this.toLabel,
  });

  final SyncPreview preview;
  final String fromLabel;
  final String toLabel;

  @override
  State<_SyncPreviewDialog> createState() => _SyncPreviewDialogState();
}

class _SyncPreviewDialogState extends State<_SyncPreviewDialog> {
  /// Which bucket's file list is open. At most one, so the dialog cannot grow
  /// past the screen on a plan with thousands of changes in several buckets.
  String? _open;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final p = widget.preview;
    final verb = switch (p.mode) {
      TransferMode.copy => 'Copy',
      TransferMode.move => 'Move',
      TransferMode.sync => 'Sync',
      TransferMode.bisync => 'Two-way sync',
    };
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      title: Text(
        p.changesNothing ? 'Nothing to $verb' : 'What this $verb would do',
        style: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: DialogBody(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.fromLabel}  →  ${widget.toLabel}',
              style: TextStyle(color: c.textFaint, fontSize: 12),
            ),
            const SizedBox(height: Space.x3),
            if (p.changesNothing)
              Text(
                'The destination already matches the source. Running it would '
                'transfer nothing and delete nothing.',
                style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
              )
            else ...[
              // Deletions first and in the error colour: this is the bucket a
              // preview exists for, and burying it under "12 new files" is how
              // it goes unread.
              if (p.wouldDelete.isNotEmpty)
                _bucket(
                  c,
                  id: 'delete',
                  icon: Icons.delete_outline,
                  color: c.error,
                  label:
                      'Delete ${_n(p.wouldDelete.length)} on the destination',
                  detail: 'Present there, absent from the source.',
                  files: p.wouldDelete,
                ),
              if (p.wouldOverwrite.isNotEmpty)
                _bucket(
                  c,
                  id: 'overwrite',
                  icon: Icons.sync_alt,
                  color: c.warning,
                  label: 'Overwrite ${_n(p.wouldOverwrite.length)}',
                  detail: p.overwritesRecoverable
                      ? 'The current versions are kept, renamed ".replaced".'
                      : p.someMayBeSkipped
                      ? 'Some may be left alone — "skip newer" is on, and which '
                            'ones is decided per file as it runs.'
                      : 'Present on both, with different contents.',
                  files: p.wouldOverwrite,
                ),
              if (p.wouldCreate.isNotEmpty)
                _bucket(
                  c,
                  id: 'create',
                  icon: Icons.add,
                  color: c.success,
                  label: 'Copy ${_n(p.wouldCreate.length)} across',
                  detail: 'On the source, not on the destination yet.',
                  files: p.wouldCreate,
                ),
            ],
            if (p.unchanged > 0) ...[
              const SizedBox(height: Space.x2),
              Text(
                '${_n(p.unchanged)} already identical — untouched.',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
            ],
            if (p.errors.isNotEmpty)
              _bucket(
                c,
                id: 'errors',
                icon: Icons.help_outline,
                color: c.warning,
                label: "${_n(p.errors.length)} couldn't be compared",
                detail:
                    'Unreadable or inaccessible. What happens to these is not '
                    'predicted here.',
                files: p.errors,
              ),
            if (p.wouldAbortOnMaxDelete) ...[
              const SizedBox(height: Space.x3),
              _warning(
                c,
                'This would not run. Your delete cap is '
                '${p.maxDeleteFiles}, and ${p.wouldDelete.length} deletions '
                'exceed it, so rclone would stop before transferring '
                'anything. Raise the cap if the deletions are expected.',
              ),
            ],
            if (p.mode == TransferMode.move) ...[
              const SizedBox(height: Space.x3),
              _warning(
                c,
                'Move also removes the copied files from the source once they '
                'land. That part is not shown above.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Close', style: TextStyle(color: c.textMuted)),
        ),
        FilledButton(
          style: p.wouldDelete.isEmpty
              ? null
              : FilledButton.styleFrom(backgroundColor: c.error),
          onPressed: p.changesNothing
              ? null
              : () => Navigator.of(context).pop(true),
          child: Text(
            p.wouldDelete.isEmpty
                ? 'Run it'
                : 'Run it, deleting ${p.wouldDelete.length}',
          ),
        ),
      ],
    );
  }

  static String _n(int n) => n == 1 ? '1 file' : '$n files';

  Widget _warning(AircloneColors c, String text) => Container(
    padding: const EdgeInsets.all(Space.x2),
    decoration: BoxDecoration(
      color: c.warningBg,
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 15, color: c.warning),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: c.textMuted, fontSize: 11, height: 1.35),
          ),
        ),
      ],
    ),
  );

  /// One outcome, with its file list one click away. Counts answer "is this
  /// what I expected"; the names answer "which ones", and only the second needs
  /// the room.
  Widget _bucket(
    AircloneColors c, {
    required String id,
    required IconData icon,
    required Color color,
    required String label,
    required String detail,
    required List<String> files,
  }) {
    final expanded = _open == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Disclosure(
        label: label,
        summary: detail,
        expanded: expanded,
        onToggle: () => setState(() => _open = expanded ? null : id),
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            width: double.infinity,
            padding: const EdgeInsets.all(Space.x2),
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Text(
                  files.join('\n'),
                  style: TextStyle(color: color, fontSize: 11, height: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
