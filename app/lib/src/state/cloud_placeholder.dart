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

/// Resolves a browse entry ([pathWithinRemote] = the RC `remote` param) to an
/// absolute local filesystem path, or null when [remote] is not a local backend
/// (cloud remotes can't be placeholders — their metadata reads for free) or the
/// path can't be resolved. Synthetic local peers (sidebar Locations / disks)
/// carry an absolute [Remote.fs] root; a named `type=local` conf remote (fs
/// `"name:"`) is only resolvable when the browse path is already absolute.
String? localAbsolutePath(Remote remote, String pathWithinRemote) {
  if (remote.type != 'local') return null;
  if (remote.isLocal) return _joinLocal(remote.fs, pathWithinRemote);
  final p = pathWithinRemote;
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
