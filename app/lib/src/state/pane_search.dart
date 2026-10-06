import 'package:flutter/foundation.dart';

import 'package:airclone_rc/airclone_rc.dart';
import '../ui/pane_drag.dart' show joinPath;

/// One pane search box, two reaches (dev/plans/search-scope-plan.md).
///
/// [folder] is the old Filter box: live, over the listing already on screen.
/// [subfolders] is the old Search dialog, moved into the pane: one recursive
/// listing of the pane's folder, kept while the query is refined.
enum SearchScope { folder, subfolders }

/// Where a [SearchScope.subfolders] scan stands.
enum SearchScanStatus { idle, scanning, done, error, cancelled }

/// The most entries one recursive scan keeps. A drive with millions of files
/// is one JSON answer in the engine and one list of objects here; past this
/// the search says it looked at part of the tree rather than eat the memory
/// of a phone or a television (plan §3 Q5).
const int kSearchScanCap = 250000;

/// How long a finished scan is reused when Subfolders is chosen again on the
/// same folder. Long enough that leaving a result and coming Back is instant;
/// short enough that a tree changed from elsewhere is not shown stale for long.
const Duration kSearchCacheTtl = Duration(minutes: 2);

/// `operations/list` options for the scan. Modification times are not shown in
/// results, so they are not fetched; the MIME type is kept so extensionless
/// files get the same icon they get in the browser.
const Map<String, Object?> kRecursiveScanOpt = {
  'recurse': true,
  'noModTime': true,
  'showHash': false,
};

/// One entry found by a recursive scan, already placed in the remote: rclone
/// answers with paths RELATIVE to the folder it listed, and that is resolved
/// once here so nothing downstream builds a path from the pane's folder.
@immutable
class SearchHit {
  const SearchHit({
    required this.entry,
    required this.parentPath,
    required this.relParent,
  });

  /// The entry; [RcloneFile.name] is its leaf.
  final RcloneFile entry;

  /// The folder it lives in, from the remote's root ('' = the root).
  final String parentPath;

  /// The same folder relative to where the search started ('' = there). What
  /// a result row shows, and what the query is matched against.
  final String relParent;

  String get absPath => joinPath(parentPath, entry.name);
}

/// The scan's answer as [SearchHit]s rooted at [basePath], capped at [cap].
/// Returns the hits and whether the cap cut the list short.
(List<SearchHit>, bool) hitsFromListing(
  List<RcloneFile> files,
  String basePath, {
  int cap = kSearchScanCap,
}) {
  final out = <SearchHit>[];
  for (final f in files) {
    if (out.length >= cap) return (out, true);
    final rel = f.path.isEmpty ? f.name : f.path;
    final slash = rel.lastIndexOf('/');
    final relParent = slash < 0 ? '' : rel.substring(0, slash);
    out.add(
      SearchHit(
        entry: f,
        parentPath: relParent.isEmpty
            ? basePath
            : joinPath(basePath, relParent),
        relParent: relParent,
      ),
    );
  }
  return (out, false);
}

/// The words of [query], lower-cased. Every one of them has to match.
List<String> queryTokens(String query) => query
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList(growable: false);

/// The This-folder rule: every word of [query] appears in [name], ignoring
/// case. An empty query matches everything.
bool matchesName(String name, String query) {
  final tokens = queryTokens(query);
  if (tokens.isEmpty) return true;
  final n = name.toLowerCase();
  return tokens.every(n.contains);
}

/// The Subfolders rule: every word appears in the name OR in the folder path
/// below the search root, so `2024 holiday` finds `Photos/2024/holiday.jpg`.
///
/// Ranked so the likeliest result is first: the name starts with the first
/// word, then the name holds every word, then only the path does; folders
/// before files within each; then by path. An empty query matches nothing —
/// there is no point listing a quarter of a million rows nobody asked for.
List<SearchHit> matchHits(List<SearchHit> all, String query) {
  final tokens = queryTokens(query);
  if (tokens.isEmpty) return const [];
  final ranked = <(int, SearchHit, String)>[];
  for (final h in all) {
    final name = h.entry.name.toLowerCase();
    final rel = h.relParent.toLowerCase();
    var inName = true;
    var ok = true;
    for (final t in tokens) {
      if (name.contains(t)) continue;
      inName = false;
      if (!rel.contains(t)) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    final rank = !inName ? 2 : (name.startsWith(tokens.first) ? 0 : 1);
    ranked.add((rank, h, '$rel/$name'));
  }
  ranked.sort((a, b) {
    final r = a.$1.compareTo(b.$1);
    if (r != 0) return r;
    final da = a.$2.entry.isDir, db = b.$2.entry.isDir;
    if (da != db) return da ? -1 : 1;
    return a.$3.compareTo(b.$3);
  });
  return [for (final r in ranked) r.$2];
}

/// The entries of [parentPath] among [all] — a result's folder-mates, which a
/// recursive scan has already listed. Rename checks names against them and
/// Quick Look walks them, so neither needs a listing of its own.
List<RcloneFile> siblingsIn(List<SearchHit> all, String parentPath) => [
  for (final h in all)
    if (h.parentPath == parentPath) h.entry,
];

/// One pane's search, beside its filter text ([BrowserState.filter] holds the
/// query for both scopes — one box, one string).
@immutable
class PaneSearch {
  const PaneSearch({
    this.scope = SearchScope.folder,
    this.open = false,
    this.status = SearchScanStatus.idle,
    this.hits = const [],
    this.scanned = 0,
    this.truncated = false,
    this.hiddenNames = 0,
    this.error,
    this.startedAt,
    this.selectedPath,
  });

  final SearchScope scope;

  /// Whether the phone/TV header shows the box instead of the breadcrumb. The
  /// desktop toolbar's box is always there and ignores it.
  final bool open;

  final SearchScanStatus status;

  /// The ranked matches of the current query in the scan (Subfolders only).
  final List<SearchHit> hits;

  /// How many entries the scan found (the denominator of "n matches in N").
  final int scanned;

  /// True when the scan hit [kSearchScanCap] and the rest was not searched.
  final bool truncated;

  /// Names a crypt remote could not decrypt during the scan — results may be
  /// missing them, and the search says so instead of a confident "No matches".
  final int hiddenNames;

  final String? error;

  /// When the running scan began, for the elapsed clock.
  final DateTime? startedAt;

  /// The highlighted result (full path). One at a time: bulk operations on
  /// results are a later phase of the plan.
  final String? selectedPath;

  bool get inSubfolders => scope == SearchScope.subfolders;

  PaneSearch copyWith({
    SearchScope? scope,
    bool? open,
    SearchScanStatus? status,
    List<SearchHit>? hits,
    int? scanned,
    bool? truncated,
    int? hiddenNames,
    String? error,
    bool clearError = false,
    DateTime? startedAt,
    String? selectedPath,
    bool clearSelected = false,
  }) => PaneSearch(
    scope: scope ?? this.scope,
    open: open ?? this.open,
    status: status ?? this.status,
    hits: hits ?? this.hits,
    scanned: scanned ?? this.scanned,
    truncated: truncated ?? this.truncated,
    hiddenNames: hiddenNames ?? this.hiddenNames,
    error: clearError ? null : (error ?? this.error),
    startedAt: startedAt ?? this.startedAt,
    selectedPath: clearSelected ? null : (selectedPath ?? this.selectedPath),
  );
}

/// Cancels a running recursive scan — the same shape as `CompareJob`.
class SearchJob {
  RcloneClient? _client;
  int? _jobid;
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  /// Stops the scan on the engine. Safe before the job exists and safe twice.
  Future<void> cancel() async {
    _cancelled = true;
    final c = _client;
    final j = _jobid;
    if (c == null || j == null) return;
    try {
      await RcApi(c).job.stop(j);
    } catch (_) {
      // Best effort: the job may already have finished.
    }
  }
}

/// Lists [basePath] on [fs] recursively as an ASYNC job and waits for it.
///
/// The synchronous form is what the old Search dialog used, and it failed on
/// exactly the remotes worth searching: every rpc carries a 30-second timeout.
/// Each poll here is a fast call, and the job id makes Cancel real. Returns
/// null when [job] was cancelled.
Future<List<RcloneFile>?> scanRecursive(
  RcloneClient client,
  String fs,
  String basePath, {
  required SearchJob job,
  Duration pollEvery = const Duration(milliseconds: 400),
}) async {
  final api = RcApi(client);
  final started = await api.operations.listAsync(
    fs,
    basePath,
    opt: kRecursiveScanOpt,
  );
  final jobid = (started['jobid'] as num?)?.toInt();
  // An engine that answered inline is still an answer.
  if (jobid == null) return RcOperations.parseList(started) ?? const [];
  job
    .._client = client
    .._jobid = jobid;
  if (job.cancelled) {
    await job.cancel(); // cancelled between dispatch and attach
    return null;
  }
  while (true) {
    await Future<void>.delayed(pollEvery);
    if (job.cancelled) return null;
    final st = await api.job.status(jobid);
    if (st['finished'] != true) continue;
    if (st['success'] != true) {
      // A stopped job reports failure; that is a cancel, not a fault.
      if (job.cancelled) return null;
      final err = (st['error'] ?? '').toString();
      throw RcloneException('operations/list', err.isEmpty ? 'failed' : err);
    }
    final out = st['output'];
    return RcOperations.parseList(
          out is Map ? out.cast<String, dynamic>() : const <String, dynamic>{},
        ) ??
        const [];
  }
}
