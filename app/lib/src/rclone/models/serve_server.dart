import 'package:flutter/foundation.dart';

/// Protocols that authenticate with a username/password. DLNA/NFS do not.
const serveAuthCapable = {'http', 'webdav', 'ftp', 'sftp'};

/// A running `rclone serve` instance, as reported by the `serve/list` RC.
///
/// rclone's `serve/list` echoes the start params back as its INTERNAL struct
/// (`params.type`, `params.fs`, `params.opt.ListenAddr`, `params.vfsOpt`), while
/// the actual bound address is the top-level `addr` — so we prefer `addr` and
/// only fall back to `opt.ListenAddr`.
@immutable
class ServeServer {
  const ServeServer({
    required this.id,
    required this.addr,
    required this.type,
    required this.fs,
  });

  final String id;
  final String addr;
  final String type;
  final String fs;

  factory ServeServer.fromList(Map<String, dynamic> m) {
    final params = m['params'];
    final p = params is Map ? params.cast<String, dynamic>() : const {};
    final opt = p['opt'];
    final optMap = opt is Map ? opt.cast<String, dynamic>() : const {};
    final topAddr = m['addr'];
    final addr = (topAddr is String && topAddr.isNotEmpty)
        ? topAddr
        : ((optMap['ListenAddr'] as String?) ?? '');
    return ServeServer(
      id: m['id'] is String ? m['id'] as String : '',
      addr: addr,
      type: p['type'] is String ? p['type'] as String : '',
      fs: p['fs'] is String ? p['fs'] as String : '',
    );
  }

  /// Host portion of [addr] (handles `[::]:port`, `host:port`, bare `:port`).
  String get host {
    final i = addr.lastIndexOf(':');
    return i < 0 ? addr : addr.substring(0, i);
  }

  String get port {
    final i = addr.lastIndexOf(':');
    return i < 0 ? '' : addr.substring(i + 1);
  }

  /// Reachable only from this machine. Anything else — `[::]`, `0.0.0.0`, a bare
  /// `:port` (empty host = all interfaces), or a LAN IP — is treated as exposed.
  bool get isLoopback {
    final h = host;
    return h == '127.0.0.1' ||
        h.startsWith('127.') ||
        h == '::1' ||
        h == '[::1]' ||
        h == 'localhost';
  }

  bool get requiresAuth => !isLoopback && serveAuthCapable.contains(type);

  /// URL scheme for this protocol (webdav rides on http).
  String get scheme => switch (type) {
    'http' || 'webdav' => 'http',
    'ftp' => 'ftp',
    'sftp' => 'sftp',
    _ => type,
  };

  /// A copy-pasteable URL. For an exposed all-interfaces bind (empty host /
  /// `[::]` / `0.0.0.0`), [lanIp] (if resolved by the caller) is substituted so
  /// the URL is actually usable.
  String displayUrl({String? lanIp}) {
    if (type == 'dlna') return 'DLNA on port $port';
    final String h;
    if (isLoopback) {
      h = '127.0.0.1';
    } else if (host.isEmpty ||
        host == '[::]' ||
        host == '::' ||
        host == '0.0.0.0') {
      h = lanIp ?? 'your-device-ip';
    } else {
      h = host;
    }
    return '$scheme://$h:$port';
  }
}
