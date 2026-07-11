import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Automatic, always-on config backups — the trust substrate under every mutating
/// operation the config-portability plan introduces (dev/plans/config-portability-plan.md
/// §2). Before an import-merge, replace, or path switch, the caller snapshots the
/// active config here; a bounded ring of the most recent copies is kept so a bad
/// import is one "Restore a backup…" away. Quiet by design: no setting, no UI
/// state — just a folder of timestamped copies.
///
/// Everything is injectable so the ring/prune/restore logic is unit-testable
/// without touching the real app-support directory or the wall clock:
///  - [dir]    the backups folder (production: `<appSupport>/config-backups`);
///  - [clock]  the time source stamped into filenames;
///  - [keep]   how many newest backups to retain (default 10).
class ConfigBackups {
  ConfigBackups(this.dir, {DateTime Function()? clock, this.keep = 10})
    : _clock = clock ?? DateTime.now;

  /// The folder holding `rclone-<stamp>.conf` copies.
  final Directory dir;

  /// Newest-N retained; older backups are pruned after each new write.
  final int keep;

  final DateTime Function() _clock;

  /// Resolves the production [ConfigBackups] over `<appSupport>/config-backups`.
  /// Async because the support directory is a platform-channel lookup; the
  /// provider below wraps this. Tests build [ConfigBackups] directly with a temp
  /// [dir] and a fake [clock].
  static Future<ConfigBackups> open({DateTime Function()? clock}) async {
    final support = await getApplicationSupportDirectory();
    return ConfigBackups(
      Directory('${support.path}/config-backups'),
      clock: clock,
    );
  }

  /// Copies the active config [src] into [dir] as `rclone-<UTC yyyyMMdd-HHmmss>.conf`,
  /// prunes the folder to the [keep] newest, and returns the new backup's path.
  /// Returns `null` when [src] does not exist — a fresh install has no active
  /// config to snapshot, and a mutating op on nothing is a no-op, not an error.
  ///
  /// If two backups land in the same UTC second the filename would collide, so a
  /// zero-padded `-02`, `-03`, … disambiguator is appended (the first stays the
  /// bare `rclone-<stamp>.conf`); zero-padding keeps the suffixed siblings in
  /// write order lexically, and [_sortKey] makes the bare first-of-second sort as
  /// the OLDEST within its second (see its note).
  Future<String?> backupActiveConfig(File src) async {
    if (!await src.exists()) return null;
    await dir.create(recursive: true);
    // A backup can be a PLAINTEXT config (import/replace/path-switch snapshots),
    // so tighten the ring to owner-only on POSIX — mirrors the config temp dir.
    await _hardenPosix(dir.path, '700');
    final stamp = _stamp(_clock());
    var dest = File('${dir.path}/rclone-$stamp.conf');
    var n = 2;
    while (await dest.exists()) {
      dest = File('${dir.path}/rclone-$stamp-${_two(n++)}.conf');
    }
    await src.copy(dest.path);
    await _hardenPosix(dest.path, '600');
    await _prune();
    return dest.path;
  }

  /// Best-effort owner-only tightening on POSIX (chmod). No-op on Windows — the
  /// backups live under the per-user app-support dir, which NTFS ACLs already
  /// scope to the user — and on any chmod failure (the file is still written).
  static Future<void> _hardenPosix(String path, String mode) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', [mode, path]);
    } catch (_) {
      // best-effort hardening — a failed chmod must not fail the backup
    }
  }

  /// The current backups, newest first. Sorted by a derived key (fixed-width UTC
  /// stamp + a same-second counter, see [_sortKey]) descending — chronological,
  /// independent of filesystem mtimes (which a fake-clock test can't set) and
  /// correct even for the same-second case. Non-backup files are ignored.
  Future<List<File>> listBackups() => _list();

  /// Restores [backupPath] over the active config [dst], first snapshotting the
  /// CURRENT [dst] so the restore is itself reversible (returns that safety
  /// snapshot's path, or null if [dst] didn't exist yet).
  ///
  /// The chosen backup's bytes are read into memory BEFORE the snapshot: the
  /// snapshot's prune could otherwise delete [backupPath] itself if it is the
  /// oldest and the folder is already at capacity — reading first makes the
  /// restore immune to that race.
  Future<String?> restoreBackup(String backupPath, File dst) async {
    final data = await File(backupPath).readAsBytes();
    final snapshot = await backupActiveConfig(dst);
    await dst.writeAsBytes(data, flush: true);
    return snapshot;
  }

  Future<List<File>> _list() async {
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && _isBackupName(_basename(e.path))) files.add(e);
    }
    files.sort(
      (a, b) =>
          _sortKey(_basename(b.path)).compareTo(_sortKey(_basename(a.path))),
    );
    return files;
  }

  /// Deletes everything past the [keep] newest. Best-effort per file so one
  /// locked/racing delete doesn't abort the rest.
  Future<void> _prune() async {
    final all = await _list();
    if (all.length <= keep) return;
    for (final f in all.skip(keep)) {
      try {
        await f.delete();
      } catch (_) {
        // best-effort — a file already gone or momentarily locked is fine
      }
    }
  }

  static bool _isBackupName(String base) =>
      base.startsWith('rclone-') && base.endsWith('.conf');

  /// The ordering key for a backup basename: the fixed-width UTC stamp plus a
  /// zero-padded same-second counter. A bare `rclone-<stamp>.conf` was written
  /// FIRST in its second, so it counts as 0 (oldest); `-02`, `-03`, … follow.
  /// This makes descending order true newest-first even within one second — a
  /// plain lexical basename sort would instead rank the bare name (whose '.' >
  /// '-') as the NEWEST, inverting the actual write order. A foreign name (never
  /// reached — [_isBackupName] filters first) falls back to itself.
  static String _sortKey(String base) {
    final m = RegExp(
      r'^rclone-(\d{8}-\d{6})(?:-(\d+))?\.conf$',
    ).firstMatch(base);
    if (m == null) return base;
    final counter = int.tryParse(m.group(2) ?? '0') ?? 0;
    return '${m.group(1)}-${counter.toString().padLeft(4, '0')}';
  }

  static String _basename(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// `yyyyMMdd-HHmmss` in UTC — sortable, timezone-stable, filesystem-safe.
  static String _stamp(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}'
        '-${_two(u.hour)}${_two(u.minute)}${_two(u.second)}';
  }
}

/// The app's [ConfigBackups] over the real support directory. A [FutureProvider]
/// because [ConfigBackups.open] awaits the platform support-dir lookup; tests
/// override this (or construct [ConfigBackups] directly with a temp dir).
final configBackupsProvider = FutureProvider<ConfigBackups>(
  (ref) => ConfigBackups.open(),
);
