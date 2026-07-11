import 'dart:convert';

import 'librclone_ffi.dart';
import 'librclone_object_server.dart';
import 'rclone_client.dart';

/// In-process [RcloneClient]: drives rclone via `librclone` over `dart:ffi`
/// instead of spawning `rcd`. The engine runs INSIDE the app process, so there is
/// no subprocess, no loopback HTTP, and no port — `rpc` maps straight onto
/// librclone's `RcloneRPC`. This is the only legal way to run rclone on iOS / the
/// Mac App Store (no `fork`/`exec`), and a tidier option on desktop.
/// See dev/plans/dual-engine-plan.md and [LibrcloneEngine].
class FfiRcloneClient implements RcloneClient {
  FfiRcloneClient({
    required this.libraryPath,
    this.configPath,
    this.configPassword,
    this.previewCacheDir,
  });

  /// Absolute path to the bundled librclone shared library
  /// (`librclone.dll`/`.dylib`/`.so`) — resolve with [defaultLibrclonePath].
  final String libraryPath;

  /// Optional explicit config-file path, applied via the `config/setpath` RC
  /// method after Initialize. Null lets rclone use its default location.
  final String? configPath;

  /// Config-encryption password (set on the process env before Initialize, then
  /// cleared). Null for unencrypted configs.
  final String? configPassword;

  /// Writable dir for the preview byte bridge ([LibrcloneObjectServer]). When
  /// null, [objectRef] throws — previews are unavailable but browse/transfer
  /// still work. The caller resolves it (e.g. path_provider's temp dir).
  final String? previewCacheDir;

  final LibrcloneEngine _engine = LibrcloneEngine();
  LibrcloneObjectServer? _objectServer;
  String? _version;
  bool _started = false;

  /// Present for interface parity with [RcloneClient] consumers that assign it
  /// (e.g. the engine controller). The in-process engine cannot "die" out from
  /// under the app the way a subprocess can, so this never fires.
  void Function()? onDied;

  @override
  Future<void> start() async {
    if (_started) return;
    await _engine.start(
      libPath: libraryPath,
      configPath: configPath,
      configPass: configPassword,
    );
    _started = true;
    // Prove the engine answers RC before we report ready (mirrors the HTTP
    // client awaiting core/version), and cache the version for status().
    final res = await rpc('core/version');
    _version = res['version'] as String?;
    // Bring up the preview byte bridge (the in-process engine has no file
    // server of its own). Best-effort: a bridge failure must not sink the
    // engine — browse/transfer keep working, only previews go dark.
    final cacheDir = previewCacheDir;
    if (cacheDir != null && cacheDir.isNotEmpty) {
      try {
        final server = LibrcloneObjectServer(rpc: rpc, cacheDir: cacheDir);
        await server.start();
        _objectServer = server;
      } catch (_) {
        _objectServer = null;
      }
    }
  }

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final int status;
    final String output;
    try {
      final r = await _engine.rpc(method, jsonEncode(params ?? const {}));
      status = r.$1;
      output = r.$2;
    } on Object catch (e) {
      throw RcloneException(method, 'ffi error: $e');
    }
    return mapRpcResult(method, status, output);
  }

  @override
  Future<void> quit() async {
    _started = false;
    _version = null;
    final server = _objectServer;
    _objectServer = null;
    await server?.stop();
    await _engine.stop();
  }

  @override
  Future<void> restart() async {
    await quit();
    await start();
  }

  @override
  Future<EngineStatus> status() async {
    if (!_started) return EngineStatus.stopped;
    try {
      final res = await rpc('core/version');
      return EngineStatus(
        EngineState.running,
        version: res['version'] as String?,
      );
    } catch (e) {
      return EngineStatus(EngineState.error, version: _version, message: '$e');
    }
  }

  @override
  ObjectRef objectRef(String fs, String remote) {
    // The in-process engine has no file server; the loopback bridge serves
    // object bytes (see LibrcloneObjectServer). It exists only when a preview
    // cache dir was provided AND start() brought the bridge up.
    final server = _objectServer;
    if (server == null || !server.isRunning) {
      throw UnsupportedError(
        'Previews are unavailable in library mode (no preview cache configured).',
      );
    }
    return server.objectRef(fs, remote);
  }
}

/// Maps a librclone `(httpStatus, jsonOutput)` pair to the same result/exception
/// shape as the HTTP client: a decoded JSON map on 2xx, else an [RcloneException]
/// carrying rclone's `error` field. Pure — unit-tested without any native lib.
Map<String, dynamic> mapRpcResult(String method, int status, String output) {
  final body = output.trim().isEmpty
      ? const <String, dynamic>{}
      : jsonDecode(output) as Map<String, dynamic>;
  if (status ~/ 100 != 2) {
    final msg = (body['error'] ?? 'HTTP $status').toString();
    throw RcloneException(method, msg, statusCode: status);
  }
  return body;
}
