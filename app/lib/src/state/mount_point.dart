/// Where a mount goes, on each platform.
///
/// THE BUG THIS FIXES. Mounting has never worked on Linux or macOS through the
/// app. The mount dialog offered only "Auto (next free letter)" and the drive
/// letters D: to Z:, on every platform, and sent that as rclone's mountPoint.
/// rclone understands "*" and drive letters on WINDOWS ONLY; everywhere else a
/// mount point is a folder. Run against the pinned rclone on Linux, through the
/// same RC call the app makes (see the mount-probe job in linux-runner.yml):
///
///     mountPoint "*"    failed to mount FUSE fs: cannot open: *: no such file or directory
///     mountPoint "D:"   failed to mount FUSE fs: cannot open: D:: no such file or directory
///     an empty folder   mounted, in the kernel mount table, readable and writable
///
/// So every choice the dialog offered failed on Linux, while rclone itself was
/// fine. macOS takes the same folder path: rclone's non-Windows getMountpoint
/// stats the path, requires a directory, and requires it to be empty.
///
/// The folder rules, from that same rclone code:
///   - it must EXIST - rclone stats it and does not create it;
///   - it must be a DIRECTORY;
///   - it must be EMPTY, unless allow-non-empty is set, which the app does not.
/// Windows is the opposite and is unchanged: a drive letter, or "*".
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether the mount dialog offers drive letters rather than a folder.
///
/// Windows mounts onto drive letters. So does the Web UI, for a different
/// reason: the dialog runs in a BROWSER there, which cannot know the host's
/// operating system and cannot create or inspect a folder on the host
/// (prepareMountFolder uses dart:io, which throws in a browser). The Web UI
/// therefore keeps the behaviour it had before folder mounts existed - correct
/// for a Windows host, and no worse than it was for any other. Folder mounts
/// from the Web UI need the host to prepare the folder, which is separate work.
bool mountsOntoDriveLetters({required bool windows, bool web = false}) =>
    windows || web;

/// A folder-safe name for [fs]: `gdrive:` -> `gdrive`, `gdrive:work/2026` ->
/// `gdrive-work-2026`.
///
/// A remote name can hold characters that are awkward or illegal in a path on
/// one platform or another, and the separators would nest the folder rather than
/// name it. Anything outside a conservative set becomes a dash, runs of dashes
/// collapse, and an empty result falls back to `remote` so there is always a
/// name.
String mountFolderName(String fs) {
  final raw = fs.replaceAll(':', '-');
  final cleaned = raw
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return cleaned.isEmpty ? 'remote' : cleaned;
}

/// Where a mount of [fs] goes by default: `<home>/Airclone/<name>`.
///
/// Under the home directory for two reasons. It is somewhere the user owns and
/// can find, unlike /mnt or /media which usually need root. And inside a
/// Flatpak it is shared with the host (the manifest grants the home), so a mount
/// made there is the same path to every other program - a sandbox-private
/// location like /tmp is not.
String defaultMountFolder({required String home, required String fs}) {
  final base = home.endsWith('/') ? home.substring(0, home.length - 1) : home;
  return '$base/Airclone/${mountFolderName(fs)}';
}

/// Top-level directories a folder mount must not go into.
///
/// Inside a Flatpak these are either private to the sandbox (/tmp, /var/tmp,
/// /run, /app) or never shared from the host (/usr, /proc, /sys, /dev). A mount
/// made at such a path from inside the sandbox lands somewhere other programs
/// cannot see - or, through the host mount helper, at a host path that is not
/// the one the user picked. Refused everywhere rather than only in a Flatpak:
/// mounting over a system directory is not something a desktop app should help
/// with on any Linux.
const List<String> kForbiddenMountRoots = [
  '/tmp',
  '/var/tmp',
  '/run',
  '/app',
  '/usr',
  '/proc',
  '/sys',
  '/dev',
  '/bin',
  '/sbin',
  '/lib',
  '/etc',
  '/boot',
];

/// Why [path] cannot be a mount folder, or null when it can.
///
/// Checks only what can be judged from the string. Existence, directory-ness and
/// emptiness are [prepareMountFolder]'s job, because they need the filesystem.
String? mountFolderProblem(String path) {
  final p = path.trim();
  if (p.isEmpty) return 'Choose a folder to mount into.';
  if (!p.startsWith('/')) {
    return 'Use a full path, starting with /.';
  }
  final segments = p.split('/');
  if (segments.contains('..')) {
    return 'The folder path cannot contain "..".';
  }
  if (p == '/') return 'You cannot mount over the root of the disk.';
  for (final root in kForbiddenMountRoots) {
    if (p == root || p.startsWith('$root/')) {
      return 'Mount into a folder in your home directory, not under $root.';
    }
  }
  return null;
}

/// Makes [path] ready for rclone: creates it when missing, and refuses anything
/// that is not an empty directory. Returns the problem, or null when ready.
///
/// Created here because rclone will not create it. Checked for emptiness here
/// because rclone's own refusal is a raw "directory not empty" inside a
/// "failed to mount FUSE fs" wrapper, which says nothing about what to do.
Future<String?> prepareMountFolder(String path) async {
  final problem = mountFolderProblem(path);
  if (problem != null) return problem;
  return prepareMountFolderOnDisk(path.trim());
}

/// The filesystem half of [prepareMountFolder], WITHOUT the path rules.
///
/// Split out so it can be tested at all. Every temporary directory a test can
/// create is one the rules refuse - a `C:/...` path on Windows, under /tmp on
/// Linux and macOS - so tests that went through [prepareMountFolder] returned
/// early on every platform and passed without exercising anything. Production
/// code must call [prepareMountFolder].
@visibleForTesting
Future<String?> prepareMountFolderOnDisk(String p) async {
  try {
    final type = await FileSystemEntity.type(p, followLinks: true);
    if (type == FileSystemEntityType.notFound) {
      await Directory(p).create(recursive: true);
      return null;
    }
    if (type != FileSystemEntityType.directory) {
      return 'Something that is not a folder already exists at $p.';
    }
    if (!await Directory(p).list().isEmpty) {
      return 'That folder is not empty. Mount into an empty folder, so '
          'nothing already in it is hidden while the mount is active.';
    }
    return null;
  } on FileSystemException catch (e) {
    return 'Could not use $p: ${e.osError?.message ?? e.message}.';
  }
}

/// rclone's mount errors, in words that say what to do.
///
/// Falls back to the raw text for anything unrecognised, rather than guessing:
/// a wrong explanation is worse than rclone's own.
String friendlyMountError(String raw, {required bool windows}) {
  final r = raw.toLowerCase();
  if (!windows &&
      r.contains('fusermount') &&
      (r.contains('not found') || r.contains('no such file'))) {
    return 'FUSE is not installed on this computer. Install it (for example '
        '`sudo apt install fuse3`), then try again.';
  }
  if (r.contains('not empty') || r.contains('directory not empty')) {
    return 'That folder is not empty. Mount into an empty folder.';
  }
  if (r.contains('permission denied') && r.contains('/dev/fuse')) {
    return 'This account is not allowed to use FUSE. On most systems adding '
        'yourself to the fuse group and signing in again fixes it.';
  }
  return raw;
}
