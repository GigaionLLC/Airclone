import 'package:flutter/foundation.dart';

/// A browsable location: a configured rclone remote, or a synthetic local-disk peer.
///
/// [fs] is the rclone "filesystem" prefix passed to RC calls:
///   - configured remote: `"gdrive:"`
///   - local disk:        an absolute path root like `"C:/"` or `"/"`.
/// Paths within the location are passed as the RC `remote` parameter.
@immutable
class Remote {
  const Remote({
    required this.name,
    required this.type,
    required this.fs,
    this.isLocal = false,
  });

  /// Config name (no trailing colon), or a label for local disks.
  final String name;

  /// Backend type, e.g. `drive`, `s3`, `local`.
  final String type;

  /// rclone fs prefix (see class doc).
  final String fs;

  /// True for synthetic local-disk peers (not in `rclone.conf`).
  final bool isLocal;

  /// Builds an `operations/list` parameter map for [path] within this remote.
  Map<String, dynamic> listParams(String path) => {
    'fs': fs,
    'remote': path,
    'opt': {'noModTime': false, 'showHash': false},
  };

  @override
  bool operator ==(Object other) =>
      other is Remote && other.name == name && other.fs == fs;

  @override
  int get hashCode => Object.hash(name, fs);
}
