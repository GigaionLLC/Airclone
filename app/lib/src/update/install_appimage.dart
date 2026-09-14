/// Installing a verified update over a running AppImage.
///
/// An AppImage is one file, which makes this the simplest of the five install
/// flows and the only one that needs no helper process: replace the file and
/// start it again.
///
/// THREE THINGS THAT ARE EASY TO GET WRONG, and each of them breaks a user's
/// install rather than merely failing:
///
///   * **The path is `$APPIMAGE`, never `Platform.resolvedExecutable`.** Inside
///     an AppImage the executable resolves into `/tmp/.mount_XXXX/usr/bin/...`,
///     a FUSE mount that disappears when the process exits. Writing "the new
///     version" there would write into a temporary filesystem and change
///     nothing at all.
///   * **The name must not change.** Desktop integration (appimaged,
///     AppImageLauncher) writes an absolute `Exec=` into a .desktop file.
///     Appending a version - which some updaters do by default - leaves the
///     menu entry, the dock pin and every file association pointing at a file
///     that is now the OLD version.
///   * **Stage in the same directory, then rename.** A rename within a
///     directory is atomic; a copy is not, and a copy interrupted halfway
///     leaves an unrunnable AppImage where a working one used to be. `/tmp` is
///     no good for staging either: it is frequently mounted `noexec`, and it is
///     usually a different filesystem, so the rename would not be atomic.
///
/// The old image is kept as `<name>.old` until the new one has started. The
/// running process holds its own inode open through its FUSE mount, so
/// replacing the file underneath it is safe - it keeps running from what it
/// already mapped.
library;

import 'dart:io';

/// What happened, or what stopped it.
enum AppImageInstall {
  /// The new image is in place; the caller should relaunch and exit.
  replaced,

  /// This process is not running from an AppImage.
  notAnAppImage,

  /// The image is somewhere this user cannot write - a system directory, or a
  /// read-only mount. Nothing was changed.
  notWritable,

  /// The staged file could not be written, or the rename failed.
  failed,
}

/// The result, with the paths a caller needs afterwards.
class AppImageInstallResult {
  const AppImageInstallResult(
    this.outcome, {
    this.imagePath,
    this.backupPath,
    this.detail,
  });

  final AppImageInstall outcome;

  /// The image that was replaced - the path to relaunch.
  final String? imagePath;

  /// Where the previous version was kept.
  final String? backupPath;

  final String? detail;

  bool get ok => outcome == AppImageInstall.replaced;
}

/// The running AppImage's path, or null when this is not one.
///
/// The AppImage runtime exports `APPIMAGE` before `AppRun` starts. A launch via
/// `--appimage-extract-and-run`, or a scrubbed environment, leaves it unset -
/// and that is a genuine "cannot update", not a reason to guess at a path.
String? runningAppImagePath(Map<String, String> environment) {
  final path = environment['APPIMAGE'] ?? '';
  return path.isEmpty ? null : path;
}

/// Puts [verified] in place of the running AppImage.
///
/// [verified] must already have been checked against the signed manifest: this
/// function is the part that writes to the user's disk, and it takes what it is
/// given. Nothing here re-verifies, and nothing here should be reachable from a
/// path that has not.
Future<AppImageInstallResult> installAppImage({
  required File verified,
  required Map<String, String> environment,
}) async {
  final imagePath = runningAppImagePath(environment);
  if (imagePath == null) {
    return const AppImageInstallResult(AppImageInstall.notAnAppImage);
  }
  final image = File(imagePath);
  final dir = image.parent;

  // Ask by DOING: a probe file in the real directory answers what permission
  // bits cannot (a read-only mount, an immutable flag, a full disk). Reading
  // the mode and believing it is how an updater reports success and then
  // changes nothing.
  final probe = File(
    '${dir.path}${Platform.pathSeparator}.airclone-write-test',
  );
  try {
    probe.writeAsStringSync('');
    probe.deleteSync();
  } catch (e) {
    return AppImageInstallResult(
      AppImageInstall.notWritable,
      imagePath: imagePath,
      detail: '$e',
    );
  }

  final staged = File('$imagePath.new');
  final backup = File('$imagePath.old');
  try {
    if (staged.existsSync()) staged.deleteSync();
    await verified.copy(staged.path);
    // Match the mode of the image being replaced, so an install that was
    // executable stays executable and one that was group-readable stays that.
    if (!Platform.isWindows) {
      final mode = image.statSync().mode & 0x1FF; // permission bits
      await Process.run('chmod', [
        mode.toRadixString(8).padLeft(3, '0'),
        staged.path,
      ]);
    }

    if (backup.existsSync()) backup.deleteSync();
    // The old image is MOVED aside rather than deleted: if the rename below
    // fails, the user still has a working Airclone.
    image.renameSync(backup.path);
    try {
      staged.renameSync(imagePath);
    } catch (e) {
      // Put it back. A failed update must not cost someone the app.
      backup.renameSync(imagePath);
      return AppImageInstallResult(
        AppImageInstall.failed,
        imagePath: imagePath,
        detail: '$e',
      );
    }
    return AppImageInstallResult(
      AppImageInstall.replaced,
      imagePath: imagePath,
      backupPath: backup.path,
    );
  } catch (e) {
    try {
      if (staged.existsSync()) staged.deleteSync();
    } catch (_) {}
    return AppImageInstallResult(
      AppImageInstall.failed,
      imagePath: imagePath,
      detail: '$e',
    );
  }
}

/// Removes the `<name>.old` left by a successful install.
///
/// Called on the NEXT launch, not immediately after replacing: until the new
/// image has actually started, that file is the only way back.
void sweepAppImageBackup(Map<String, String> environment) {
  final imagePath = runningAppImagePath(environment);
  if (imagePath == null) return;
  final backup = File('$imagePath.old');
  try {
    if (backup.existsSync()) backup.deleteSync();
  } catch (_) {
    // A leftover file is untidy, not harmful.
  }
}
