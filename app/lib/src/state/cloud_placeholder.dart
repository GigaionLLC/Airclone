import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../rclone/models/remote.dart';

/// Guards against silently HYDRATING cloud "Files On-Demand" placeholders.
///
/// On Windows (Cloud Files API — Proton Drive, OneDrive, iCloud, Dropbox, Google
/// Drive) and macOS (File Provider) a synced file can be an online-only
/// PLACEHOLDER: listing/stat is free, but reading its CONTENT forces the OS to
/// download the WHOLE file. Airclone reads full content in a few places
/// (thumbnails, dedupe, checksum); if the browsed local path lives inside a sync
/// root, those reads trigger unexpected multi-GB downloads. This module lets
/// those call sites skip an online-only file BEFORE touching its bytes.

// Windows placeholder attributes. Any one set => online-only (content not local).
const int _attrRecallOnDataAccess = 0x00400000; // hydrate on any data read
const int _attrRecallOnOpen = 0x00040000; // hydrate on open
const int _attrOffline = 0x00001000; // content not resident
const int _invalidFileAttributes = 0xFFFFFFFF; // GetFileAttributesW failure

typedef _GetFileAttributesWC = Uint32 Function(Pointer<Utf16>);
typedef _GetFileAttributesWDart = int Function(Pointer<Utf16>);

/// Bound once. Null on non-Windows (or if kernel32 won't load), which makes
/// [isOnlineOnlyPlaceholder] a safe no-op there.
final _GetFileAttributesWDart? _getFileAttributesW = _bindGetFileAttributesW();

_GetFileAttributesWDart? _bindGetFileAttributesW() {
  if (!Platform.isWindows) return null;
  try {
    return DynamicLibrary.open(
      'kernel32.dll',
    ).lookupFunction<_GetFileAttributesWC, _GetFileAttributesWDart>(
      'GetFileAttributesW',
    );
  } catch (_) {
    return null;
  }
}

/// True when reading [absolutePath]'s CONTENT would hydrate (download) an
/// online-only cloud placeholder. Windows-only today; returns false on other
/// platforms, on any error, and for an unresolvable path.
///
/// Fail-OPEN by design: a false positive only costs a thumbnail (we show the
/// kind icon instead); a false negative costs a silent multi-GB download. So we
/// act only on a definitive "yes" and treat everything uncertain as local.
bool isOnlineOnlyPlaceholder(String absolutePath) {
  final fn = _getFileAttributesW;
  if (fn == null || absolutePath.isEmpty) return false;
  Pointer<Utf16>? p;
  try {
    p = absolutePath.toNativeUtf16();
    final attrs = fn(p);
    if (attrs == _invalidFileAttributes) return false;
    const mask = _attrRecallOnDataAccess | _attrRecallOnOpen | _attrOffline;
    return (attrs & mask) != 0;
  } catch (_) {
    return false;
  } finally {
    if (p != null) malloc.free(p);
  }
}

// ── Wrapper remotes over a local backing store ──────────────────────────────
//
// A `crypt`, `alias`, `chunker` or `compress` remote can point at a LOCAL path.
// Its Remote.type is then "crypt"/"alias"/..., never "local", so the type check
// below used to give up and report "not local" - which [wouldHydrateOnRead]
// turned into "safe to read". A crypt-over-Proton-Drive remote therefore
// bypassed this guard completely, which is the opposite of what it exists for.
//
// Resolution needs the rclone config, which is async, while this guard is called
// synchronously from widget builds. So the map is computed once when the remote
// list loads (see remotes_provider.dart) and cached here.

Map<String, String?> _backingRoots = const {};

/// Cache of remote name -> absolute LOCAL root it ultimately sits on, or null
/// when it resolves to a cloud backend (which cannot hold placeholders).
/// A name ABSENT from the map is unresolved - not the same as null, and callers
/// that are about to read a whole tree must treat absence as "do not proceed".
void setRemoteBackingRoots(Map<String, String?> roots) {
  _backingRoots = Map.unmodifiable(roots);
}

/// Wrapper backends that take a single `remote =` pointing at another remote or
/// a filesystem path. `union`/`combine` take a LIST and are deliberately absent:
/// they stay unresolved, so tree-walk callers fail closed on them.
const _wrapperTypes = {'crypt', 'alias', 'chunker', 'compress'};

/// Every type whose backing store COULD be local: the wrappers above plus the
/// list-shaped ones this module does not follow. Anything outside this set is a
/// real backend and is definitively not local.
const _localCapableTypes = {
  'crypt',
  'alias',
  'chunker',
  'compress',
  'union',
  'combine',
};

/// Resolves `name` through any chain of wrapper remotes to the absolute local
/// path it is backed by, or null when it ends at a cloud backend or cannot be
/// resolved. [dump] is `config/dump`'s response.
String? resolveLocalBackingRoot(
  String name,
  Map<String, dynamic> dump, [
  int depth = 0,
]) {
  if (depth > 8) return null; // cyclic or absurd config
  final cfg = dump[name];
  if (cfg is! Map) return null;
  final type = cfg['type']?.toString();
  if (type == 'local') return ''; // rooted by the browse path itself
  if (!_wrapperTypes.contains(type)) return null; // a real cloud backend
  final target = (cfg['remote'] ?? '').toString();
  if (target.isEmpty) return null;
  if (target.startsWith('/')) return target; // absolute POSIX path
  final i = target.indexOf(':');
  if (i <= 0) return null;
  final head = target.substring(0, i);
  final rest = target.substring(i + 1);
  // The CONFIG decides, not the shape. A remote named `b` is written `b:`,
  // which matches a drive letter perfectly - so a single-letter remote used to
  // resolve to the literal path "b:" and, worse, ended a cycle by accident
  // rather than by the depth guard. Look the name up first; only fall back to
  // a drive letter when no such remote exists, and require the separator
  // (`C:/x`, `C:\x`) that a bare remote reference never has.
  if (dump.containsKey(head)) {
    final base = resolveLocalBackingRoot(head, dump, depth + 1);
    if (base == null) return null;
    if (rest.isEmpty) return base;
    return base.isEmpty ? rest : _joinLocal(base, rest);
  }
  if (RegExp(r'^[A-Za-z]:[\/]').hasMatch(target)) return target;
  return null;
}

/// Builds the whole name -> local-root map from a `config/dump`, for
/// [setRemoteBackingRoots].
///
/// Owns the ABSENCE rule, which a caller kept getting wrong: a name is omitted
/// when this module cannot follow its type at all (`union`, `combine`, which
/// take a LIST of upstreams rather than a single `remote =`). Publishing those
/// with a null value made [isLocalBacked] read them as a definitive "not local"
/// — the key was present, the value was null — and a union sitting on a sync
/// folder went straight past the dedupe consent prompt. Absent means unknown;
/// null means known-to-be-cloud. They are not the same and the difference is a
/// silent multi-GB download.
Map<String, String?> resolveBackingRoots(Map<String, dynamic> dump) {
  final out = <String, String?>{};
  for (final name in dump.keys) {
    final cfg = dump[name];
    final type = (cfg is Map ? cfg['type'] : null)?.toString();
    if (type == null) continue; // unclassifiable -> absent -> unknown
    if (_unfollowableTypes.contains(type)) continue; // absent on purpose
    out[name] = resolveLocalBackingRoot(name, dump);
  }
  return out;
}

/// Types whose backing store could be local but which this module does not
/// follow. They must stay ABSENT from the map, not present-with-null.
const _unfollowableTypes = {'union', 'combine'};

/// Whether [remote] is known to sit on local storage. Null means UNRESOLVED -
/// the config has not been read yet, or the type is one this module does not
/// follow (`union`, `combine`). Callers about to read a whole tree must refuse
/// on null rather than assume it is safe.
bool? isLocalBacked(Remote remote) {
  if (remote.type == 'local') return true;
  // A real backend - drive, s3, sftp, b2 - cannot be a local placeholder
  // whatever the config says, so the TYPE settles it and no lookup is needed.
  // Without this, a plain cloud remote fell into "might be local" whenever the
  // backing map had not been populated yet, and every dedupe scan on it would
  // have prompted about downloads that were never going to happen.
  if (!_localCapableTypes.contains(remote.type)) {
    return remote.type == 'unknown' ? null : false;
  }
  if (!_backingRoots.containsKey(remote.name)) return null;
  return _backingRoots[remote.name] != null;
}

/// Resolves a browse entry ([pathWithinRemote] = the RC `remote` param) to an
/// absolute local filesystem path, or null when [remote] is not a local backend
/// (cloud remotes can't be placeholders — their metadata reads for free) or the
/// path can't be resolved. Synthetic local peers (sidebar Locations / disks)
/// carry an absolute [Remote.fs] root; a named `type=local` conf remote (fs
/// `"name:"`) is only resolvable when the browse path is already absolute.
String? localAbsolutePath(Remote remote, String pathWithinRemote) {
  if (remote.type == 'local') {
    if (remote.isLocal) return _joinLocal(remote.fs, pathWithinRemote);
    return _absoluteOrNull(pathWithinRemote);
  }
  // A wrapper (crypt/alias/...) over a local path. Its backing root is resolved
  // from the config when the remote list loads; absent means unresolved, and
  // there is nothing to check.
  final root = _backingRoots[remote.name];
  if (root == null) return null;
  // An empty root means the chain ends at a bare `name:` local remote, which
  // has no fixed root of its own - so only an already-absolute browse path can
  // be resolved, exactly as for that remote directly.
  if (root.isEmpty) return _absoluteOrNull(pathWithinRemote);
  return _joinLocal(root, pathWithinRemote);
}

/// [p] when it is already an absolute filesystem path, else null.
String? _absoluteOrNull(String p) {
  if (RegExp(r'^[A-Za-z]:').hasMatch(p) || p.startsWith('/')) return p;
  return null;
}

String _joinLocal(String root, String within) {
  if (within.isEmpty) return root;
  final r = root.endsWith('/') ? root : '$root/';
  final w = within.startsWith('/') ? within.substring(1) : within;
  return '$r$w';
}

/// True when reading the entry at [pathWithinRemote] under [remote] would
/// hydrate an online-only cloud placeholder. The guard thumbnail builders and
/// content-hash scans consult before fetching a file's bytes.
bool wouldHydrateOnRead(Remote remote, String pathWithinRemote) {
  final local = localAbsolutePath(remote, pathWithinRemote);
  return local != null && isOnlineOnlyPlaceholder(local);
}
