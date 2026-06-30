import 'package:flutter/foundation.dart';

/// VFS cache modes (rclone `--vfs-cache-mode`). The RC takes the numeric value
/// under `vfsOpt.CacheMode`; "writes" is the safe usable default.
const mountCacheModes = ['off', 'minimal', 'writes', 'full'];
int cacheModeValue(String mode) => switch (mode) {
  'off' => 0,
  'minimal' => 1,
  'full' => 3,
  _ => 2, // writes
};

/// A live `rclone mount`, as reported by the `mount/listmounts` RC. Entries may
/// come back as a bare string (the mount point) or a struct with `MountPoint`
/// + `Fs`, so parse defensively (mirrors ServeServer.fromList).
@immutable
class MountInfo {
  const MountInfo({required this.mountPoint, required this.fs});

  final String mountPoint;
  final String fs;

  factory MountInfo.fromList(Object? e) {
    if (e is String) return MountInfo(mountPoint: e, fs: '');
    if (e is Map) {
      final m = e.cast<String, dynamic>();
      return MountInfo(
        mountPoint: (m['MountPoint'] as String?) ?? '',
        fs: (m['Fs'] as String?) ?? '',
      );
    }
    return const MountInfo(mountPoint: '', fs: '');
  }
}
