import 'package:flutter/foundation.dart';

import 'mount_info.dart';

/// Everything Airclone tunes on an `rclone mount`, and the single place that
/// maps it to the RC wire format.
///
/// Airclone used to send exactly one option — `vfsOpt.CacheMode` — and take
/// rclone's stock defaults for the rest. Several of those are wrong for a
/// desktop file manager, and the symptom was reported from the field: while a
/// mounted drive was uploading, Explorer would not list other folders or draw
/// thumbnails. The cause is the READ path, not concurrency:
///
///  * `--vfs-cache-mode writes` (the old default) means, in rclone's words,
///    "files opened for read only are still read directly from the remote" — so
///    every thumbnail is an uncached network read, every time;
///  * `--vfs-read-chunk-size` defaults to 128Mi with no doubling limit, so
///    reading a thumbnail's first few KB starts a 128 MiB request;
///  * `--attr-timeout` defaults to 1s, so Explorer re-stats an already-busy VFS
///    constantly.
///
/// Raising `--transfers` would make this WORSE, not better: the VFS writeback
/// queue already runs that many uploads concurrently, each with its own buffer.
/// It is deliberately not a field here.
///
/// Kept pure — no Flutter widgets, no Riverpod, no `dart:io` — because the wire
/// format is the part that must be exactly right and silently is not: rclone
/// reshapes `vfsOpt`/`mountOpt` by marshalling JSON into a Go struct, and
/// `encoding/json` DROPS keys it does not recognise. A typo'd option name is
/// therefore accepted, ignored, and looks exactly like success. Unit tests over
/// [toVfsOpt] and [toMountOpt] are the guard against that; see also the live
/// read-back in `dev/plans/mount-tuning-plan.md`.
@immutable
class MountOptions {
  const MountOptions({
    this.cacheMode = 'full',
    this.cacheMaxSize = '10Gi',
    this.cacheMaxAge = '24h',
    this.chunkSize = '32Mi',
    this.chunkSizeLimit = '1Gi',
    this.dirCacheTime = '5m',
    this.attrTimeout = '5s',
    this.fastFingerprint = true,
    this.networkMode = false,
  });

  /// `--vfs-cache-mode`. `full` by default: it is the only mode that caches
  /// READS, which is what stops a folder of thumbnails being re-downloaded on
  /// every visit. Bounded by [cacheMaxSize] and [cacheMaxAge] so it cannot run
  /// away with a disk.
  final String cacheMode;

  /// `--vfs-cache-max-size`. **Per mount, not global** — three mounts at the
  /// default is 30 GiB. The editor says so next to the field.
  final String cacheMaxSize;

  /// `--vfs-cache-max-age`. rclone's 1h default evicts a thumbnail cache before
  /// it can pay for itself.
  final String cacheMaxAge;

  /// `--vfs-read-chunk-size`. Smaller than rclone's 128Mi so a metadata or
  /// thumbnail read is cheap.
  final String chunkSize;

  /// `--vfs-read-chunk-size-limit`. Chunks still double up to here, so a large
  /// sequential read reaches full speed; unlike rclone's `off`, it is bounded.
  final String chunkSizeLimit;

  /// `--dir-cache-time`. rclone's own default, exposed because it is the first
  /// thing worth raising on a slow remote.
  final String dirCacheTime;

  /// `--attr-timeout` (a MOUNT option, not a VFS one).
  final String attrTimeout;

  /// `--vfs-fast-fingerprint`: fewer metadata round-trips on change detection.
  final bool fastFingerprint;

  /// `--network-mode`, Windows only. Off by default — a mounted drive stays a
  /// normal one. Turning it on stops Windows treating the mount as local
  /// storage (the Search Indexer will not crawl it), at the cost of it
  /// appearing under Network rather than as a drive.
  final bool networkMode;

  /// What a mount gets when the user has never changed anything.
  static const MountOptions defaults = MountOptions();

  MountOptions copyWith({
    String? cacheMode,
    String? cacheMaxSize,
    String? cacheMaxAge,
    String? chunkSize,
    String? chunkSizeLimit,
    String? dirCacheTime,
    String? attrTimeout,
    bool? fastFingerprint,
    bool? networkMode,
  }) => MountOptions(
    cacheMode: cacheMode ?? this.cacheMode,
    cacheMaxSize: cacheMaxSize ?? this.cacheMaxSize,
    cacheMaxAge: cacheMaxAge ?? this.cacheMaxAge,
    chunkSize: chunkSize ?? this.chunkSize,
    chunkSizeLimit: chunkSizeLimit ?? this.chunkSizeLimit,
    dirCacheTime: dirCacheTime ?? this.dirCacheTime,
    attrTimeout: attrTimeout ?? this.attrTimeout,
    fastFingerprint: fastFingerprint ?? this.fastFingerprint,
    networkMode: networkMode ?? this.networkMode,
  );

  /// The `vfsOpt` object for `mount/mount`.
  ///
  /// Keys are rclone's **Go field names**, not its command-line flags, and
  /// durations/sizes go over as strings ("24h", "32Mi") which rclone's
  /// `fs.Duration` / `fs.SizeSuffix` parse. `CacheMode` is the one exception:
  /// it is an int, and was already sent that way before this existed.
  Map<String, Object?> toVfsOpt() => <String, Object?>{
    'CacheMode': cacheModeValue(cacheMode),
    'CacheMaxSize': cacheMaxSize,
    'CacheMaxAge': cacheMaxAge,
    'ChunkSize': chunkSize,
    'ChunkSizeLimit': chunkSizeLimit,
    'DirCacheTime': dirCacheTime,
    'FastFingerprint': fastFingerprint,
  };

  /// The `mountOpt` object for `mount/mount`.
  ///
  /// [windows] is passed in rather than read from `Platform` so this file stays
  /// free of `dart:io` and the mapping is testable on any host. `NetworkMode` is
  /// omitted entirely off Windows — rclone documents it as Windows-only, and
  /// sending a flag that platform cannot honour would be noise in a bug report.
  Map<String, Object?> toMountOpt({required bool windows}) => <String, Object?>{
    'AttrTimeout': attrTimeout,
    if (windows) 'NetworkMode': networkMode,
  };

  /// How many fields differ from [other] — what the mount dialog's collapsed
  /// summary reports so a user can see at a glance that they are looking at a
  /// deviation from their saved defaults rather than the defaults themselves.
  int changedFrom(MountOptions other) {
    var n = 0;
    if (cacheMode != other.cacheMode) n++;
    if (cacheMaxSize != other.cacheMaxSize) n++;
    if (cacheMaxAge != other.cacheMaxAge) n++;
    if (chunkSize != other.chunkSize) n++;
    if (chunkSizeLimit != other.chunkSizeLimit) n++;
    if (dirCacheTime != other.dirCacheTime) n++;
    if (attrTimeout != other.attrTimeout) n++;
    if (fastFingerprint != other.fastFingerprint) n++;
    if (networkMode != other.networkMode) n++;
    return n;
  }

  /// The one-line state shown on the collapsed disclosure. Deliberately short:
  /// it has to read as a summary, not as a second copy of the form.
  String get summary => [
    'Cache: $cacheMode',
    if (cacheMode == 'full' || cacheMode == 'writes') cacheMaxSize,
    cacheMaxAge,
    if (networkMode) 'network drive on',
  ].join(' · ');

  // --- Persistence -----------------------------------------------------------

  Map<String, Object?> toJson() => <String, Object?>{
    'cacheMode': cacheMode,
    'cacheMaxSize': cacheMaxSize,
    'cacheMaxAge': cacheMaxAge,
    'chunkSize': chunkSize,
    'chunkSizeLimit': chunkSizeLimit,
    'dirCacheTime': dirCacheTime,
    'attrTimeout': attrTimeout,
    'fastFingerprint': fastFingerprint,
    'networkMode': networkMode,
  };

  /// Tolerant by design: a value of the wrong type, or a key that a future
  /// version removed, falls back to the shipped default for that field rather
  /// than throwing. A corrupt preference must never be able to stop the mount
  /// dialog opening.
  factory MountOptions.fromJson(Map<String, Object?> json) {
    String str(String key, String fallback) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : fallback;
    }

    bool flag(String key, bool fallback) {
      final v = json[key];
      return v is bool ? v : fallback;
    }

    const d = MountOptions.defaults;
    final mode = str('cacheMode', d.cacheMode);
    return MountOptions(
      // An unknown mode would silently become "writes" inside cacheModeValue;
      // reject it here instead so the UI never shows a value it cannot offer.
      cacheMode: mountCacheModes.contains(mode) ? mode : d.cacheMode,
      cacheMaxSize: str('cacheMaxSize', d.cacheMaxSize),
      cacheMaxAge: str('cacheMaxAge', d.cacheMaxAge),
      chunkSize: str('chunkSize', d.chunkSize),
      chunkSizeLimit: str('chunkSizeLimit', d.chunkSizeLimit),
      dirCacheTime: str('dirCacheTime', d.dirCacheTime),
      attrTimeout: str('attrTimeout', d.attrTimeout),
      fastFingerprint: flag('fastFingerprint', d.fastFingerprint),
      networkMode: flag('networkMode', d.networkMode),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MountOptions && changedFrom(other) == 0;

  @override
  int get hashCode => Object.hash(
    cacheMode,
    cacheMaxSize,
    cacheMaxAge,
    chunkSize,
    chunkSizeLimit,
    dirCacheTime,
    attrTimeout,
    fastFingerprint,
    networkMode,
  );
}
