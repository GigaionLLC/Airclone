import 'package:flutter/foundation.dart';

/// One entry returned by rclone's `operations/list` (lsjson shape).
@immutable
class RcloneFile {
  const RcloneFile({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = -1,
    this.mimeType = '',
    this.modTime,
  });

  /// Leaf name, e.g. `report.pdf`.
  final String name;

  /// Path relative to the remote's fs, e.g. `Work/Q1/report.pdf`.
  final String path;

  final bool isDir;

  /// Size in bytes; `-1` for directories or unknown.
  final int size;

  final String mimeType;

  final DateTime? modTime;

  factory RcloneFile.fromJson(Map<String, dynamic> json) {
    DateTime? mod;
    final raw = json['ModTime'];
    if (raw is String && raw.isNotEmpty) {
      mod = DateTime.tryParse(raw);
    }
    return RcloneFile(
      name: (json['Name'] ?? '') as String,
      path: (json['Path'] ?? '') as String,
      isDir: (json['IsDir'] ?? false) as bool,
      size: (json['Size'] is num) ? (json['Size'] as num).toInt() : -1,
      mimeType: (json['MimeType'] ?? '') as String,
      modTime: mod,
    );
  }
}
