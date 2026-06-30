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

/// Result of an `operations/check` comparison, bucketed by outcome. Each list
/// holds remote-relative file paths. [usedHash] is false when rclone had no
/// common hash to compare with (it then compared by size/modtime only, or by
/// streaming bytes when download was requested).
class CompareResult {
  const CompareResult({
    required this.success,
    required this.status,
    required this.hashType,
    required this.match,
    required this.missingOnSrc,
    required this.missingOnDst,
    required this.differ,
    required this.error,
  });

  final bool success;
  final String status;
  final String hashType;
  final List<String> match;
  final List<String> missingOnSrc;
  final List<String> missingOnDst;
  final List<String> differ;
  final List<String> error;

  bool get usedHash => hashType.isNotEmpty && hashType != 'none';

  factory CompareResult.fromRpc(Map<String, dynamic> m) {
    List<String> l(Object? v) =>
        (v as List?)?.whereType<String>().toList() ?? const [];
    return CompareResult(
      success: m['success'] == true,
      status: (m['status'] as Object?)?.toString() ?? '',
      hashType: (m['hashType'] as Object?)?.toString() ?? '',
      match: l(m['match']),
      missingOnSrc: l(m['missingOnSrc']),
      missingOnDst: l(m['missingOnDst']),
      differ: l(m['differ']),
      error: l(m['error']),
    );
  }
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

  /// Compares [srcFs] against [dstFs] (`operations/check`) and returns the
  /// per-bucket file lists. Set [download] to compare by streaming bytes when
  /// the backends share no hash. Returns null only when the engine isn't ready.
  Future<CompareResult?> compare(
    String srcFs,
    String dstFs, {
    bool download = false,
  }) async {
    final client = _client;
    if (client == null) return null;
    final res = await client.rpc('operations/check', {
      'srcFs': srcFs,
      'dstFs': dstFs,
      'download': download,
      'match': true,
      'missingOnSrc': true,
      'missingOnDst': true,
      'differ': true,
      'error': true,
    });
    return CompareResult.fromRpc(res);
  }

  /// File count + total byte size of [fs] (`operations/size`). [fs] is a full
  /// `remote:path` filesystem spec; `bytes` may be negative when unknown.
  Future<(int count, int bytes)> folderSize(String fs) async {
    final client = _client;
    if (client == null) return (0, 0);
    final res = await client.rpc('operations/size', {'fs': fs});
    int n(Object? v) => v is num ? v.toInt() : 0;
    return (n(res['count']), n(res['bytes']));
  }

  /// Streams [url] straight into [r] at [folderPath] (`operations/copyurl`),
  /// deriving the filename from the URL — no local round-trip.
  Future<void> copyUrl(Remote r, String folderPath, String url) async {
    final client = _client;
    if (client == null) return;
    await client.rpc('operations/copyurl', {
      'fs': r.fs,
      'remote': folderPath,
      'url': url,
      'autoFilename': true,
    });
  }

  /// Empties the backend trash / aborts incomplete uploads (`operations/cleanup`).
  /// Throws [RcloneException] when the backend doesn't support it.
  Future<void> cleanup(Remote r) async {
    final client = _client;
    if (client == null) return;
    await client.rpc('operations/cleanup', {'fs': r.fs});
  }
}

/// Exposes a single [FileOps] bound to the provider [Ref].
final fileOpsProvider = Provider<FileOps>(FileOps.new);
