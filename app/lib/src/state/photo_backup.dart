import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'archive_command.dart' show escapeRcloneGlob;
import 'local_locations.dart' show fsRoot;
import 'task_kind.dart';
import 'task_schedule.dart';
import 'tasks_controller.dart';
import 'transfer_options.dart';

/// Camera-roll backup as a [TaskKind.photos] task — a shape over the existing
/// task model, not a model of its own.
///
/// The decisions this encodes (plan §4.d / §4.f, 2026-09-09):
///
///  * **The source is a SET of folders**, camera roll (`DCIM`) by default, all
///    under the phone's shared-storage root. One rclone job cannot take several
///    sources, so the task's `srcFs` is the storage root and the folders become
///    ordered rclone filter rules — which also **mirrors the source structure**
///    at the destination (`…/Photos/<device>/DCIM/Camera/IMG.jpg`), the only
///    honest layout once a user can add a folder with no capture-date meaning.
///  * **Videos are included, with their own toggle.** They live in DCIM and a
///    camera-roll backup without them would surprise people; they also dominate
///    the byte count and the first run's duration.
///  * **Copy only, never move or sync** — guaranteed by [backupOptions] at
///    definition and again at run time. A camera-roll backup that deletes is a
///    data-loss incident, not a feature.
///  * **Destination `remote:Airclone/Photos/<device>/`**, with [deviceFolderName]
///    keeping two phones on one remote out of each other's folders.
///
/// The filter rules are `--filter` rules (`+`/`-` prefixed), in one ordered
/// list, and NOT a mix of `--include` and `--exclude`. rclone evaluates every
/// `--include` before any `--exclude`, first match wins, so an included
/// `/DCIM/**` would swallow a `.mp4` before an exclude could see it. A single
/// ordered list is the only form where "videos out, then these folders in,
/// then nothing else" means what it says. The trailing `- **` is load-bearing:
/// rclone adds an implicit one for `--include` rules but never for `--filter`.
const String kPhotoBackupFolder = 'Airclone/Photos';

/// The camera roll, relative to the storage root.
const String kCameraRollFolder = 'DCIM';

const String kPhotoBackupTaskName = 'Photo backup';

/// Extensions treated as video for the toggle. Lower-case here; rules are
/// emitted in both cases because rclone's filters are case-sensitive and
/// cameras disagree about which case to write.
const List<String> kVideoExtensions = [
  'mp4',
  'm4v',
  'mov',
  '3gp',
  '3g2',
  'mkv',
  'webm',
  'avi',
  'mts',
  'm2ts',
  'ts',
  'mpg',
  'mpeg',
  'wmv',
];

/// Every-N-hours choices offered by the setup sheet, in minutes.
const List<int> kPhotoBackupIntervalChoices = [60, 180, 360, 720, 1440];

/// The default schedule: every six hours, matching [TaskSchedule]'s own
/// default so the raw editor shows nothing surprising.
const TaskSchedule kPhotoBackupDefaultSchedule = TaskSchedule(
  kind: ScheduleKind.interval,
  intervalMinutes: 360,
);

/// `- *.mp4`, `- *.MP4`, … — the rules that keep videos out.
List<String> videoExcludeRules() => [
  for (final e in kVideoExtensions) ...['- *.$e', '- *.${e.toUpperCase()}'],
];

/// `+ /DCIM/**` — everything under one source folder, anchored at the root.
String photoFolderRule(String relativeFolder) =>
    '+ /${escapeRcloneGlob(relativeFolder)}/**';

final _folderRule = RegExp(r'^\+ /(.+)/\*\*$');

/// The inverse of [photoFolderRule], or null for any other rule.
String? photoFolderOfRule(String rule) {
  final m = _folderRule.firstMatch(rule);
  if (m == null) return null;
  return m[1]!.replaceAllMapped(RegExp(r'\\(.)'), (x) => x[1]!);
}

/// The ordered `--filter` list for [folders] (relative to the storage root).
List<String> buildPhotoFilterRules({
  required List<String> folders,
  required bool includeVideos,
}) => [
  if (!includeVideos) ...videoExcludeRules(),
  for (final f in folders) photoFolderRule(f),
  '- **',
];

/// [absolutePath] relative to [storageRoot], or null when it is not strictly
/// inside it (the root itself, a different volume, or a path that climbs).
///
/// Null is a refusal, not a fallback: a folder on an SD card has no place in a
/// job rooted at internal storage, and silently backing up the wrong thing is
/// worse than saying so.
String? relativePhotoFolder(String absolutePath, String storageRoot) {
  String norm(String p) =>
      p.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final path = norm(absolutePath);
  final root = norm(storageRoot);
  if (root.isEmpty || path == root || !path.startsWith('$root/')) return null;
  final rel = path.substring(root.length + 1);
  final parts = rel.split('/');
  if (parts.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
  return rel;
}

/// `remote:<path>/Airclone/Photos/<device>` — [remoteFs] is the rclone fs
/// prefix (`gdrive:`), [path] a folder inside it (may be empty).
String photoBackupDestination({
  required String remoteFs,
  required String path,
  required String deviceName,
}) {
  final segments = <String>[
    ...path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty),
    ...kPhotoBackupFolder.split('/'),
    deviceFolderName(deviceName),
  ];
  return '$remoteFs${segments.join('/')}';
}

/// What the user chose: which folders, and whether videos ride along.
@immutable
class PhotoBackupSpec {
  const PhotoBackupSpec({required this.folders, required this.includeVideos});

  /// Relative to the storage root, in the order they were added.
  final List<String> folders;
  final bool includeVideos;

  static const defaults = PhotoBackupSpec(
    folders: [kCameraRollFolder],
    includeVideos: true,
  );

  PhotoBackupSpec copyWith({List<String>? folders, bool? includeVideos}) =>
      PhotoBackupSpec(
        folders: folders ?? this.folders,
        includeVideos: includeVideos ?? this.includeVideos,
      );

  @override
  bool operator ==(Object other) =>
      other is PhotoBackupSpec &&
      listEquals(other.folders, folders) &&
      other.includeVideos == includeVideos;

  @override
  int get hashCode => Object.hash(Object.hashAll(folders), includeVideos);
}

/// Reads the spec back out of a [TaskKind.photos] task's filter rules, or null
/// for any other task. A hand-edited rule list that no longer carries a folder
/// rule reads as "no folders", which the sheet shows rather than guesses at.
PhotoBackupSpec? photoBackupSpecOf(TransferTask t) {
  if (t.kind != TaskKind.photos) return null;
  final folders = <String>[
    for (final r in t.options.filters) ?photoFolderOfRule(r),
  ];
  // The first video rule is enough to know the toggle was off.
  final excludesVideos = t.options.filters.contains(videoExcludeRules().first);
  return PhotoBackupSpec(folders: folders, includeVideos: !excludesVideos);
}

/// "Camera roll", "Camera roll + 2 folders", "3 folders".
String describePhotoSources(List<String> folders) {
  final camera = folders.contains(kCameraRollFolder);
  final extra = folders.where((f) => f != kCameraRollFolder).length;
  String n(int k) => '$k folder${k == 1 ? '' : 's'}';
  if (camera && extra == 0) return 'Camera roll';
  if (camera) return 'Camera roll + ${n(extra)}';
  return extra == 0 ? 'No folders' : n(extra);
}

/// The task itself. [dstFs] is the composed destination from
/// [photoBackupDestination]. [id] is kept when re-saving an existing photo
/// backup so its run history and `lastRun` carry over; a new one gets a fresh
/// id.
TransferTask buildPhotoBackupTask({
  String? id,
  required String storageRoot,
  required PhotoBackupSpec spec,
  required String dstFs,
  TaskSchedule schedule = kPhotoBackupDefaultSchedule,
  DateTime? lastRun,
  List<TaskRunRecord> history = const [],
}) {
  return TransferTask(
    id: id ?? TransferTask.newId(),
    name: kPhotoBackupTaskName,
    srcFs: fsRoot(storageRoot),
    srcLabel: describePhotoSources(spec.folders),
    dstFs: dstFs,
    dstLabel: dstFs,
    // backupOptions at definition; scheduler_controller and headless_runner
    // apply it again at run time, so the raw editor cannot undo it.
    options: backupOptions(
      TransferOptions(
        filters: buildPhotoFilterRules(
          folders: spec.folders,
          includeVideos: spec.includeVideos,
        ),
      ),
    ),
    schedule: schedule,
    lastRun: lastRun,
    history: history,
    // The point of a photo backup on a phone is that it runs by itself.
    runWhileClosed: true,
    kind: TaskKind.photos,
  );
}

/// The phone's own name, for the per-device folder. Asked natively
/// (`Settings.Global.DEVICE_NAME`, falling back to make + model); off Android
/// the host name stands in, and any failure yields a usable placeholder rather
/// than an exception in a setup flow.
Future<String> photoBackupDeviceName() async {
  if (!Platform.isAndroid) {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'device';
    }
  }
  try {
    const channel = MethodChannel('airclone/native');
    final name = await channel.invokeMethod<String>('deviceName');
    if (name != null && name.trim().isNotEmpty) return name;
  } catch (_) {
    // an old native build without the method
  }
  return 'Android';
}
