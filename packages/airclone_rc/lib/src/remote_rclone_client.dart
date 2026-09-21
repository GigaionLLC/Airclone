/// Talking to an rclone engine you did not start.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'log_redaction.dart';
import 'rclone_client.dart';
import 'rclone_log.dart';

/// An [RcloneClient] for an rc endpoint that is **already running somewhere
/// else** — another machine, another process, or the host a browser is asking.
///
/// [HttpRcloneClient] owns its engine: it spawns `rclone rcd`, holds the child,
/// and stops it. This one owns nothing. It has no `dart:io` in it, so it
/// compiles and runs everywhere Dart does, **including the web**, which is the
/// case it exists for: a page served by a desktop app cannot spawn a process,
/// but it can ask the thing that served it.
///
/// ```dart
/// final rc = RcApi(RemoteRcloneClient(
///   baseUrl: Uri.parse('http://127.0.0.1:5572/'),
///   authorization: basicAuth('user', 'pass'),
/// ));
/// final files = await rc.operations.list('gdrive:', 'papers');
/// ```
///
/// **rc access is not a read-only API.** rclone's own documentation equates it
/// with shell access as the user running the engine: `core/command` runs
/// commands, `config/*` reads and writes credentials for every remote. Whoever
/// can reach this endpoint with these credentials can do all of that, so
/// plaintext HTTP to anything but loopback is refused — see [allowInsecure].
class RemoteRcloneClient implements RcloneClient {
  RemoteRcloneClient({
    required Uri baseUrl,
    this.authorization,
    this.requestTimeout = const Duration(seconds: 30),
    this.logSink = discardRcloneLog,
    this.allowInsecure = false,
    http.Client? httpClient,
  }) : baseUrl = _checked(baseUrl, allowInsecure),
       _ownsClient = httpClient == null,
       _http = httpClient ?? http.Client();

  /// Where the engine answers, e.g. `http://127.0.0.1:5572/`. A trailing slash
  /// is optional; method names are resolved against it.
  final Uri baseUrl;

  /// The `Authorization` header value to send, or null for an endpoint with
  /// none (`--rc-no-auth`, which is a decision the operator makes, not this
  /// client). Build a Basic value with [basicAuth].
  final String? authorization;

  /// How long one rc call may take. See [HttpRcloneClient.requestTimeout]: it
  /// is a transport timeout, and long work belongs in a job.
  final Duration requestTimeout;

  /// Where transport failures are reported. Credentials are removed first.
  final RcloneLogSink logSink;

  /// Permits plaintext HTTP to a non-loopback host.
  ///
  /// Off by default, and the refusal is deliberate: these credentials are
  /// equivalent to shell access on the engine's machine, and "it is only my
  /// LAN" is how they end up on the wire. Set it when you have decided that
  /// yourself — a tunnel, a trusted link, a test — not to make an error go
  /// away.
  final bool allowInsecure;

  final http.Client _http;

  /// Whether [quit] may close [_http]: a client the caller passed in is the
  /// caller's to close, and closing it would break their next request.
  final bool _ownsClient;

  bool _closed = false;

  static Uri _checked(Uri url, bool allowInsecure) {
    if (!url.hasScheme || (url.scheme != 'http' && url.scheme != 'https')) {
      throw ArgumentError.value(
        url.toString(),
        'baseUrl',
        'must be an http:// or https:// URL',
      );
    }
    final host = url.host;
    final isLoopback =
        host == 'localhost' ||
        host == '::1' ||
        host == '[::1]' ||
        host.startsWith('127.');
    if (url.scheme == 'http' && !isLoopback && !allowInsecure) {
      throw ArgumentError.value(
        url.toString(),
        'baseUrl',
        'plaintext HTTP to a non-loopback host would put rc credentials — '
            'which are equivalent to shell access on that machine — on the '
            'wire. Use https, or pass allowInsecure: true if you have decided '
            'that yourself',
      );
    }
    return url;
  }

  Uri _uri(String method) => baseUrl.resolve(method);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': ?authorization,
  };

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (_closed) {
      throw RcloneException(method, 'this client has been closed');
    }
    http.Response res;
    try {
      res = await _http
          .post(
            _uri(method),
            headers: _headers,
            body: jsonEncode(params ?? const {}),
          )
          .timeout(requestTimeout);
    } on Object catch (e) {
      final detail = redactEngineLine('$e', sessionSecrets: [?authorization]);
      logSink(
        RcloneLogLevel.warning,
        'engine',
        'no answer from the remote engine for $method',
        detail: detail,
      );
      throw RcloneException(method, 'transport error: $detail');
    }
    final body = res.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode ~/ 100 != 2) {
      final msg = (body['error'] ?? res.reasonPhrase ?? 'unknown error')
          .toString();
      throw RcloneException(method, msg, statusCode: res.statusCode);
    }
    return body;
  }

  /// Confirms the engine is reachable. It does NOT start anything: there is
  /// nothing here to start, and pretending otherwise would let a caller
  /// believe it had an engine because a method returned.
  @override
  Future<void> start() async {
    final st = await status();
    if (st.state != EngineState.running) {
      throw RcloneException(
        'start',
        'no engine answered at $baseUrl${st.message == null ? '' : ': ${st.message}'}',
      );
    }
  }

  /// Stops using the engine; **never stops the engine.** It is someone else's
  /// process, possibly serving other callers, and `core/quit` would take it
  /// away from them. This releases the local HTTP client and nothing more.
  @override
  Future<void> quit() async {
    _closed = true;
    if (_ownsClient) _http.close();
  }

  /// Unsupported, and deliberately loud: restarting an engine means owning its
  /// process. Ask whoever does.
  @override
  Future<void> restart() async => throw UnsupportedError(
    'RemoteRcloneClient does not own the engine, so it cannot restart it. '
    'Use HttpRcloneClient (which spawns rclone rcd) or ask the host that did.',
  );

  @override
  Future<EngineStatus> status() async {
    if (_closed) return EngineStatus.stopped;
    try {
      final res = await rpc('core/version');
      return EngineStatus(
        EngineState.running,
        version: res['version'] as String?,
      );
    } catch (e) {
      return EngineStatus(EngineState.error, message: '$e');
    }
  }

  /// An object's bytes, served by the engine's own `--rc-serve` route.
  ///
  /// Only an engine started with `--rc-serve` answers this, which is the
  /// operator's choice and not something this client can arrange.
  @override
  ObjectRef objectRef(String fs, String remote) {
    final encoded = remote.split('/').map(Uri.encodeComponent).join('/');
    // Concatenated, NOT Uri.resolve: every remote name ends in a colon, so
    // `resolve('[gdrive:]/...')` reads `[gdrive:` as a URL scheme and throws.
    final root = baseUrl.toString();
    final join = root.endsWith('/') ? '' : '/';
    return ObjectRef('$root$join[$fs]/$encoded', {
      'Authorization': ?authorization,
    });
  }
}

/// The `Authorization` value for rclone's `--rc-user` / `--rc-pass`.
///
/// It is base64, not encryption: anyone who sees the header has the password,
/// which is why [RemoteRcloneClient] refuses plaintext HTTP off loopback.
String basicAuth(String user, String pass) =>
    'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
