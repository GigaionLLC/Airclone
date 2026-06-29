import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import 'engine_controller.dart';

/// Joins a remote-relative parent path with a leaf [name], avoiding a leading
/// slash when [parent] is empty (the remote root).
String join(String parent, String name) =>
    parent.isEmpty ? name : '$parent/$name';

/// Returns the parent portion of a remote-relative [path] (everything before the
/// last `/`), or the empty string when [path] is already at the root.
String _parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// Synchronous, single-shot file operations against a [Remote] via the rclone RC.
///
/// These are the quick, non-streaming mutations the browser issues directly
/// (create / rename / delete). Long-running transfers belong to the jobs module.
/// Every method resolves once rclone reports success and throws [RcloneException]
/// on failure; callers refresh the browser afterwards.
class FileOps {
  FileOps(this._ref);

  final Ref _ref;

  /// The live engine client, or `null` when the engine is not ready.
  RcloneClient? get _client => _ref.read(engineControllerProvider).client;

  /// Creates a new folder named [name] under [parentPath] within [r].
  ///
  /// Maps to `operations/mkdir {fs, remote}` where `remote` is the full
  /// remote-relative path of the new folder.
  Future<void> newFolder(Remote r, String parentPath, String name) async {
    final client = _client;
    if (client == null) return;
    await client.rpc('operations/mkdir', {
      'fs': r.fs,
      'remote': join(parentPath, name),
    });
  }

  /// Renames the entry at [path] within [r] to [newName], keeping it in place.
  ///
  /// Maps to `operations/movefile` within a single remote (src/dst fs equal).
  Future<void> rename(Remote r, String path, String newName) async {
    final client = _client;
    if (client == null) return;
    await client.rpc('operations/movefile', {
      'srcFs': r.fs,
      'srcRemote': path,
      'dstFs': r.fs,
      'dstRemote': join(_parentOf(path), newName),
    });
  }

  /// Deletes [f] (located under [parentPath]) within [r].
  ///
  /// Directories use `operations/purge` (recursive, removes contents); files use
  /// `operations/deletefile`.
  Future<void> deleteEntry(Remote r, RcloneFile f, String parentPath) async {
    final client = _client;
    if (client == null) return;
    final remote = join(parentPath, f.name);
    if (f.isDir) {
      await client.rpc('operations/purge', {'fs': r.fs, 'remote': remote});
    } else {
      await client.rpc('operations/deletefile', {'fs': r.fs, 'remote': remote});
    }
  }
}

/// Exposes a single [FileOps] bound to the provider [Ref].
final fileOpsProvider = Provider<FileOps>(FileOps.new);
