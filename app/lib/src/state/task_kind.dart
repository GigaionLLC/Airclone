import 'transfer_options.dart';

/// What a saved task *is*, as opposed to what it does.
///
/// A discriminator rather than three parallel objects: a backup is a transfer
/// task with its dangerous options taken away and different words on top. That
/// keeps one scheduler, one run history, one set of safety guards, and one place
/// where a bug can live.
///
/// [transfer] is the default and is omitted from persisted JSON, so every task
/// saved before this existed round-trips byte-identical.
enum TaskKind {
  /// The raw thing: any mode, all options, advanced-gated.
  transfer,

  /// A folder copied somewhere safe, on a schedule. Copy only, versions kept.
  backup,

  /// A backup whose source is the camera roll (plus any folders the user added).
  photos,
}

/// The recoverable-overwrite suffix rclone renames replaced files with.
///
/// Named here rather than left as a literal in three places because retention
/// has to recognise it: a prune pass must delete *versions* and never a current
/// file, and the only thing distinguishing them is this suffix.
const String kReplacedSuffix = '.replaced';

/// The options that make a task a backup rather than a transfer.
///
/// Applied at definition AND enforced at run time, for the same reason the
/// delete cap is: a task saved before these constraints existed, or edited
/// through the raw advanced dialog, must not be able to run as something else
/// under a backup's name.
///
/// Three constraints, each closing a specific way a backup stops being one:
///
///  * **`copy`, never `sync` or `move`.** A sync deletes at the destination to
///    match the source, so a backup that syncs deletes your history the moment
///    the source loses a file — which is exactly when you need it. A move
///    deletes the original, so a "backup" that moves is not a backup at all.
///  * **`keepReplaced`.** An overwritten file is renamed aside rather than lost,
///    which is what makes a version history exist to restore *from*.
///  * **No dry run.** A backup that quietly reports instead of copying is the
///    worst possible failure: it looks like it worked every night.
TransferOptions backupOptions(TransferOptions o) =>
    o.copyWith(mode: TransferMode.copy, keepReplaced: true, dryRun: false);

/// Whether [o] already satisfies [backupOptions].
///
/// Used to detect a task that says it is a backup but carries options that make
/// it something else — the shape a hand-edited config or an older build can
/// produce.
bool isBackupShaped(TransferOptions o) =>
    o.mode == TransferMode.copy && o.keepReplaced && !o.dryRun;

/// The per-device destination subfolder for a backup.
///
/// Two devices backing up to one remote would otherwise merge into each other's
/// folders, and the first sign of it would be a restore putting a laptop's files
/// on a phone. Sanitised because the value ends up in a remote path: a device
/// name is user-controlled and can hold slashes, colons and worse.
///
/// Falls back to `device` when the name carries no letters or digits at all.
/// An empty segment would back up into the PARENT folder, merging this device
/// with every other one — and a name like `///`, which sanitises to `---`, is
/// technically a usable folder but identifies nothing, so it gets the same
/// treatment rather than a meaningless one.
String deviceFolderName(String rawDeviceName) {
  final cleaned = rawDeviceName
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
      // Leading/trailing dots and spaces are invalid on Windows and invisible
      // everywhere else, which is a bad combination in a path.
      .replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  return RegExp(r'[A-Za-z0-9]').hasMatch(cleaned) ? cleaned : 'device';
}
