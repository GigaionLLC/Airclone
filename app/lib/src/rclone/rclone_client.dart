/// The ONE seam between Airclone and the rclone engine.
///
/// `method` is an rclone RC method string (e.g. `"operations/list"`, `"config/listremotes"`).
/// Params and results are the identical JSON shapes whether driven over HTTP (desktop,
/// spawned `rclone rcd`) or in-process (mobile, `librclone`). Everything above this
/// interface is transport-agnostic. See `wiki/core/08-core-architecture.md`.
abstract interface class RcloneClient {
  /// Core RPC. Throws [RcloneException] on a non-2xx / error response.
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic> params,
  ]);

  /// Bring the engine up (desktop: spawn `rcd` and await `core/version`).
  Future<void> start();

  /// Tear the engine down (desktop: `core/quit` then kill the process).
  Future<void> quit();

  /// First-class restart — rclone has no `core/restart` (quit + respawn).
  Future<void> restart();

  /// Current engine state + version, without throwing.
  Future<EngineStatus> status();

  /// An authenticated reference (URL + headers) to fetch an object's raw bytes,
  /// for image/media/text previews. On desktop this points at the rcd
  /// `--rc-serve` file server.
  ObjectRef objectRef(String fs, String remote);
}

/// A URL + headers pair for fetching an object's bytes (preview/media).
class ObjectRef {
  const ObjectRef(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
}

enum EngineState { stopped, starting, running, error }

/// Snapshot of the engine's lifecycle state.
class EngineStatus {
  const EngineStatus(this.state, {this.version, this.message});

  final EngineState state;
  final String? version;

  /// Human-readable detail (error text, pause reason).
  final String? message;

  bool get isRunning => state == EngineState.running;

  static const stopped = EngineStatus(EngineState.stopped);
}

/// Thrown when an RC call fails (transport error or rclone-reported error).
class RcloneException implements Exception {
  RcloneException(this.method, this.message, {this.statusCode});

  final String method;
  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'RcloneException($method${statusCode != null ? ' [$statusCode]' : ''}): $message';
}
