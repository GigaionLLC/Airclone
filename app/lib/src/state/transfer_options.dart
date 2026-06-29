import 'package:flutter/foundation.dart';

/// How a transfer reconciles source and destination.
enum TransferMode { copy, move, sync }

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
};

/// Builds the read-only command shown on the preview tab.
///
/// Mirrors what [buildRcCall] sends, in CLI form — purely for display.
String rcloneCmdPreview(TransferOptions o, String src, String dst) {
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
  String dstFs,
) {
  final method = 'sync/${_modeVerb(o.mode)}';

  final config = <String, dynamic>{};
  if (o.dryRun) config['DryRun'] = true;
  if (o.skipExisting) config['IgnoreExisting'] = true;
  if (o.skipNewer) config['UpdateOlder'] = true;
  switch (o.compare) {
    case CompareMode.size:
      config['SizeOnly'] = true;
    case CompareMode.checksum:
      config['Checksum'] = true;
    case CompareMode.sizeModTime:
    case null:
      break;
  }

  final filter = <String, dynamic>{};
  final inc = _clean(o.includes);
  final exc = _clean(o.excludes);
  final flt = _clean(o.filters);
  if (inc.isNotEmpty) filter['IncludeRule'] = inc;
  if (exc.isNotEmpty) filter['ExcludeRule'] = exc;
  if (flt.isNotEmpty) filter['FilterRule'] = flt;

  final params = <String, dynamic>{
    'srcFs': srcFs,
    'dstFs': dstFs,
    '_async': true,
  };
  if (config.isNotEmpty) params['_config'] = config;
  if (filter.isNotEmpty) params['_filter'] = filter;

  return (method: method, params: params);
}
