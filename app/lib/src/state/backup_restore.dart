/// Restoring, and why there is so little code here.
///
/// A backup destination is an **ordinary remote folder**. So "restore from this
/// backup" does not need a restore engine, a manifest format, or a parallel
/// browser — it needs to open that folder in a pane. Copying out of it is then
/// the copy the app already does, through the conflict preflight every other
/// transfer got in v0.7.6.
///
/// That inheritance is the point rather than a shortcut. Restoring *over* live
/// files is a write, and it must ask before overwriting — a bespoke restore path
/// would have had to grow its own version of that guard, and would have grown it
/// later and worse.
library;

import '../rclone/models/remote.dart';
import 'task_kind.dart';
import 'tasks_controller.dart';

/// Splits `remote:path` into its two halves.
///
/// A task stores its destination as a single `fs` string like
/// `gdrive:Airclone/Backups/laptop/Docs`. Restoring needs the remote and the
/// path separately, to open one at the other.
///
/// Only the FIRST colon separates them: a path may legitimately contain colons
/// on backends that allow it, and splitting on the last one would address the
/// wrong folder.
({String remoteName, String path})? splitFs(String fs) {
  final i = fs.indexOf(':');
  if (i <= 0) return null;
  return (
    remoteName: fs.substring(0, i),
    path: fs.substring(i + 1).replaceAll(RegExp(r'^/+|/+$'), ''),
  );
}

/// The remote a backup task writes to, or null when it no longer exists.
///
/// A remote can be deleted while a task still names it, and the honest answer
/// then is "that backup's remote is gone" rather than a crash or an empty
/// browser pane with no explanation.
Remote? restoreRemoteFor(TransferTask task, List<Remote> remotes) {
  final split = splitFs(task.dstFs);
  if (split == null) return null;
  for (final r in remotes) {
    if (r.name == split.remoteName) return r;
  }
  return null;
}

/// Whether [task] is something a restore makes sense from.
///
/// A plain transfer's destination is not a backup — it has no version history
/// and nothing about it promises the source is still recoverable — so offering
/// "restore" there would be claiming something untrue.
bool canRestoreFrom(TransferTask task) =>
    task.kind == TaskKind.backup || task.kind == TaskKind.photos;
