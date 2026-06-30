import 'package:flutter/foundation.dart';

/// How a transfer reconciles source and destination. [bisync] is two-way
/// (keeps both locations mirrored); the rest are one-way.
enum TransferMode { copy, move, sync, bisync }

/// How rclone decides two files are equal (skip vs. retransfer).
enum CompareMode { sizeModTime, size, checksum }

/// Immutable bundle of advanced Copy/Move/Sync settings.
///
/// The easy path does a one-click copy; this is the power path surfaced by
/// the transfer options dialog. [includes]/[excludes]/[filters] are raw rclone
/// patterns (one per entry). [extraFlags] are pre-tokenised CLI args used only
/// for the human-readable preview (e.g. `--transfers 8`).
@immutable
class TransferOptions {
  const TransferOptions({
    this.mode = TransferMode.copy,
    this.skipNewer = false,
    this.skipExisting = false,
    this.compare,
    this.dryRun = false,
    this.keepReplaced = false,
    this.resyncMode = 'path1',
    this.conflictResolve = 'none',
    this.conflictLoser = 'num',
    this.conflictSuffix = 'conflict',
    this.maxDeletePercent = 50,
    this.checkAccess = false,
    this.createEmptySrcDirs = false,
    this.baselineEstablished = false,
    this.includes = const [],
    this.excludes = const [],
    this.filters = const [],
    this.extraFlags = const [],
  });

  final TransferMode mode;

  /// Don't overwrite a destination file that is newer (`--update`).
  final bool skipNewer;

  /// Don't touch files that already exist on the destination
  /// (`--ignore-existing`).
  final bool skipExisting;

  /// Equality test; `null` leaves rclone's default (size + mod-time).
  final CompareMode? compare;

  /// Report-only run (`--dry-run`).
  final bool dryRun;

  /// Preserve overwritten/deleted destination files instead of losing them:
  /// rclone renames them in place with a `.replaced` suffix (`--suffix` +
  /// `--suffix-keep-extension`). Makes a sync/move recoverable.
  final bool keepReplaced;

  // ── Two-way sync (bisync) settings — only used when mode == bisync ─────────

  /// Which side wins during the one-time `--resync` baseline: `path1` (default),
  /// `path2`, `newer`, `older`, `larger`, `smaller`.
  final String resyncMode;

  /// How a both-sides-changed conflict is resolved: `none` (keep both, default),
  /// `newer`, `older`, `larger`, `smaller`, `path1`, `path2`.
  final String conflictResolve;

  /// What happens to the losing side of a resolved conflict: `num` (auto-number,
  /// default), `pathname`, `delete`.
  final String conflictLoser;

  /// Suffix used when both versions are kept (`--conflict-suffix`).
  final String conflictSuffix;

  /// bisync's own `--max-delete` guard, as a PERCENT 0–100 (default 50). Aborts
  /// a run that would delete more than this share. Distinct from the global
  /// `--max-delete` count. (See rclone.org/bisync.)
  final int maxDeletePercent;

  /// Require `RCLONE_TEST` sentinel files on both sides before running
  /// (`--check-access`). Opt-in safety; off by default.
  final bool checkAccess;

  /// Propagate empty directories (`--create-empty-src-dirs`).
  final bool createEmptySrcDirs;

  /// Whether the one-time `--resync` baseline has been established for this
  /// (saved) pair. Flips true exactly once, on the first successful non-dry-run
  /// resync. Until then bisync runs must resync; the scheduler must not fire.
  final bool baselineEstablished;

  /// `--include` patterns.
  final List<String> includes;

  /// `--exclude` patterns.
  final List<String> excludes;

  /// `--filter` rules.
  final List<String> filters;

  /// Raw extra CLI flags for the preview, e.g. `--transfers 8`.
  final List<String> extraFlags;

  TransferOptions copyWith({
    TransferMode? mode,
    bool? skipNewer,
    bool? skipExisting,
    CompareMode? compare,
    bool? dryRun,
    bool? keepReplaced,
    String? resyncMode,
    String? conflictResolve,
    String? conflictLoser,
    String? conflictSuffix,
    int? maxDeletePercent,
    bool? checkAccess,
    bool? createEmptySrcDirs,
    bool? baselineEstablished,
    List<String>? includes,
    List<String>? excludes,
    List<String>? filters,
    List<String>? extraFlags,
  }) => TransferOptions(
    mode: mode ?? this.mode,
    skipNewer: skipNewer ?? this.skipNewer,
    skipExisting: skipExisting ?? this.skipExisting,
    compare: compare ?? this.compare,
    dryRun: dryRun ?? this.dryRun,
    keepReplaced: keepReplaced ?? this.keepReplaced,
    resyncMode: resyncMode ?? this.resyncMode,
    conflictResolve: conflictResolve ?? this.conflictResolve,
    conflictLoser: conflictLoser ?? this.conflictLoser,
    conflictSuffix: conflictSuffix ?? this.conflictSuffix,
    maxDeletePercent: maxDeletePercent ?? this.maxDeletePercent,
    checkAccess: checkAccess ?? this.checkAccess,
    createEmptySrcDirs: createEmptySrcDirs ?? this.createEmptySrcDirs,
    baselineEstablished: baselineEstablished ?? this.baselineEstablished,
    includes: includes ?? this.includes,
    excludes: excludes ?? this.excludes,
    filters: filters ?? this.filters,
    extraFlags: extraFlags ?? this.extraFlags,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'skipNewer': skipNewer,
    'skipExisting': skipExisting,
    'compare': compare?.name,
    'dryRun': dryRun,
    'keepReplaced': keepReplaced,
    // bisync settings: omit when at their defaults so legacy task JSON (which
    // never had these keys) round-trips byte-identical.
    if (resyncMode != 'path1') 'resyncMode': resyncMode,
    if (conflictResolve != 'none') 'conflictResolve': conflictResolve,
    if (conflictLoser != 'num') 'conflictLoser': conflictLoser,
    if (conflictSuffix != 'conflict') 'conflictSuffix': conflictSuffix,
    if (maxDeletePercent != 50) 'maxDeletePercent': maxDeletePercent,
    if (checkAccess) 'checkAccess': checkAccess,
    if (createEmptySrcDirs) 'createEmptySrcDirs': createEmptySrcDirs,
    if (baselineEstablished) 'baselineEstablished': baselineEstablished,
    'includes': includes,
    'excludes': excludes,
    'filters': filters,
    'extraFlags': extraFlags,
  };

  factory TransferOptions.fromJson(Map<String, dynamic> j) {
    List<String> list(Object? v) =>
        (v as List?)?.whereType<String>().toList() ?? const [];
    return TransferOptions(
      mode: TransferMode.values.firstWhere(
        (m) => m.name == j['mode'],
        orElse: () => TransferMode.copy,
      ),
      skipNewer: j['skipNewer'] == true,
      skipExisting: j['skipExisting'] == true,
      compare: j['compare'] == null
          ? null
          : CompareMode.values.firstWhere(
              (m) => m.name == j['compare'],
              orElse: () => CompareMode.sizeModTime,
            ),
      dryRun: j['dryRun'] == true,
      keepReplaced: j['keepReplaced'] == true,
      resyncMode: (j['resyncMode'] as String?) ?? 'path1',
      conflictResolve: (j['conflictResolve'] as String?) ?? 'none',
      conflictLoser: (j['conflictLoser'] as String?) ?? 'num',
      conflictSuffix: (j['conflictSuffix'] as String?) ?? 'conflict',
      maxDeletePercent: (j['maxDeletePercent'] as num?)?.toInt() ?? 50,
      checkAccess: j['checkAccess'] == true,
      createEmptySrcDirs: j['createEmptySrcDirs'] == true,
      baselineEstablished: j['baselineEstablished'] == true,
      includes: list(j['includes']),
      excludes: list(j['excludes']),
      filters: list(j['filters']),
      extraFlags: list(j['extraFlags']),
    );
  }
}

/// rclone subcommand name for a [TransferMode].
String _modeVerb(TransferMode m) => switch (m) {
  TransferMode.copy => 'copy',
  TransferMode.move => 'move',
  TransferMode.sync => 'sync',
  TransferMode.bisync => 'bisync',
};

/// Builds the read-only command shown on the preview tab.
///
/// Mirrors what [buildRcCall] sends, in CLI form — purely for display.
String rcloneCmdPreview(TransferOptions o, String src, String dst) {
  if (o.mode == TransferMode.bisync) return _bisyncCmdPreview(o, src, dst);

  final parts = <String>['rclone', _modeVerb(o.mode), '"$src"', '"$dst"'];

  if (o.skipNewer) parts.add('--update');
  if (o.skipExisting) parts.add('--ignore-existing');
  switch (o.compare) {
    case CompareMode.size:
      parts.add('--size-only');
    case CompareMode.checksum:
      parts.add('--checksum');
    case CompareMode.sizeModTime:
    case null:
      break;
  }
  if (o.dryRun) parts.add('--dry-run');
  if (o.keepReplaced) parts.add('--suffix .replaced --suffix-keep-extension');

  for (final p in o.includes) {
    if (p.trim().isEmpty) continue;
    parts.add('--include "${p.trim()}"');
  }
  for (final p in o.excludes) {
    if (p.trim().isEmpty) continue;
    parts.add('--exclude "${p.trim()}"');
  }
  for (final p in o.filters) {
    if (p.trim().isEmpty) continue;
    parts.add('--filter "${p.trim()}"');
  }
  for (final f in o.extraFlags) {
    if (f.trim().isEmpty) continue;
    parts.add(f.trim());
  }

  return parts.join(' ');
}

/// CLI preview for a two-way (bisync) run. Shows `--resync` while the baseline
/// hasn't been established yet.
String _bisyncCmdPreview(TransferOptions o, String p1, String p2) {
  final parts = <String>['rclone', 'bisync', '"$p1"', '"$p2"'];
  if (!o.baselineEstablished) {
    parts.add('--resync');
    if (o.resyncMode != 'path1') parts.add('--resync-mode ${o.resyncMode}');
  }
  if (o.conflictResolve != 'none') {
    parts.add('--conflict-resolve ${o.conflictResolve}');
  }
  if (o.conflictLoser != 'num') {
    parts.add('--conflict-loser ${o.conflictLoser}');
  }
  if (o.conflictSuffix != 'conflict') {
    parts.add('--conflict-suffix ${o.conflictSuffix}');
  }
  if (o.maxDeletePercent != 50) parts.add('--max-delete ${o.maxDeletePercent}');
  if (o.checkAccess) parts.add('--check-access');
  if (o.createEmptySrcDirs) parts.add('--create-empty-src-dirs');
  if (o.dryRun) parts.add('--dry-run');
  for (final p in o.includes) {
    if (p.trim().isEmpty) continue;
    parts.add('--include "${p.trim()}"');
  }
  for (final p in o.excludes) {
    if (p.trim().isEmpty) continue;
    parts.add('--exclude "${p.trim()}"');
  }
  for (final p in o.filters) {
    if (p.trim().isEmpty) continue;
    parts.add('--filter "${p.trim()}"');
  }
  return parts.join(' ');
}

/// Drops blank lines and trims each entry.
List<String> _clean(List<String> patterns) => [
  for (final p in patterns)
    if (p.trim().isNotEmpty) p.trim(),
];

/// Assembles the rclone RC call for [o] given full `fs<path>` strings.
///
/// Returns the method (`sync/copy` | `sync/move` | `sync/sync`) plus params
/// carrying `srcFs`/`dstFs`, a `_config` override map, and a `_filter` block of
/// include/exclude/filter rule lists. Runs async (`_async: true`).
({String method, Map<String, dynamic> params}) buildRcCall(
  TransferOptions o,
  String srcFs,
  String dstFs, {
  bool resync = false,
}) {
  // Two-way sync takes a different RC method + a top-level param shape (no
  // _config), so branch out before assembling the one-way call.
  if (o.mode == TransferMode.bisync) {
    return _buildBisyncCall(o, srcFs, dstFs, resync: resync);
  }

  final method = 'sync/${_modeVerb(o.mode)}';

  final config = <String, dynamic>{};
  if (o.dryRun) config['DryRun'] = true;
  if (o.skipExisting) config['IgnoreExisting'] = true;
  if (o.skipNewer) config['UpdateOlder'] = true;
  // Recoverable transfer: rename (don't delete/overwrite) replaced files.
  if (o.keepReplaced) {
    config['Suffix'] = '.replaced';
    config['SuffixKeepExtension'] = true;
  }
  switch (o.compare) {
    case CompareMode.size:
      config['SizeOnly'] = true;
    case CompareMode.checksum:
      config['Checksum'] = true;
    case CompareMode.sizeModTime:
    case null:
      break;
  }

  final params = <String, dynamic>{
    'srcFs': srcFs,
    'dstFs': dstFs,
    '_async': true,
  };
  if (config.isNotEmpty) params['_config'] = config;
  final filter = _filterBlock(o);
  if (filter != null) params['_filter'] = filter;

  return (method: method, params: params);
}

/// The `_filter` block (include/exclude/filter rule lists), or null when empty.
/// Shared by the one-way and bisync calls (filters apply to both).
Map<String, dynamic>? _filterBlock(TransferOptions o) {
  final filter = <String, dynamic>{};
  final inc = _clean(o.includes);
  final exc = _clean(o.excludes);
  final flt = _clean(o.filters);
  if (inc.isNotEmpty) filter['IncludeRule'] = inc;
  if (exc.isNotEmpty) filter['ExcludeRule'] = exc;
  if (flt.isNotEmpty) filter['FilterRule'] = flt;
  return filter.isEmpty ? null : filter;
}

/// Builds the `sync/bisync` call. bisync params are TOP-LEVEL (not `_config`);
/// only non-default values are sent. [resync] (the one-time baseline run) also
/// sends [TransferOptions.resyncMode]. Verified against rclone `cmd/bisync/rc.go`.
({String method, Map<String, dynamic> params}) _buildBisyncCall(
  TransferOptions o,
  String path1,
  String path2, {
  required bool resync,
}) {
  final params = <String, dynamic>{
    'path1': path1,
    'path2': path2,
    '_async': true,
  };
  if (resync) {
    params['resync'] = true;
    params['resyncMode'] = o.resyncMode; // only meaningful with resync
  }
  if (o.conflictResolve != 'none') {
    params['conflictResolve'] = o.conflictResolve;
  }
  if (o.conflictLoser != 'num') params['conflictLoser'] = o.conflictLoser;
  if (o.conflictSuffix != 'conflict') {
    params['conflictSuffix'] = o.conflictSuffix;
  }
  // bisync's --max-delete is a PERCENT (default 50); omit at default.
  if (o.maxDeletePercent != 50) params['maxDelete'] = o.maxDeletePercent;
  if (o.checkAccess) params['checkAccess'] = true;
  if (o.createEmptySrcDirs) params['createEmptySrcDirs'] = true;
  if (o.dryRun) params['dryRun'] = true;

  final filter = _filterBlock(o);
  if (filter != null) params['_filter'] = filter;

  return (method: 'sync/bisync', params: params);
}
