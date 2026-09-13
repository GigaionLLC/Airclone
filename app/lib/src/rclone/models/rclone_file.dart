import 'package:flutter/foundation.dart';

/// The key the Web UI server adds to an `operations/list` entry to report that
/// its content is online-only. Prefixed so it cannot collide with a field
/// rclone adds later, and named once here so the writer and the reader cannot
/// drift apart.
const String kOnlineOnlyField = 'AirclonePlaceholder';

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
    this.onlineOnly,
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

  /// Whether this entry's content is online-only (a cloud placeholder), as
  /// answered by the HOST - or null when nobody answered.
  ///
  /// rclone never sets this. It is added by the Web UI server, which is the
  /// only party that can answer for a browser: the placeholder bit is a
  /// filesystem attribute on the machine serving the page, and the machine
  /// RENDERING the page has no access to it. Left null on desktop, where the
  /// app asks the filesystem directly.
  ///
  /// Three-valued on purpose. `false` means the host checked and the content is
  /// resident; null means nobody could check, which is not the same claim and
  /// must not be read as one.
  final bool? onlineOnly;

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
      // Airclone's own annotation, not rclone's - see [onlineOnly]. Absent for
      // a desktop build talking to the engine directly, which is why this is
      // read as a nullable rather than defaulted to false.
      onlineOnly: json[kOnlineOnlyField] is bool
          ? json[kOnlineOnlyField] as bool
          : null,
    );
  }
}
