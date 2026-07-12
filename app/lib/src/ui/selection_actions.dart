import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/clipboard_controller.dart';
import '../state/download_settings.dart';
import '../state/file_ops.dart';
import '../state/transfer_service.dart';
import 'file_op_dialogs.dart';
import 'pane_drag.dart';

/// Bulk operations over pane [index]'s current multi-selection, factored out so
/// the phone selection bar runs the SAME logic the desktop toolbar does. Each
/// reads the live selection from `paneProvider(index)` and no-ops when nothing is
/// selected. None clears the selection — the caller decides (the phone bar clears
/// after every action so it dismisses).

/// Copy (or [cut]) the selection to the clipboard; paste happens elsewhere.
void selectionClip(WidgetRef ref, int index, {required bool cut}) {
  final state = ref.read(paneProvider(index));
  final remote = state.remote;
  final files = state.selectedEntries;
  if (remote == null || files.isEmpty) return;
  final clip = ref.read(clipboardControllerProvider.notifier);
  cut
      ? clip.cut(remote, state.path, files)
      : clip.copy(remote, state.path, files);
}

/// Confirm, then delete every selected entry and refresh. Returns `ran` = false
/// when there was nothing to delete or the user cancelled; otherwise `ran` = true
/// with `failed` = how many entries could NOT be deleted (a per-item failure
/// never aborts the rest, and the folder ALWAYS refreshes so the pane can't show
/// items that are actually gone).
Future<({bool ran, int failed})> selectionDelete(
  BuildContext context,
  WidgetRef ref,
  int index,
) async {
  // Capture the notifier up front: it outlives the widget, so the trailing
  // refresh is safe even if the caller unmounts (e.g. a bottom-nav tab switch)
  // during the multi-item delete.
  final ctrl = ref.read(paneProvider(index).notifier);
  final state = ref.read(paneProvider(index));
  final remote = state.remote;
  final files = state.selectedEntries;
  if (remote == null || files.isEmpty) return (ran: false, failed: 0);
  final ok = await showDeleteConfirm(
    context,
    files.length == 1 ? files.first.name : '${files.length} items',
    // Warn about the recursive folder purge whenever the batch includes a folder.
    isDir: files.any((f) => f.isDir),
  );
  if (!ok) return (ran: false, failed: 0);
  final ops = ref.read(fileOpsProvider);
  var failed = 0;
  for (final f in files) {
    try {
      await ops.deleteEntry(remote, f, state.path);
    } catch (_) {
      failed++; // keep going; the caller surfaces the count
    }
  }
  await ctrl.refresh();
  return (ran: true, failed: failed);
}

/// Download the selection to the user's download folder (prompts / uses the saved
/// default). Returns true once the transfers are queued (false if cancelled or
/// nothing was selected).
Future<bool> selectionDownload(WidgetRef ref, int index) async {
  final state = ref.read(paneProvider(index));
  final remote = state.remote;
  final files = state.selectedEntries;
  if (remote == null || files.isEmpty) return false;
  final dir = await resolveDownloadDir(ref); // prompts / uses saved default
  if (dir == null) return false; // cancelled
  final local = Remote(
    name: 'Download',
    type: 'local',
    fs: '$dir/',
    isLocal: true,
  );
  final svc = ref.read(transferServiceProvider);
  for (final f in files) {
    await svc.transfer(
      srcRemote: remote,
      srcPath: joinPath(state.path, f.name),
      dstRemote: local,
      dstPath: f.name,
      type: JobType.copy,
    );
  }
  return true;
}
