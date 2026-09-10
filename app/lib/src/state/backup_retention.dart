import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/rclone_file.dart';
import 'task_kind.dart';

/// How long a replaced version is kept before a prune may remove it.
///
/// Thirty days by the user's decision (2026-09-09), configurable. Zero means
/// "keep nothing beyond the current file", which is a legitimate choice for
/// someone short on space; there is deliberately no "forever" option, because a
/// version history that only grows is a bill nobody agreed to.
const int kDefaultRetentionDays = 30;

/// The retention choices offered, in days.
const List<int> kRetentionDayChoices = [0, 7, 14, 30, 60, 90, 365];

/// Clamps an arbitrary stored value onto something sane, honouring an
/// off-menu-but-reasonable number rather than snapping it to the nearest choice.
int clampRetentionDays(int days) =>
    days.clamp(kRetentionDayChoices.first, kRetentionDayChoices.last);

/// Whether [name] is a version left behind by [kReplacedSuffix], rather than a
/// live file.
///
/// **This is the single most dangerous predicate in the backup feature.** A
/// prune is a delete loop over a remote, and everything it deletes is decided
/// here. A false positive deletes the user's actual data.
///
/// rclone's `--suffix` with `--suffix-keep-extension` inserts the suffix before
/// the extension, so `report.pdf` becomes `report.replaced.pdf`. Without the
/// keep-extension flag it appends, giving `report.pdf.replaced`. Both shapes are
/// recognised, because a config written by an older build may hold either.
///
/// Deliberately strict: the suffix must be a whole dot-separated segment. A file
/// genuinely named `my.replacedparts.txt` is not a version, and neither is
/// `replaced.txt` — a leading segment is the file's own name, not a marker
/// something replaced it.
bool isReplacedVersion(String name) {
  final parts = name.split('.');
  // Needs at least `stem`, `replaced` — and the marker can never be the first
  // segment, or a file simply named "replaced.txt" would qualify.
  if (parts.length < 2) return false;
  const marker = 'replaced';
  for (var i = 1; i < parts.length; i++) {
    if (parts[i] == marker) return true;
  }
  return false;
}

/// The live filename a version belongs to, or null if [name] is not a version.
///
/// `report.replaced.pdf` → `report.pdf`; `report.pdf.replaced` → `report.pdf`.
/// Used to show a restore UI which file a version is a version *of*, and to
/// make sure a prune never removes the last copy of something whose current
/// file has since been deleted.
String? liveNameFor(String name) {
  if (!isReplacedVersion(name)) return null;
  final parts = name.split('.');
  const marker = 'replaced';
  for (var i = parts.length - 1; i >= 1; i--) {
    if (parts[i] == marker) {
      parts.removeAt(i);
      return parts.join('.');
    }
  }
  return null;
}

/// What a prune would delete, given a listing and a cutoff.
///
/// Pure and separate from the deleting, which is the whole point: a delete loop
/// over a remote is the most destructive thing this app does, and the decision
/// about *what* to delete should be inspectable, testable and dry-runnable
/// without a network call.
///
/// Two rules, and the second is the one that makes it safe:
///
///  * Only files [isReplacedVersion] recognises are candidates.
///  * A version is kept if it is the **only** remaining copy of its live file —
///    i.e. nothing in [entries] carries the name it is a version of. That case
///    arises when the current file was deleted at the source and the backup
///    copied that deletion forward; the version is then not a redundant old
///    copy, it is the last copy in existence.
///
/// [now] is injected rather than read, so the cutoff is testable.
List<RcloneFile> prunableVersions({
  required List<RcloneFile> entries,
  required int retentionDays,
  required DateTime now,
}) {
  final cutoff = now.subtract(
    Duration(days: clampRetentionDays(retentionDays)),
  );
  final liveNames = {
    for (final e in entries)
      if (!e.isDir && !isReplacedVersion(e.name)) e.name,
  };
  return [
    for (final e in entries)
      if (!e.isDir && isReplacedVersion(e.name))
        if (liveNames.contains(liveNameFor(e.name)))
          if (e.modTime != null && e.modTime!.isBefore(cutoff)) e,
  ];
}

/// The parent folder of a remote-relative path, or `''` at the root.
String parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// [prunableVersions] over a RECURSIVE listing, grouped by folder.
///
/// The trap this exists to close: [prunableVersions] decides whether a version
/// is the last copy of its file by looking for a live file of that name **in the
/// same listing**. Hand it a recursive listing and `a/report.pdf` vouches for
/// `b/report.replaced.pdf` — a version in a completely different folder is then
/// judged redundant and deleted, when it may be the only copy left.
///
/// Grouping by parent restores the rule to what it means: a version is redundant
/// only when its live file sits **beside** it.
List<RcloneFile> prunableVersionsRecursive({
  required List<RcloneFile> entries,
  required int retentionDays,
  required DateTime now,
}) {
  final byFolder = <String, List<RcloneFile>>{};
  for (final e in entries) {
    (byFolder[parentOf(e.path)] ??= []).add(e);
  }
  return [
    for (final group in byFolder.values)
      ...prunableVersions(
        entries: group,
        retentionDays: retentionDays,
        now: now,
      ),
  ];
}

/// Total bytes held by versions in [entries], so the cost is not invisible.
int versionBytes(List<RcloneFile> entries) => entries
    .where((e) => !e.isDir && isReplacedVersion(e.name))
    .fold(0, (sum, e) => sum + (e.size < 0 ? 0 : e.size));

/// Persisted retention window.
class BackupRetention extends Notifier<int> {
  static const _key = 'backup_retention_days';

  @override
  int build() {
    _load();
    return kDefaultRetentionDays;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt(_key);
      if (v != null) state = clampRetentionDays(v);
    } catch (_) {
      // The default is a reasonable answer; a prune reads whatever we hold.
    }
  }

  Future<void> set(int days) async {
    final v = clampRetentionDays(days);
    if (v == state) return;
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key, v);
    } catch (_) {
      // Best effort.
    }
  }
}

final backupRetentionProvider = NotifierProvider<BackupRetention, int>(
  BackupRetention.new,
);
