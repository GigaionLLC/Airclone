import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';

/// Joins a parent path and a leaf name with a single forward slash.
/// Empty parent yields the bare name (remote root).
String joinPath(String parent, String name) =>
    parent.isEmpty ? name : '$parent/$name';

/// Payload dragged from a file row/tile — one file, or the whole selection.
/// Shared by the list ([BrowserPane]) and grid ([FileGrid]) views and the
/// sidebar drop targets, so it lives here rather than in any one view.
///
/// Serializable so it can ride along as the `localData` of a native
/// (`super_drag_and_drop`) drag, which is how the same gesture serves both an
/// in-app drop and an OS drag-out.
class PaneDragData {
  const PaneDragData(this.remote, this.parentPath, this.files);
  final Remote remote;
  final String parentPath;
  final List<RcloneFile> files;

  Map<String, dynamic> toJson() => {
    'remote': {
      'name': remote.name,
      'type': remote.type,
      'fs': remote.fs,
      'isLocal': remote.isLocal,
    },
    'parentPath': parentPath,
    'files': [
      for (final f in files)
        {
          'name': f.name,
          'path': f.path,
          'isDir': f.isDir,
          'size': f.size,
          'mimeType': f.mimeType,
          'modTime': f.modTime?.toIso8601String(),
        },
    ],
  };

  factory PaneDragData.fromJson(Map<String, dynamic> j) {
    final r = (j['remote'] as Map).cast<String, dynamic>();
    final files = <RcloneFile>[
      for (final raw in (j['files'] as List))
        () {
          final m = (raw as Map).cast<String, dynamic>();
          final mod = m['modTime'];
          return RcloneFile(
            name: (m['name'] ?? '') as String,
            path: (m['path'] ?? '') as String,
            isDir: (m['isDir'] ?? false) as bool,
            size: (m['size'] is num) ? (m['size'] as num).toInt() : -1,
            mimeType: (m['mimeType'] ?? '') as String,
            modTime: (mod is String && mod.isNotEmpty)
                ? DateTime.tryParse(mod)
                : null,
          );
        }(),
    ];
    return PaneDragData(
      Remote(
        name: (r['name'] ?? '') as String,
        type: (r['type'] ?? '') as String,
        fs: (r['fs'] ?? '') as String,
        isLocal: (r['isLocal'] ?? false) as bool,
      ),
      (j['parentPath'] ?? '') as String,
      files,
    );
  }
}
