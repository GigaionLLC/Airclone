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
  ///
  /// The `fs` here is [listFs], not [fs] — see that function for why a local
  /// listing needs a different one.
  Map<String, dynamic> listParams(String path) => {
    'fs': listFsFor(fs: fs, type: type, isLocal: isLocal),
    'remote': path,
    'opt': {'noModTime': false, 'showHash': false},
  };

  @override
  bool operator ==(Object other) =>
      other is Remote && other.name == name && other.fs == fs;

  @override
  int get hashCode => Object.hash(name, fs);
}

/// rclone's `--copy-links` / `-L`, as a backend parameter.
const String _copyLinks = 'copy_links=true';

/// The `fs` to list a location with, which for a local one is NOT [Remote.fs].
///
/// **Why this exists.** rclone's local backend treats any reparse point as a
/// symlink and SKIPS it. On Windows that is not an exotic case: OneDrive's
/// Known Folder Move turns `Desktop`, `Documents` and `Music` into reparse
/// points, and `OneDrive` and `iCloudDrive` are reparse points themselves. All
/// of them are therefore absent from a listing — with no error, no warning and
/// nothing to click, so the app simply appears not to have the folder that
/// Explorer is showing next to it. The same default hides a symlinked folder on
/// macOS and Linux.
///
/// `copy_links` makes the backend follow them, and it is applied to the LISTING
/// ONLY, for two reasons:
///
///  * It is the only call that needs it. Once the folder is visible, every
///    later operation addresses it directly rather than discovering it through
///    its parent, and rclone reads through a reparse point perfectly well when
///    the path points at or into it — verified against 1.75.1 for listing,
///    navigating and copying.
///  * A global `-L` would change what a sync DOES, not merely what a listing
///    shows: symlinks would be copied as their contents everywhere, on every
///    platform. Making a folder visible should not quietly rewrite transfer
///    semantics.
///
/// Returns [fs] unchanged for anything that is not local, and for an fs that
/// already carries parameters, so this cannot double-apply.
@visibleForTesting
String listFsFor({
  required String fs,
  required String type,
  required bool isLocal,
}) {
  if (!isLocal && type != 'local') return fs;
  if (fs.contains(_copyLinks)) return fs;

  // A synthetic local peer's fs is a PATH (`C:/`, `/`), not `name:`. Splitting
  // it on the first colon would take the drive letter for a remote name and
  // produce `C,copy_links=true:/`, so these get the anonymous-backend form.
  if (isLocal) return ':local,$_copyLinks:$fs';

  // A configured `local` remote is `name:` or `name:path`; the parameters go
  // between the name and the colon.
  final colon = fs.indexOf(':');
  if (colon <= 0) return fs;
  return '${fs.substring(0, colon)},$_copyLinks${fs.substring(colon)}';
}
