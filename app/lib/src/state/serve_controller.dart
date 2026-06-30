import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/serve_server.dart';
import '../rclone/rclone_client.dart';
import 'engine_controller.dart';
import 'serve_policy.dart';

/// Protocols Airclone offers, intersected with what the engine reports via
/// `serve/types` (so we never offer a type the binary lacks, nor trust a
/// truncated docs example).
const _curatedServeTypes = ['http', 'webdav', 'ftp', 'sftp', 'dlna'];

/// The serve types the running engine supports (curated ∩ `serve/types`).
final serveTypesProvider = FutureProvider<List<String>>((ref) async {
  final client = ref.read(engineControllerProvider).client;
  if (client == null) return const [];
  try {
    final res = await client.rpc('serve/types');
    final types = (res['types'] as List?)?.whereType<String>().toSet() ?? {};
    return [
      for (final t in _curatedServeTypes)
        if (types.contains(t)) t,
    ];
  } catch (_) {
    return const [];
  }
});

/// First non-loopback IPv4, for building a usable URL for a LAN bind. Null when
/// none/offline. Display-only — never used as a bind address.
final lanIpProvider = FutureProvider<String?>((ref) async {
  try {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback) return a.address;
      }
    }
  } catch (_) {}
  return null;
});

/// Drives `rclone serve` instances. `serve/list` is the source of truth (polled
/// every 2s, mirroring [StatsController]); Airclone keeps no authoritative list.
///
/// All security is enforced in [start] itself (not just the UI): the policy
/// kill-switch, loopback-default, mandatory auth for exposed auth-capable
/// protocols, and the DLNA acknowledgement.
class ServeController extends Notifier<List<ServeServer>> {
  Timer? _timer;

  @override
  List<ServeServer> build() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    ref.onDispose(() => _timer?.cancel());
    return const [];
  }

  Future<void> _poll() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      final res = await client.rpc('serve/list');
      final list = res['list'];
      state = list is List
          ? [
              for (final e in list)
                if (e is Map) ServeServer.fromList(e.cast<String, dynamic>()),
            ]
          : const [];
    } catch (_) {
      // Keep the last good snapshot on a transient error.
    }
  }

  /// Starts a server and returns its id + bound address. Security is enforced
  /// here so no caller (UI or otherwise) can bypass it. Throws [RcloneException]
  /// on a policy/validation failure or an engine error.
  Future<({String id, String addr})> start({
    required String type,
    required String fs,
    required bool lan,
    required int port,
    String user = '',
    String pass = '',
    bool readOnly = false,
    String vfsCacheMode = 'off',
    bool dlnaAcknowledged = false,
  }) async {
    if (!ref.read(serveEnabledProvider)) {
      throw RcloneException('serve/start', 'Serving is disabled by policy.');
    }
    final authCapable = serveAuthCapable.contains(type);
    // Loopback binds to 127.0.0.1 (this device only); LAN binds all interfaces.
    final addr = lan ? ':$port' : '127.0.0.1:$port';
    if (lan && authCapable && (user.isEmpty || pass.isEmpty)) {
      throw RcloneException(
        'serve/start',
        'A username and password are required to serve on your network.',
      );
    }
    if (lan && type == 'dlna' && !dlnaAcknowledged) {
      throw RcloneException(
        'serve/start',
        'DLNA has no password — confirm you want it reachable on your network.',
      );
    }
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      throw RcloneException('serve/start', 'Engine not ready.');
    }
    // Whitelisted params only — never the rc creds, _config, or config password.
    final params = <String, dynamic>{
      'type': type,
      'fs': fs,
      'addr': addr,
      if (authCapable && user.isNotEmpty) 'user': user,
      if (authCapable && pass.isNotEmpty) 'pass': pass,
      if (readOnly) 'read_only': true,
      if (vfsCacheMode != 'off') 'vfs_cache_mode': vfsCacheMode,
    };
    final res = await client.rpc('serve/start', params);
    final id = (res['id'] as String?) ?? '';
    final boundAddr = (res['addr'] as String?) ?? addr;
    await _poll();
    return (id: id, addr: boundAddr);
  }

  Future<void> stop(String id) async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      await client.rpc('serve/stop', {'id': id});
    } catch (_) {
      // Server may already be gone — refresh below either way.
    }
    await _poll();
  }

  /// Kill-switch tear-down: stop every running server.
  Future<void> panicStopAll() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      await client.rpc('serve/stopall');
    } catch (_) {}
    await _poll();
  }
}

final serveControllerProvider =
    NotifierProvider<ServeController, List<ServeServer>>(ServeController.new);
