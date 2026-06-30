import 'package:flutter/foundation.dart';

/// One file considered for de-duplication. Built from an `operations/list`
/// (lsjson) item that was requested with `showHash:true`.
@immutable
class DupFile {
  const DupFile({
    required this.path,
    required this.name,
    required this.size,
    required this.signature,
  });

  /// Path relative to the scanned root (rclone's `remote` param), unique per
  /// object — so `operations/deletefile` can target exactly this copy.
  final String path;
  final String name;
  final int size;

  /// Content signature: size + every available hash. `null` when the backend
  /// exposed no hash for this file (then it is NOT a de-dupe candidate — we
  /// never guess identity from size alone).
  final String? signature;

  /// Parses an lsjson item. Returns null for directories or files with no hash.
  static DupFile? fromJson(Map<String, dynamic> json) {
    if ((json['IsDir'] ?? false) as bool) return null;
    final hashes = json['Hashes'];
    if (hashes is! Map || hashes.isEmpty) return null;
    // Keep only non-empty hash values; sort by type for a stable signature.
    final entries = <String>[];
    for (final e in hashes.entries) {
      final v = e.value;
      if (v is String && v.isNotEmpty) entries.add('${e.key}:$v');
    }
    if (entries.isEmpty) return null;
    entries.sort();
    final size = (json['Size'] is num) ? (json['Size'] as num).toInt() : -1;
    return DupFile(
      path: (json['Path'] ?? '') as String,
      name: (json['Name'] ?? '') as String,
      size: size,
      signature: '$size|${entries.join('|')}',
    );
  }
}

/// A set of two-or-more files with identical content (same signature).
@immutable
class DupGroup {
  const DupGroup({required this.files});

  /// Distinct-path copies sharing one content signature. Always length >= 2.
  final List<DupFile> files;

  int get size => files.first.size;

  /// Bytes reclaimable if all but one copy are deleted.
  int get reclaimable => size * (files.length - 1);
}

/// Groups [files] into duplicate sets: same [DupFile.signature] across two or
/// more DISTINCT paths. Files with a null signature are ignored. Groups are
/// returned largest-reclaimable-first; within a group, files are path-sorted.
List<DupGroup> findDuplicateGroups(Iterable<DupFile> files) {
  final bySig = <String, List<DupFile>>{};
  for (final f in files) {
    final sig = f.signature;
    if (sig == null) continue;
    bySig.putIfAbsent(sig, () => <DupFile>[]).add(f);
  }
  final groups = <DupGroup>[];
  for (final list in bySig.values) {
    // Collapse accidental duplicate paths (defensive); need >= 2 real copies.
    final seen = <String>{};
    final distinct = <DupFile>[];
    for (final f in list) {
      if (seen.add(f.path)) distinct.add(f);
    }
    if (distinct.length < 2) continue;
    distinct.sort(
      (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
    );
    groups.add(DupGroup(files: distinct));
  }
  groups.sort((a, b) => b.reclaimable.compareTo(a.reclaimable));
  return groups;
}
