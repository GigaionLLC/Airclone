import 'package:flutter/foundation.dart';

/// One completed (or failed) transfer, from rclone's `core/transferred` RC.
///
/// Field names match rclone's `TransferSnapshot` JSON exactly — note the mixed
/// casing (`started_at`/`completed_at` snake_case vs `srcFs`/`dstFs` camelCase),
/// and that `error` is ALWAYS present (empty string on success) so success is
/// determined by an empty error, not a missing key. (The public rc docs page is
/// stale — there is no `jobid`/`timestamp`; correlate via [group] instead.)
@immutable
class TransferredItem {
  const TransferredItem({
    required this.name,
    required this.size,
    required this.bytes,
    required this.checked,
    required this.what,
    required this.group,
    this.srcFs,
    this.dstFs,
    this.error,
    this.startedAt,
    this.completedAt,
  });

  final String name;
  final int size;
  final int bytes;
  final bool checked;
  final String what;
  final String group;
  final String? srcFs;
  final String? dstFs;
  final String? error;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get failed => error != null && error!.isNotEmpty;
  bool get succeeded => !failed;

  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static String _str(Object? v) => v?.toString() ?? '';
  static String? _strOrNull(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Parses an RFC3339 time, treating Go's zero-time as null (rclone always
  /// emits `started_at`/`completed_at`, even for never-started entries).
  static DateTime? _time(Object? v) {
    final s = v?.toString();
    if (s == null || s.isEmpty || s.startsWith('0001-01-01')) return null;
    return DateTime.tryParse(s);
  }

  factory TransferredItem.fromJson(Map json) => TransferredItem(
    name: _str(json['name']),
    size: _int(json['size']),
    bytes: _int(json['bytes']),
    checked: json['checked'] == true,
    what: _str(json['what']),
    group: _str(json['group']),
    srcFs: _strOrNull(json['srcFs']),
    dstFs: _strOrNull(json['dstFs']),
    error: _strOrNull(json['error']),
    startedAt: _time(json['started_at']),
    completedAt: _time(json['completed_at']),
  );

  /// Reads the `transferred` list from a `core/transferred` response, newest
  /// first (rclone returns oldest-first). Tolerant of a missing/non-list key.
  static List<TransferredItem> listFromResponse(Map<String, dynamic> res) {
    final raw = res['transferred'];
    if (raw is! List) return const [];
    final items = <TransferredItem>[
      for (final e in raw)
        if (e is Map) TransferredItem.fromJson(e),
    ];
    return items.reversed.toList();
  }
}
