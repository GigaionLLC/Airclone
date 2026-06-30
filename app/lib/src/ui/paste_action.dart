import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../state/browser_controller.dart';
import '../state/clipboard_controller.dart';
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
  final clip = ref.read(clipboardControllerProvider);
  if (clip.isEmpty || clip.remote == null) return;

  final destNames = dest.entries.map((e) => e.name).toSet();
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
      dstRemote: remote,
      dstPath: joinPath(dest.path, step.dst),
      type: clip.isCut ? JobType.move : JobType.copy,
    );
  }
  if (clip.isCut) ref.read(clipboardControllerProvider.notifier).clear();
  await ref.read(paneProvider(paneIndex).notifier).refresh();
}
