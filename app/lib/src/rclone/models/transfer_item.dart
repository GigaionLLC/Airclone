import 'package:flutter/foundation.dart';

/// One in-flight file within a transfer, as reported by rclone `core/stats`'
/// `transferring` array (per engine-wide stats or a single job's `_group`).
@immutable
class TransferItem {
  const TransferItem({
    required this.name,
    this.percentage = 0,
    this.speed = 0,
    this.bytes = 0,
    this.size = 0,
  });

  final String name;
  final int percentage;
  final double speed;
  final int bytes;
  final int size;

  /// Parses a `core/stats` `transferring` array (list of maps) into items.
  /// Non-list / non-map entries are skipped.
  static List<TransferItem> listFrom(Object? raw) {
    final out = <TransferItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          out.add(
            TransferItem(
              name: (e['name'] as Object?)?.toString() ?? '',
              percentage: _asInt(e['percentage']),
              speed: _asDouble(e['speed']),
              bytes: _asInt(e['bytes']),
              size: _asInt(e['size']),
            ),
          );
        }
      }
    }
    return out;
  }

  static int _asInt(Object? v) => v is num ? v.toInt() : 0;
  static double _asDouble(Object? v) => v is num ? v.toDouble() : 0;
}
