import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/file_ops.dart';
import '../state/sync_preview.dart';
import '../state/sync_source.dart';
import '../state/transfer_options.dart';
import '../state/transfer_service.dart';
import 'bisync_confirm.dart';
import 'dialog_body.dart';
import 'sync_preview_dialog.dart';
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
    // Check the source before offering to sync FROM it. A marker outlives the
    // folder it points at, and "0 files" is indistinguishable from "everything
    // at the destination is surplus" once rclone is running.
    //
    // ONE SHALLOW LISTING, not a recursive walk. This used to call
    // operations/size over the whole tree before any dialog appeared, which on
    // a 13,000-file source is several seconds of a window that has not changed
    // — reported, fairly, as the menu item doing nothing. The deep question is
    // asked later and only where it still matters.
    final empty = await ref.read(fileOpsProvider).isRootEmpty(src.fs);
    if (!context.mounted) return;
    if (empty == null) {
      await _refuse(
        context,
        "Couldn't read ${src.label}, so nothing was synced. The source may be "
        'offline, renamed or deleted — check it and mark it again.',
      );
      return;
    }
    if (empty) {
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
    // A dry run used to mean "dispatch the real job with DryRun set and read the
    // Transfers dock", where a Sync's whole question — how many files would be
    // DELETED — never appeared. Answer it here instead, then offer to run.
    if (options.dryRun && options.mode != TransferMode.bisync) {
      final SyncPreview? preview;
      final job = CompareJob();
      try {
        preview = await _withProgress<SyncPreview?>(
          context,
          buildSyncPreview(
            ref,
            srcFs: src.fs,
            dstFs: dstFs,
            options: options,
            job: job,
          ),
          label: 'Working out what would change…',
          onCancel: job.cancel,
        );
      } catch (e) {
        if (!context.mounted) return;
        await _refuse(
          context,
          "Couldn't compare $dstLabel with ${src.label}, so there is nothing "
          'to preview and nothing was run. ($e)',
        );
        return;
      }
      if (preview == null || !context.mounted) return;
      final go = await showSyncPreviewDialog(
        context,
        preview: preview,
        fromLabel: src.label,
        toLabel: dstLabel,
      );
      if (go != true || !context.mounted) return;
      // The preview WAS the dry run. Going ahead from it means the real thing.
      effective = options.copyWith(dryRun: false);
    }
    // The shallow check above cannot see a source that is a tree of EMPTY
    // DIRECTORIES: its root lists non-empty, it holds no files, and a one-way
    // sync from it still deletes everything at the destination. On the dry-run
    // path the preview answers that plainly ("would delete N, would copy 0").
    // Without a preview there is nothing between the user and that outcome, so
    // ask the expensive question here — after they have chosen a destructive
    // Sync, where a wait is expected, and cancellable.
    if (effective.mode == TransferMode.sync && !effective.dryRun) {
      final n = await _withProgress<int?>(
        context,
        ref.read(fileOpsProvider).folderSize(src.fs).then((r) => r.$1),
        label: 'Counting what is in ${src.label}…',
      );
      if (n == null || !context.mounted) return; // cancelled, or gone
      if (n == 0) {
        await _refuse(
          context,
          '${src.label} contains no files, so syncing from it would delete '
          'everything in $dstLabel. Nothing was run.',
        );
        return;
      }
    }

    if (effective.mode == TransferMode.bisync) {
      // An ad-hoc pair has no baseline, so TransferService would silently fire
      // --resync — the run that lets one side overwrite the other on conflict.
      // Same trap the two-pane flow documents; same confirm.
      final choice = await showBisyncBaselineConfirm(
        context,
        path1Label: src.label,
        path2Label: dstLabel,
      );
      if (choice == null) return;
      if (choice.dryRun) effective = effective.copyWith(dryRun: true);
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

/// Runs [work] behind a modal spinner.
///
/// [label] says which phase is running, because these can take minutes and
/// "working" without saying at what is indistinguishable from a hang. A user
/// reported the menu item doing nothing at all: it was reading the source, with
/// no indicator, before any dialog appeared.
///
/// [onCancel] makes the Cancel button real. Without it the only way out was to
/// close the dialog, which abandoned the wait while the job carried on running
/// on the engine - so the button has to stop the work, not just the waiting.
Future<T?> _withProgress<T>(
  BuildContext context,
  Future<T> work, {
  required String label,
  Future<void> Function()? onCancel,
}) async {
  final navigator = Navigator.of(context);
  var cancelled = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final c = AircloneTheme.of(ctx);
      return AlertDialog(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        content: DialogBody(
          width: 320,
          child: Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actions: onCancel == null
            ? null
            : [
                TextButton(
                  onPressed: () async {
                    cancelled = true;
                    await onCancel();
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
      );
    },
  );
  try {
    final out = await work;
    return cancelled ? null : out;
  } finally {
    // Pop the spinner whether the work succeeded or threw, or it becomes a
    // permanent modal barrier over the app. Cancel already popped it.
    if (!cancelled && navigator.canPop()) navigator.pop();
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
