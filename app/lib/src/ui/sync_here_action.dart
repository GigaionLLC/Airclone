import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/file_ops.dart';
import '../state/sync_source.dart';
import '../state/transfer_options.dart';
import '../state/transfer_service.dart';
import 'bisync_confirm.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';
import 'transfer_options_dialog.dart';

/// True while a [runMarkedSyncInto] call is in flight, so a double right-click
/// cannot stack two option dialogs or dispatch the same sync twice. Mirrors the
/// latch `paste_action.dart` uses for the same reason.
final _syncInFlightProvider = StateProvider<bool>((_) => false);

/// Sync the marked source into [destPath] on [destRemote].
///
/// This is the second half of the mark-then-sync gesture: "Set as sync source"
/// records a folder, the user navigates anywhere — another folder, another
/// remote — and this runs the transfer into where they now are.
///
/// The gesture's own hazard is the gap between the two halves. In the two-pane
/// flow both endpoints are on screen at the moment you commit; here the source
/// was chosen minutes ago and may since have been renamed, emptied or deleted,
/// and a one-way Sync from an empty source deletes everything at the
/// destination. So this preflights before it offers any options:
///
///  * overlapping paths are REFUSED outright ([syncTargetRefusal]);
///  * an unreadable or empty source is refused too, fail-closed — the same rule
///    `paste_action.dart` applies to an unreadable destination: if we cannot see
///    what is there, we do not write over it.
///
/// Only then does the existing options dialog open, pre-aimed at Sync, with its
/// own destructive-run confirm intact.
Future<void> runMarkedSyncInto(
  BuildContext context,
  WidgetRef ref, {
  required Remote destRemote,
  required String destPath,
  required int paneIndex,
}) async {
  if (ref.read(_syncInFlightProvider)) return;
  final src = ref.read(syncSourceProvider);
  if (!src.isSet) return;
  final dstFs = '${destRemote.fs}$destPath';
  final dstLabel = '${destRemote.name}:$destPath';

  final refusal = syncTargetRefusal(srcFs: src.fs, dstFs: dstFs);
  if (refusal != null) {
    await _refuse(context, refusal);
    return;
  }

  ref.read(_syncInFlightProvider.notifier).state = true;
  try {
    // Read the source before offering to sync FROM it. A marker outlives the
    // folder it points at, and "0 files" is indistinguishable from "everything
    // at the destination is surplus" once rclone is running.
    final int count;
    try {
      final (n, _) = await ref.read(fileOpsProvider).folderSize(src.fs);
      count = n;
    } catch (_) {
      if (!context.mounted) return;
      await _refuse(
        context,
        "Couldn't read ${src.label}, so nothing was synced. The source may be "
        'offline, renamed or deleted — check it and mark it again.',
      );
      return;
    }
    if (count == 0) {
      if (!context.mounted) return;
      await _refuse(
        context,
        '${src.label} is empty or no longer exists. Syncing from it would '
        'delete everything in $dstLabel.',
      );
      return;
    }

    if (!context.mounted) return;
    final options = await showTransferOptionsDialog(
      context,
      fromLabel: src.label,
      toLabel: dstLabel,
      // The gesture said "sync", so the dialog opens on Sync rather than making
      // the user re-pick it. Everything else is the dialog's own default, and
      // its destructive-Sync confirm fires from isRunNow.
      initial: const TransferOptions(mode: TransferMode.sync),
      isRunNow: true,
    );
    if (options == null || !context.mounted) return;

    var effective = options;
    if (options.mode == TransferMode.bisync) {
      // An ad-hoc pair has no baseline, so TransferService would silently fire
      // --resync — the run that lets one side overwrite the other on conflict.
      // Same trap the two-pane flow documents; same confirm.
      final choice = await showBisyncBaselineConfirm(
        context,
        path1Label: src.label,
        path2Label: dstLabel,
      );
      if (choice == null) return;
      if (choice.dryRun) effective = options.copyWith(dryRun: true);
    }

    await ref
        .read(transferServiceProvider)
        .transferAdvancedRaw(
          srcFs: src.fs,
          dstFs: dstFs,
          srcLabel: src.label,
          dstLabel: dstLabel,
          options: effective,
        );
    await ref.read(paneProvider(paneIndex).notifier).refresh();
  } finally {
    ref.read(_syncInFlightProvider.notifier).state = false;
  }
}

/// A refusal, stated as a dialog rather than a snackbar: every one of these is
/// "the sync you asked for would have destroyed something", which is not a
/// message to let slide past in three seconds.
Future<void> _refuse(BuildContext context, String message) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final c = AircloneTheme.of(ctx);
      return AlertDialog(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        title: Text(
          'Nothing was synced',
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: DialogBody(
          width: 420,
          child: Text(
            message,
            style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
