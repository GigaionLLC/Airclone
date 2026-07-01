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

/// True while a [transferNamesIntoFolder] call (including its collision prompt)
/// is in flight, so a second paste/drop can't dispatch the same move twice or
/// stack a second conflict dialog.
final _transferInFlightProvider = StateProvider<bool>((_) => false);

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
/// subfolder the user right-clicked "Paste" onto). See [transferNamesIntoFolder];
/// clears the clipboard after a successful cut.
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
  final ran = await transferNamesIntoFolder(
    context,
    ref,
    srcRemote: clip.remote!,
    srcParentPath: clip.parentPath,
    names: clip.files.map((f) => f.name).toList(),
    destRemote: destRemote,
    destPath: destPath,
    type: clip.isCut ? JobType.move : JobType.copy,
    refreshPaneIndex: refreshPaneIndex,
    knownNames: knownNames,
  );
  if (ran && clip.isCut) ref.read(clipboardControllerProvider.notifier).clear();
}

/// The shared conflict-aware transfer core behind both paste and drag-drop:
/// moves [names] (leaf names sharing [srcParentPath] on [srcRemote]) into
/// [destPath] on [destRemote] as [type]. When any name already exists at the
/// destination the user is prompted (Skip / Replace / Keep both); [knownNames]
/// lets the caller supply the destination listing to skip the read-only
/// `operations/list` collision probe. Refreshes pane [refreshPaneIndex] (if
/// given) and returns true when the transfer actually ran (false if it was
/// empty, cancelled, or the widget went away mid-probe).
Future<bool> transferNamesIntoFolder(
  BuildContext context,
  WidgetRef ref, {
  required Remote srcRemote,
  required String srcParentPath,
  required List<String> names,
  required Remote destRemote,
  required String destPath,
  required JobType type,
  int? refreshPaneIndex,
  Iterable<String>? knownNames,
}) async {
  if (names.isEmpty) return false;
  // Re-entrancy latch: block a second paste/drop (and a stacked conflict
  // dialog) while one is resolving.
  if (ref.read(_transferInFlightProvider)) return false;
  ref.read(_transferInFlightProvider.notifier).state = true;
  try {
    Set<String> destNames;
    if (knownNames != null) {
      destNames = knownNames.toSet();
    } else {
      final client = ref.read(engineControllerProvider).client;
      if (client == null) return false;
      try {
        final res = await client.rpc(
          'operations/list',
          destRemote.listParams(destPath),
        );
        if (!context.mounted) return false;
        destNames = {
          for (final it in (res['list'] as List? ?? const []))
            ((it as Map)['Name'] ?? '').toString(),
        };
      } catch (_) {
        destNames = const {}; // can't list → proceed as if no collisions
      }
    }

    final collisions = [
      for (final n in names)
        if (destNames.contains(n)) n,
    ];

    var choice = ConflictChoice.overwrite; // no collisions ⇒ plain copy/move
    if (collisions.isNotEmpty) {
      if (!context.mounted) return false;
      choice = await showCopyConflictDialog(
        context,
        collisions: collisions,
        total: names.length,
      );
      if (!context.mounted || choice == ConflictChoice.cancel) return false;
    }

    final svc = ref.read(transferServiceProvider);
    final plan = planPaste(names, destNames, choice);
    for (final step in plan) {
      await svc.transfer(
        srcRemote: srcRemote,
        srcPath: joinPath(srcParentPath, step.src),
        dstRemote: destRemote,
        dstPath: joinPath(destPath, step.dst),
        type: type,
      );
    }
    if (refreshPaneIndex != null) {
      await ref.read(paneProvider(refreshPaneIndex).notifier).refresh();
    }
    // Only "true" (→ caller clears a cut clipboard) when something moved; a
    // skip-everything choice dispatches nothing and must keep the selection.
    return plan.isNotEmpty;
  } finally {
    ref.read(_transferInFlightProvider.notifier).state = false;
  }
}
