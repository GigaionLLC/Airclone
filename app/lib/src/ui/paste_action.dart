import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/clipboard_controller.dart';
import '../state/engine_controller.dart';
import '../state/name_conflict.dart';
import '../state/transfer_service.dart';
import 'copy_conflict_dialog.dart';
import 'pane_drag.dart' show joinPath;

/// The single conflict-aware "paste the clipboard into [dest]" routine shared by
/// the keyboard shortcut (home screen) and the per-pane context menu, so both
/// entry points behave identically. When pasted names already exist in [dest],
/// the user is asked to Skip / Replace / Keep both; otherwise it pastes
/// straight through. Refreshes pane [paneIndex] afterwards.
Future<void> pasteClipboardInto(
  BuildContext context,
  WidgetRef ref, {
  required BrowserState dest,
  required int paneIndex,
}) async {
  final remote = dest.remote;
  if (remote == null) return;
  await pasteClipboardIntoFolder(
    context,
    ref,
    destRemote: remote,
    destPath: dest.path,
    refreshPaneIndex: paneIndex,
    // The pane's listing is already loaded — collision-check for free.
    knownNames: dest.entries.map((e) => e.name),
  );
}

/// Conflict-aware paste into an arbitrary [destRemote]+[destPath] (e.g. a
/// subfolder the user right-clicked "Paste" onto). When [knownNames] is null
/// the destination folder is listed first (read-only) to detect collisions;
/// pass it when the caller already holds the listing to skip that round-trip.
Future<void> pasteClipboardIntoFolder(
  BuildContext context,
  WidgetRef ref, {
  required Remote destRemote,
  required String destPath,
  required int refreshPaneIndex,
  Iterable<String>? knownNames,
}) async {
  final clip = ref.read(clipboardControllerProvider);
  if (clip.isEmpty || clip.remote == null) return;

  Set<String> destNames;
  if (knownNames != null) {
    destNames = knownNames.toSet();
  } else {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      final res = await client.rpc(
        'operations/list',
        destRemote.listParams(destPath),
      );
      if (!context.mounted) return;
      destNames = {
        for (final it in (res['list'] as List? ?? const []))
          ((it as Map)['Name'] ?? '').toString(),
      };
    } catch (_) {
      destNames = const {}; // can't list → proceed as if no collisions
    }
  }

  final collisions = [
    for (final f in clip.files)
      if (destNames.contains(f.name)) f.name,
  ];

  var choice = ConflictChoice.overwrite; // no collisions ⇒ plain copy/move
  if (collisions.isNotEmpty) {
    choice = await showCopyConflictDialog(
      context,
      collisions: collisions,
      total: clip.files.length,
    );
    if (!context.mounted || choice == ConflictChoice.cancel) return;
  }

  final svc = ref.read(transferServiceProvider);
  final plan = planPaste(
    clip.files.map((f) => f.name).toList(),
    destNames,
    choice,
  );
  for (final step in plan) {
    await svc.transfer(
      srcRemote: clip.remote!,
      srcPath: joinPath(clip.parentPath, step.src),
      dstRemote: destRemote,
      dstPath: joinPath(destPath, step.dst),
      type: clip.isCut ? JobType.move : JobType.copy,
    );
  }
  if (clip.isCut) ref.read(clipboardControllerProvider.notifier).clear();
  await ref.read(paneProvider(refreshPaneIndex).notifier).refresh();
}
