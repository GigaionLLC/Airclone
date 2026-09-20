import 'dart:convert';

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

/// An engine that can accept raw bytes and write them to a remote.
///
/// A CAPABILITY interface rather than a widening of [RcloneClient]: 24 test
/// fakes `implements RcloneClient` and every one of them would have to grow a
/// method it does not care about.
///
/// Three implementations, which differ entirely in HOW and not at all in what a
/// caller writes — which is the point of a seam:
///
///   * the spawned `rcd` streams the bytes straight through to
///     `operations/uploadfile`, touching no disk;
///   * the in-process library cannot — `RcloneRPC` speaks JSON and nothing else
///     — so it stages to a file and then copies;
///   * [WebRcloneClient] has no engine of its own, so it POSTs to the Web UI
///     server, which then does one of the two above on the host.
///
/// (An earlier version of this comment claimed the web client could not be an
/// uploader "because it is the thing asking". That was wrong: asking the server
/// IS how a browser writes to a remote, and pretending otherwise would have put
/// a second, parallel upload path in the UI layer for no benefit.)
abstract interface class ObjectUploader {
  /// Writes [bytes] to `fs:remote`, replacing whatever is there.
  ///
  /// [length] is the byte count when it is known up front. The streaming
  /// implementation needs it for a Content-Length; the staging one uses it to
  /// check free space before accepting a single byte, which is the difference
  /// between refusing an upload and filling the disk.
  Future<void> putObject(
    String fs,
    String remote,
    Stream<List<int>> bytes, {
    int? length,
  });
}

/// A URL + headers pair for fetching an object's bytes (preview/media).
class ObjectRef {
  const ObjectRef(this.url, this.headers);

  /// A reference to an ARBITRARY network URL, carrying no credentials.
  ///
  /// Used by "open a network stream": the user names a host we know nothing
  /// about, so there is nothing of ours that may be sent to it.
  const ObjectRef.network(this.url) : headers = const {};

  final String url;
  final Map<String, String> headers;

  /// The headers that may actually be sent when fetching [url].
  ///
  /// **This is a credential boundary, not a tidy-up.** [headers] holds the
  /// engine's own authorization — the rcd file server's Basic auth, or the
  /// in-process bridge's bearer token — and both are minted to protect a
  /// loopback port on this machine. They were previously handed to the player
  /// verbatim alongside whatever URL it was given, which was harmless while
  /// every URL came from [RcloneClient.objectRef] and therefore pointed at
  /// 127.0.0.1. The moment a user can type a URL, that same code path would
  /// send the engine's credentials to a stranger's CDN.
  ///
  /// So the rule is enforced here rather than remembered at each call site:
  /// credentials travel to loopback and nowhere else.
  Map<String, String> get sendableHeaders =>
      isLoopbackUrl(url) ? headers : const {};
}

/// Rewrites a loopback object URL to carry its credential IN THE URL, returning
/// null when that is not possible.
///
/// **Why this exists.** [ObjectRef.sendableHeaders] decides whether the engine's
/// credential may be sent, based on the URL it is given. That is correct for one
/// request and insufficient for media: media_kit maps `Media.httpHeaders` onto
/// mpv's `http-header-fields`, which is a GLOBAL, non-origin-scoped property.
/// mpv attaches those headers to every HTTP request it makes for that stream —
/// redirects, and the segments an HLS manifest names. So a manifest stored on
/// the user's own remote (put there by anyone they share that folder with) can
/// list a segment at `http://attacker.example/seg.ts`, and mpv sends the engine's
/// `Authorization` header straight to it. The header boundary never sees that
/// request; it only ever saw the top-level URL.
///
/// Credentials in the URL are scoped by the thing that actually makes the
/// requests: a relative segment resolves against the manifest's URL and inherits
/// the userinfo, while an absolute URL naming another host does not — which is
/// exactly the rule wanted. `scheme://user:pass@host` is also a shape the
/// diagnostics redactor already strips at ingest.
String? loopbackUrlWithCredentials(String url, Map<String, String> headers) {
  if (!isLoopbackUrl(url)) return null;
  final auth = headers['Authorization'] ?? headers['authorization'];
  if (auth == null || !auth.startsWith('Basic ')) return null;
  final decoded = utf8.decode(base64.decode(auth.substring(6)));
  final colon = decoded.indexOf(':');
  if (colon < 0) return null;
  final uri = Uri.parse(url);
  return uri
      .replace(
        userInfo:
            '${Uri.encodeComponent(decoded.substring(0, colon))}'
            ':${Uri.encodeComponent(decoded.substring(colon + 1))}',
      )
      .toString();
}

/// Whether [url] addresses this machine's loopback interface.
///
/// Parse failures answer FALSE: an unparseable URL is not something to send
/// credentials to. IPv6 loopback arrives from [Uri] as `::1` with the brackets
/// already stripped.
bool isLoopbackUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host == '::1') return true;
  // The whole 127.0.0.0/8 block, not just 127.0.0.1.
  return RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
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
