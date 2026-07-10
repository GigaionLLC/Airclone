import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// One-time two-way-sync (bisync) baseline confirm for an ad-hoc run started
/// from the browser (no saved task backing it). The FIRST two-way sync of a
/// pair runs `--resync` to build its baseline: on any conflict the chosen
/// winner's file overwrites the other side, so it is destructive. Returns
/// `(dryRun: false)` to establish the baseline for real, `(dryRun: true)` to
/// preview it first, or `null` if the user cancels.
Future<({bool dryRun})?> showBisyncBaselineConfirm(
  BuildContext context, {
  required String path1Label,
  required String path2Label,
}) => showDialog<({bool dryRun})>(
  context: context,
  builder: (ctx) {
    final c = AircloneTheme.of(ctx);
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      title: Text(
        'Establish two-way baseline',
        style: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The first two-way sync matches both folders. It runs a one-time '
              'baseline (--resync): where the two sides differ, the winning '
              'side overwrites the other. This cannot be undone.',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const SizedBox(height: Space.x3),
            _pathRow(c, 'Path1', path1Label),
            _pathRow(c, 'Path2', path2Label),
            const SizedBox(height: Space.x3),
            Text(
              'Tip: save this as a task instead — Airclone then tracks the '
              'baseline, so later runs are ordinary two-way syncs.',
              style: TextStyle(color: c.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.x4,
        0,
        Space.x4,
        Space.x4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Cancel', style: TextStyle(color: c.textMuted)),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop((dryRun: true)),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.text,
            side: BorderSide(color: c.borderStrong),
          ),
          child: const Text('Dry run first'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.error,
            foregroundColor: c.onPrimary,
          ),
          onPressed: () => Navigator.of(ctx).pop((dryRun: false)),
          child: const Text('Establish baseline'),
        ),
      ],
    );
  },
);

/// A `Path1: remote:dir` row, mirroring the saved-task baseline dialog so the
/// two confirms read the same.
Widget _pathRow(AircloneColors c, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 2),
  child: Row(
    children: [
      SizedBox(
        width: 48,
        child: Text(
          label,
          style: TextStyle(
            color: c.textFaint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
);
