import 'task_kind.dart';
import 'task_schedule.dart';
import 'tasks_controller.dart';
import 'transfer_options.dart';

/// The folder every backup lands under, inside whatever remote the user picked.
///
/// A fixed, recognisable root so a restore knows where to look and a user
/// browsing their remote can tell what put those files there. `Photos` sits
/// beside `Backups` for the camera-roll case, per the plan's
/// `remote:Airclone/Photos/<device>/`.
const String kBackupRoot = 'Airclone/Backups';
const String kPhotoRoot = 'Airclone/Photos';

/// The last path segment of [path], or the remote's own name at its root.
///
/// A backup of `D:\Projects\Airclone` should land in a folder called
/// `Airclone`, not one called `D--Projects-Airclone` and not one called after
/// the whole path.
String backupFolderLeaf({required String remoteName, required String path}) {
  final trimmed = path.replaceAll(RegExp(r'[/\\]+$'), '');
  if (trimmed.isEmpty) return deviceFolderName(remoteName);
  final parts = trimmed.split(RegExp(r'[/\\]'));
  for (var i = parts.length - 1; i >= 0; i--) {
    final leaf = deviceFolderName(parts[i]);
    if (leaf != 'device' || parts[i].isNotEmpty) return leaf;
  }
  return deviceFolderName(remoteName);
}

/// Where a backup of [sourcePath] from this device writes to, under [destPath].
///
/// `<dest>/Airclone/Backups/<device>/<source leaf>` — the device segment so two
/// machines backing up to one remote cannot merge into each other, and the leaf
/// so several folders from one machine stay apart.
///
/// Joined carefully: [destPath] is empty at a remote's root, and a leading or
/// doubled slash makes rclone address a different path than the user chose.
String backupDestinationPath({
  required String destPath,
  required String deviceName,
  required String sourceRemoteName,
  required String sourcePath,
  bool photos = false,
}) {
  final leaf = backupFolderLeaf(remoteName: sourceRemoteName, path: sourcePath);
  final segments = [
    if (destPath.isNotEmpty) destPath.replaceAll(RegExp(r'^/+|/+$'), ''),
    photos ? kPhotoRoot : kBackupRoot,
    deviceFolderName(deviceName),
    // A photo backup is per-device, not per-folder: several source folders all
    // mirror into the one Photos tree, which is what "mirror the source
    // structure" means when the source is a set.
    if (!photos) leaf,
  ];
  return segments.where((s) => s.isNotEmpty).join('/');
}

/// Builds the task the backup wizard's three answers describe.
///
/// Pure, so what the wizard produces can be asserted without driving a dialog —
/// and so the constraints that make this a backup are visible in one place
/// rather than spread across a widget's callbacks.
///
/// The options come from [backupOptions], which is also enforced at run time:
/// nothing here can produce a task that later runs as a sync.
TransferTask buildBackupTask({
  required String id,
  required String name,
  required String srcFs,
  required String srcLabel,
  required String dstFs,
  required String dstLabel,
  required TaskSchedule? schedule,
  bool photos = false,
  bool runWhileClosed = false,
  TransferOptions base = const TransferOptions(),
}) => TransferTask(
  id: id,
  name: name,
  srcFs: srcFs,
  srcLabel: srcLabel,
  dstFs: dstFs,
  dstLabel: dstLabel,
  options: backupOptions(base),
  schedule: schedule,
  runWhileClosed: runWhileClosed,
  kind: photos ? TaskKind.photos : TaskKind.backup,
  // A backup that has never run should read as "not yet", not as "ran at the
  // moment you created it" — leaving lastRun null also makes the first
  // scheduled slot fire rather than waiting a full interval.
  lastRun: null,
);
