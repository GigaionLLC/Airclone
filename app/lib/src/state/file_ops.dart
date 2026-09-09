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

/// Cancels a long [FileOps.compare].
///
/// A comparison over a large tree runs for minutes, and until now the dialog
/// offered no way out: closing it left the job running on the engine. Holding
/// the jobid is what makes a real cancel possible rather than a cosmetic one.
class CompareJob {
  RcloneClient? _client;
  int? _jobid;
  bool _cancelled = false;

  /// True once [cancel] has been called. [FileOps.compare] returns null.
  bool get cancelled => _cancelled;

  void _attach(RcloneClient client, int jobid) {
    _client = client;
    _jobid = jobid;
  }

  /// Stops the running comparison. Safe before the job exists and safe twice.
  Future<void> cancel() async {
    _cancelled = true;
    final c = _client;
    final j = _jobid;
    if (c == null || j == null) return;
    try {
      await c.rpc('job/stop', {'jobid': j});
    } catch (_) {
      // Best effort: the job may already have finished. The caller has stopped
      // waiting either way, and a failed stop must not surface as an error.
    }
  }
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
  /// [config] and [filter] are passed straight through as rclone's `_config` /
  /// `_filter` blocks. The dry-run preview supplies the SAME ones the transfer
  /// will run with: check honours both, so a comparison made under different
  /// rules describes a different operation than the one about to happen.
  /// Pass a [CompareJob] to be able to cancel a long comparison.
  ///
  /// Runs ASYNC (`_async`) and polls `job/status`. The synchronous form could
  /// not survive its own success: every rpc carries a 30-second timeout, and a
  /// real tree does not answer inside it. A user comparing 13,356 files got
  /// `TimeoutException after 0:00:30` — the feature failing precisely on the
  /// trees big enough to need a preview. Each poll is a fast call, so there is
  /// no wall to hit, and the jobid gives the caller something to cancel.
  Future<CompareResult?> compare(
    String srcFs,
    String dstFs, {
    bool download = false,
    Map<String, dynamic>? config,
    Map<String, dynamic>? filter,
    CompareJob? job,
    Duration pollEvery = const Duration(milliseconds: 400),
  }) async {
    final client = _client;
    if (client == null) return null;
    final params = <String, dynamic>{
      'srcFs': srcFs,
      'dstFs': dstFs,
      'download': download,
      'match': true,
      'missingOnSrc': true,
      'missingOnDst': true,
      'differ': true,
      'error': true,
      if (config != null && config.isNotEmpty) '_config': config,
      if (filter != null && filter.isNotEmpty) '_filter': filter,
      '_async': true,
    };
    final started = await client.rpc('operations/check', params);
    final jobid = (started['jobid'] as num?)?.toInt();
    // An engine that answered inline rather than with a jobid is still a valid
    // answer - take it rather than insisting on the async shape.
    if (jobid == null) return CompareResult.fromRpc(started);
    job?._attach(client, jobid);
    if (job?.cancelled ?? false) {
      await job!.cancel(); // cancelled between dispatch and attach
      return null;
    }
    while (true) {
      await Future<void>.delayed(pollEvery);
      if (job?.cancelled ?? false) return null;
      final st = await client.rpc('job/status', {'jobid': jobid});
      if (st['finished'] != true) continue;
      if (st['success'] != true) {
        final err = (st['error'] ?? '').toString();
        // A stopped job reports failure; that is a cancel, not a fault.
        if (job?.cancelled ?? false) return null;
        throw RcloneException('operations/check', err.isEmpty ? 'failed' : err);
      }
      final out = st['output'];
      return CompareResult.fromRpc(
        out is Map ? out.cast<String, dynamic>() : const <String, dynamic>{},
      );
    }
  }

  /// Whether [fs] has any entry at its ROOT: false when it is empty, true when
  /// it is not, null when it cannot be read at all.
  ///
  /// A SHALLOW list, deliberately. The empty-source guard used to answer this
  /// with `operations/size` - a full recursive walk - BEFORE the first dialog
  /// appeared. On a 13,000-file tree that is a multi-second dead click, and a
  /// spinner does not make an O(tree) call in that position the right design.
  /// One listing answers the cases that actually happen (the source was deleted,
  /// renamed, or emptied) at the cost of one round trip.
  ///
  /// What it does NOT catch is a source that is a tree of empty directories: its
  /// root lists non-empty while it holds no files, so a one-way sync from it
  /// still deletes everything at the destination. That case is caught later, on
  /// the destructive path only - see the caller.
  Future<bool?> isRootEmpty(String fs) async {
    final client = _client;
    if (client == null) return null;
    try {
      final res = await client.rpc('operations/list', {
        'fs': fs,
        'remote': '',
        'opt': {'noModTime': true, 'showHash': false},
      });
      final list = res['list'];
      return list is List ? list.isEmpty : null;
    } catch (_) {
      return null; // unreadable - the caller refuses rather than guesses
    }
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
