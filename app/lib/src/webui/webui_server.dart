/// The Airclone Web UI server.
///
/// Serves the Flutter web build of *this same app* and gives it a way to drive
/// the rclone engine running on **this** machine. The browser renders; the host
/// does the work. A mount created through the Web UI appears on the host, a
/// listing is read by the host's engine, a copy is performed by the host's
/// rclone. Nothing the user asks for happens in the browser.
///
/// Shape of the surface:
///
/// | Route | Auth | What it is |
/// | :-- | :-- | :-- |
/// | `GET /login` | none | the sign-in page, ~4 KB, server-rendered |
/// | `POST /api/login` | none | trades the password for a session cookie |
/// | `POST /api/logout` | session | ends the session |
/// | `GET /api/whoami` | session | cheap "am I still signed in" probe |
/// | `POST /api/rc` | session | allowlisted rclone RC, forwarded to the engine |
/// | `GET /api/object` | session | object bytes for previews, with Range |
/// | everything else | session | the Flutter web bundle |
///
/// The bundle itself is behind the session on purpose — see
/// `webui_login_page.dart` for why.
library;

import '../state/cloud_placeholder.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../rclone/rclone_client.dart';
import 'webui_assets.dart';
import 'webui_credentials.dart';
import 'webui_login_page.dart';
import 'webui_options.dart';
import 'webui_protocol.dart';
import 'webui_rc_policy.dart';
import 'webui_sessions.dart';

/// Severity for [WebUiLogSink].
enum WebUiLogLevel { info, warning, error }

/// Where the server's log lines go.
///
/// Injected rather than reaching for the diagnostics provider directly, because
/// this server runs in two very different places: inside the desktop app, where
/// lines belong in the in-app diagnostics log, and under `--webui` on a headless
/// box, where they belong on stdout. Neither should be compiled into the other.
typedef WebUiLogSink =
    void Function(WebUiLogLevel level, String message, {Object? detail});

/// A running Web UI server.
class WebUiServer {
  WebUiServer({
    required this.options,
    required this.credentials,
    required this.engineClient,
    required this.log,
    this.bundle,
    WebUiSessions? sessions,
    LoginThrottle? throttle,
  }) : _sessions = sessions ?? WebUiSessions(),
       _throttle = throttle ?? LoginThrottle();

  final WebUiOptions options;

  /// Resolved at start and replaced on rotation.
  WebUiCredentials credentials;

  /// Looked up per request rather than captured: the desktop app can restart
  /// its engine underneath us, and a stale client would 500 every call.
  final RcloneClient Function() engineClient;

  final WebUiLogSink log;

  /// Null when this build did not ship the compiled web interface.
  final Directory? bundle;
  final WebUiSessions _sessions;
  final LoginThrottle _throttle;

  HttpServer? _server;
  HttpClient? _upstream;
  final Random _nonceRandom = Random.secure();

  bool get isRunning => _server != null;

  /// The address actually bound, once running.
  String? get boundAddress => _server?.address.address;

  int? get boundPort => _server?.port;

  /// Binds the socket and starts serving. Throws [SocketException] if the
  /// address or port is unavailable — callers surface that rather than
  /// retrying somewhere else, since "somewhere else" is not what was asked for.
  Future<void> start() async {
    if (_server != null) return;
    // Fail loudly at startup rather than on the first denied call.
    debugAssertRcPolicyConsistent();

    final server = await HttpServer.bind(
      options.bindAddress,
      options.port,
      shared: false,
    );
    server.autoCompress = true;
    _server = server;
    _upstream = HttpClient();

    log(
      WebUiLogLevel.info,
      'Web UI listening on http://${options.bindAddress}:${server.port}/',
    );
    if (!options.isLoopback) {
      log(
        WebUiLogLevel.warning,
        options.isAllInterfaces
            ? 'The Web UI is reachable from every network this machine is on. '
                  'It is protected only by the generated password, and the '
                  'connection is plain HTTP — put it behind a reverse proxy '
                  'with TLS if it crosses a network you do not control.'
            : 'The Web UI is bound to ${options.bindAddress}, which is not '
                  'loopback, so it is reachable from the network over plain '
                  'HTTP.',
      );
    }
    if (bundle == null) {
      log(
        WebUiLogLevel.error,
        'The Web UI interface files are missing from this build, so only the '
        'sign-in page will load. Build them with `flutter build web` and '
        'place the output in a "webui" folder beside the Airclone executable, '
        'or point $kWebUiRootEnv at it.',
      );
    }

    unawaited(_serve(server));
  }

  /// Stops serving and drops every session.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _sessions.revokeAll();
    _upstream?.close(force: true);
    _upstream = null;
    if (server != null) {
      await server.close(force: true);
      log(WebUiLogLevel.info, 'Web UI stopped.');
    }
  }

  /// Replaces the credentials and signs every session out.
  ///
  /// Both halves matter: a session minted under the old password must not
  /// outlive it, or "rotate the password" would not actually lock anyone out.
  void rotateCredentials(WebUiCredentials next) {
    credentials = next;
    _sessions.revokeAll();
    log(
      WebUiLogLevel.info,
      'Web UI credentials replaced; all sessions signed out.',
    );
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      // One bad request must never take the server down.
      unawaited(
        _handle(request).catchError((Object e, StackTrace s) {
          log(
            WebUiLogLevel.error,
            'Web UI request failed: ${request.method} ${request.uri.path}',
            detail: e,
          );
          _tryClose(request, HttpStatus.internalServerError);
        }),
      );
    }
  }

  void _tryClose(HttpRequest request, int status) {
    try {
      request.response.statusCode = status;
      request.response.close();
    } on StateError {
      // Response already started or closed; nothing left to say.
    }
  }

  Future<void> _handle(HttpRequest request) async {
    _applySecurityHeaders(request.response);
    final path = request.uri.path;

    if (path == kLoginApiPath) return _handleLogin(request);
    if (path == kLoginPath) return _handleLoginPage(request);

    final token = _sessionCookie(request);
    final authed = _sessions.validate(token);

    if (path.startsWith('/api/')) {
      if (!authed) {
        return _json(request, HttpStatus.unauthorized, {
          'error': 'Not signed in.',
        });
      }
      switch (path) {
        case kWhoamiPath:
          return _json(request, HttpStatus.ok, {
            'username': credentials.username,
          });
        case kLogoutPath:
          if (!_requireCsrf(request)) return;
          _sessions.revoke(token);
          _clearSessionCookie(request.response);
          return _json(request, HttpStatus.ok, {'ok': true});
        case kRcPath:
          if (!_requireCsrf(request)) return;
          return _handleRc(request);
        case kObjectPath:
          return _handleObject(request);
      }
      return _json(request, HttpStatus.notFound, {
        'error': 'No such endpoint.',
      });
    }

    if (!authed) {
      // Send browsers to the sign-in page rather than a bare 401 body.
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, kLoginPath);
      return request.response.close();
    }
    return _handleStatic(request);
  }

  // ── Security headers ──────────────────────────────────────────────────────

  /// [scriptNonce] is set only for the sign-in page, which is the one response
  /// carrying an inline script. `script-src 'self'` does not cover inline
  /// script, so without the nonce the browser drops it silently and the form
  /// degrades to a native POST that the CSRF check then refuses.
  void _applySecurityHeaders(HttpResponse response, {String? scriptNonce}) {
    final h = response.headers;
    h.set('X-Content-Type-Options', 'nosniff');
    // The Web UI has no reason to be framed, and being framed is how
    // clickjacking turns a signed-in operator into a delete button.
    h.set('X-Frame-Options', 'DENY');
    h.set('Referrer-Policy', 'no-referrer');
    // 'wasm-unsafe-eval' is required: CanvasKit is a WebAssembly module and
    // compiling one counts as eval under CSP. It permits WebAssembly
    // compilation only, NOT JavaScript eval().
    final scriptSrc = StringBuffer("script-src 'self' 'wasm-unsafe-eval'");
    if (scriptNonce != null) {
      scriptSrc.write(" 'nonce-$scriptNonce'");
    }
    h.set(
      'Content-Security-Policy',
      "default-src 'self'; "
          '$scriptSrc; '
          "style-src 'self' 'unsafe-inline'; "
          "img-src 'self' data: blob:; "
          "media-src 'self' blob:; "
          "font-src 'self' data:; "
          "connect-src 'self'; "
          "worker-src 'self' blob:; "
          "object-src 'none'; base-uri 'self'; frame-ancestors 'none'",
    );
  }

  /// Whether the request carries the anti-CSRF header. Answers the client when
  /// it does not, so callers can simply return.
  bool _requireCsrf(HttpRequest request) {
    final value = request.headers.value(kWebUiCsrfHeader);
    if (value != null && value.isNotEmpty) return true;
    _json(request, HttpStatus.forbidden, {
      'error': 'Missing the $kWebUiCsrfHeader header.',
    });
    return false;
  }

  String? _sessionCookie(HttpRequest request) {
    for (final c in request.cookies) {
      if (c.name == kSessionCookieName) return c.value;
    }
    return null;
  }

  void _setSessionCookie(HttpRequest request, String token) {
    final cookie = Cookie(kSessionCookieName, token)
      ..httpOnly = true
      ..path = '/'
      // Strict, not Lax: there is no cross-site flow into the Web UI that
      // anyone should be able to start.
      ..sameSite = SameSite.strict
      // Only when TLS actually terminated in front of us. Setting Secure on a
      // plain-HTTP connection makes the browser discard the cookie, which
      // presents as "the password is wrong" forever.
      ..secure =
          request.headers.value('x-forwarded-proto')?.toLowerCase() == 'https';
    request.response.cookies.add(cookie);
  }

  void _clearSessionCookie(HttpResponse response) {
    response.cookies.add(
      Cookie(kSessionCookieName, '')
        ..httpOnly = true
        ..path = '/'
        ..maxAge = 0,
    );
  }

  /// A stable key for throttling. `HttpConnectionInfo` is null only for an
  /// already-closed connection, where a shared bucket is fine.
  String _peerKey(HttpRequest request) =>
      request.connectionInfo?.remoteAddress.address ?? 'unknown';

  // ── Routes ────────────────────────────────────────────────────────────────

  Future<void> _handleLoginPage(HttpRequest request) async {
    if (_sessions.validate(_sessionCookie(request))) {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, '/');
      return request.response.close();
    }
    // Fresh per response: a nonce reused across responses is no better than
    // 'unsafe-inline', since an injected script could simply carry it.
    final nonce = _newNonce();
    _applySecurityHeaders(request.response, scriptNonce: nonce);
    return _html(request, HttpStatus.ok, renderLoginPage(nonce: nonce));
  }

  String _newNonce() {
    final bytes = List<int>.generate(16, (_) => _nonceRandom.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> _handleLogin(HttpRequest request) async {
    if (request.method != 'POST') {
      return _json(request, HttpStatus.methodNotAllowed, {
        'error': 'POST required.',
      });
    }
    if (!_requireCsrf(request)) return;

    final peer = _peerKey(request);
    final wait = _throttle.retryAfter(peer);
    if (wait != null) {
      final seconds = wait.inSeconds + 1;
      log(
        WebUiLogLevel.warning,
        'Web UI sign-in throttled for $peer ($seconds s remaining).',
      );
      request.response.headers.set('Retry-After', '$seconds');
      return _json(request, HttpStatus.tooManyRequests, {
        'error': 'Too many sign-in attempts. Try again in $seconds seconds.',
      });
    }

    final body = await _readBody(request, kMaxRcBodyBytes);
    if (body == null) {
      return _json(request, HttpStatus.badRequest, {'error': 'Bad request.'});
    }
    Map<String, dynamic> parsed;
    try {
      parsed = (jsonDecode(body) as Map).cast<String, dynamic>();
    } on FormatException {
      return _json(request, HttpStatus.badRequest, {'error': 'Bad request.'});
    } on TypeError {
      return _json(request, HttpStatus.badRequest, {'error': 'Bad request.'});
    }

    final user = (parsed['username'] as String?) ?? '';
    final pass = (parsed['password'] as String?) ?? '';
    // Both checks run every time and neither short-circuits, so a wrong
    // username costs exactly as long as a wrong password.
    final userOk = verifyPassword(credentials.username, user);
    final passOk = verifyPassword(credentials.password, pass);

    if (!(userOk && passOk)) {
      _throttle.recordFailure(peer);
      _throttle.sweep();
      // The peer address is evidence; the attempted credentials are not ours to
      // keep and must never reach a log an operator might paste into an issue.
      log(WebUiLogLevel.warning, 'Web UI sign-in failed from $peer.');
      return _json(request, HttpStatus.unauthorized, {
        'error': 'That username and password did not match.',
      });
    }

    _throttle.recordSuccess(peer);
    final token = _sessions.issue();
    _setSessionCookie(request, token);
    log(WebUiLogLevel.info, 'Web UI sign-in from $peer.');
    return _json(request, HttpStatus.ok, {'ok': true});
  }

  Future<void> _handleRc(HttpRequest request) async {
    if (request.method != 'POST') {
      return _json(request, HttpStatus.methodNotAllowed, {
        'error': 'POST required.',
      });
    }
    final body = await _readBody(request, kMaxRcBodyBytes);
    if (body == null) {
      return _json(request, HttpStatus.badRequest, {
        'error': 'Request body was missing or too large.',
      });
    }
    Map<String, dynamic> payload;
    try {
      payload = (jsonDecode(body) as Map).cast<String, dynamic>();
    } on FormatException {
      return _json(request, HttpStatus.badRequest, {'error': 'Bad JSON.'});
    } on TypeError {
      return _json(request, HttpStatus.badRequest, {'error': 'Bad JSON.'});
    }

    final method = (payload['method'] as String?) ?? '';
    final params =
        (payload['params'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final decision = rcPolicyFor(method);
    if (!decision.allowed) {
      // The signal that matters most in this log. A refusal here is either a
      // bug in the client or somebody probing, and both are worth seeing.
      log(
        WebUiLogLevel.warning,
        'Web UI refused rclone method "$method" from ${_peerKey(request)}.',
      );
      return _json(request, HttpStatus.forbidden, {
        'error': decision.reason,
        'method': method,
      });
    }

    // Allowed, but a genuine escalation in capability — it republishes the
    // host's files on a port of its own. Worth a line even on the happy path.
    if (method == 'serve/start') {
      log(
        WebUiLogLevel.warning,
        'Web UI started an rclone serve endpoint on this host.',
        detail: params,
      );
    }

    try {
      final result = await engineClient().rpc(method, params);
      return await _json(request, HttpStatus.ok, result);
    } on RcloneException catch (e) {
      // rclone said no. That is frequently NORMAL (a backend without `about`,
      // a missing path) and the client maps it onto its own error handling, so
      // it is relayed rather than logged as a server fault.
      return _json(request, e.statusCode ?? HttpStatus.badGateway, {
        'error': e.message,
        'method': method,
      });
    }
  }

  /// Streams an object's bytes from the engine to the browser.
  ///
  /// Previews, thumbnails, audio and video all come through here. `Range` is
  /// forwarded both ways, which is what makes seeking in a video work rather
  /// than downloading the whole file first.
  Future<void> _handleObject(HttpRequest request) async {
    final fs = request.uri.queryParameters['fs'];
    final remote = request.uri.queryParameters['remote'];
    if (fs == null || remote == null) {
      return _json(request, HttpStatus.badRequest, {
        'error': 'fs and remote are required.',
      });
    }

    // A download is a CONTENT read, and this repo's standing rule is that every
    // new content-read path consults the placeholder guard. Serving an
    // online-only OneDrive/iCloud file would silently pull the whole thing down
    // — the user's bandwidth, and on a metered plan their money — for a click
    // that looked like it was moving a file they already had.
    //
    // Preview (no `download=1`) is deliberately left alone for now: it is
    // shipped behaviour, and changing what previews are allowed to open is a
    // separate decision from what a Save button may fetch.
    if (request.uri.queryParameters['download'] == '1' &&
        wouldHydrateOnReadFs(fs, remote)) {
      return _json(request, HttpStatus.conflict, {
        'error':
            'That file is stored online-only on this device. Download it in '
            'the Airclone app first, or make it available offline.',
      });
    }

    final ref = engineClient().objectRef(fs, remote);
    final upstream = _upstream;
    if (upstream == null) {
      return _json(request, HttpStatus.serviceUnavailable, {
        'error': 'The Web UI server is shutting down.',
      });
    }

    HttpClientResponse upstreamResponse;
    try {
      final req = await upstream.getUrl(Uri.parse(ref.url));
      ref.headers.forEach(req.headers.set);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      upstreamResponse = await req.close();
    } on SocketException catch (e) {
      log(
        WebUiLogLevel.error,
        'Web UI could not reach the engine for object bytes.',
        detail: e,
      );
      return _json(request, HttpStatus.badGateway, {
        'error': 'The rclone engine is not reachable.',
      });
    }

    final response = request.response;
    response.statusCode = upstreamResponse.statusCode;
    for (final header in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.lastModifiedHeader,
      HttpHeaders.etagHeader,
    ]) {
      final value = upstreamResponse.headers.value(header);
      if (value != null) response.headers.set(header, value);
    }
    // `?download=1` turns a preview into a save. Everything else about the
    // request is identical — same proxy, same Range support — so this is a
    // header, not a second code path.
    if (request.uri.queryParameters['download'] == '1') {
      response.headers.set(
        'Content-Disposition',
        contentDispositionAttachment(remote),
      );
    }
    // Already-compressed media gains nothing from a second pass, and
    // re-compressing invalidates the Content-Length we just copied.
    response.headers.chunkedTransferEncoding = false;
    try {
      await upstreamResponse.pipe(response);
    } on HttpException {
      // The browser hung up mid-stream — routine when seeking a video.
    }
  }

  Future<void> _handleStatic(HttpRequest request) async {
    final root = bundle;
    if (root == null) {
      return _html(
        request,
        HttpStatus.serviceUnavailable,
        _missingBundlePage(),
      );
    }
    var file = resolveStaticFile(root, request.uri.path);
    // Single-page app: an unknown path that is not a file request is the
    // router's business, so hand back the shell and let it decide.
    file ??= request.uri.path.contains('.')
        ? null
        : resolveStaticFile(root, '/index.html');
    if (file == null) {
      return _html(request, HttpStatus.notFound, '<h1>404</h1>');
    }

    final response = request.response;
    response.headers.contentType = ContentType.parse(contentTypeFor(file.path));
    // The bundle is versioned by the build, not by URL, so a stale cached
    // main.dart.js after an upgrade would be a very confusing bug. Let the
    // browser revalidate instead.
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    try {
      await response.addStream(file.openRead());
    } on FileSystemException catch (e) {
      log(
        WebUiLogLevel.error,
        'Web UI could not read a bundle file.',
        detail: e,
      );
    }
    return response.close();
  }

  String _missingBundlePage() =>
      '<!doctype html><meta charset="utf-8">'
      '<title>Airclone Web UI</title>'
      '<body style="font:15px system-ui;max-width:40em;margin:3em auto;'
      'color:#e6e8ec;background:#14161a">'
      '<h1>The Web UI files are missing</h1>'
      '<p>You are signed in, but this build of Airclone does not carry the '
      'compiled web interface, so there is nothing to show.</p>'
      '<p>Build it with <code>flutter build web</code> and put the contents of '
      '<code>build/web</code> into a folder named <code>webui</code> beside the '
      'Airclone executable, or point the <code>$kWebUiRootEnv</code> '
      'environment variable at it.</p></body>';

  // ── Small helpers ─────────────────────────────────────────────────────────

  /// Reads the body as a string, or null when it exceeds [limit].
  ///
  /// Two guards, because they fail differently. `Content-Length` is checked
  /// first, so a declared oversized body is refused without buffering a byte.
  /// A chunked body declares no length, so those bytes are counted as they
  /// arrive and dropped once over the cap.
  ///
  /// Either way the request is **drained** before answering. Abandoning a
  /// half-read request makes the server reset the connection, and the client
  /// then reports "connection closed before full header was received" instead
  /// of the 400 that explains what it did wrong.
  Future<String?> _readBody(HttpRequest request, int limit) async {
    if (request.headers.contentLength > limit) {
      await request.drain<void>();
      return null;
    }
    final chunks = <int>[];
    var over = false;
    await for (final chunk in request) {
      if (over) continue; // keep draining, keep nothing
      chunks.addAll(chunk);
      if (chunks.length > limit) {
        over = true;
        chunks.clear(); // release it now rather than at the end of the request
      }
    }
    if (over) return null;
    try {
      return utf8.decode(chunks);
    } on FormatException {
      return null;
    }
  }

  Future<void> _json(HttpRequest request, int status, Object body) {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    return response.close();
  }

  Future<void> _html(HttpRequest request, int status, String body) {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.html;
    response.write(body);
    return response.close();
  }
}

/// A `Content-Disposition` value that makes a browser SAVE the response, under
/// the file's own name.
///
/// The filename is never interpolated raw. A name may contain a quote, a
/// newline, a semicolon or non-ASCII characters, and a header is a line-oriented
/// protocol: `attachment; filename="a";drop.txt` or a name carrying CRLF would
/// let a remote's file name rewrite the response headers. So two forms are
/// emitted, which is what RFC 6266 asks for:
///
///   * `filename=` with a conservative ASCII fallback, for old clients;
///   * `filename*=UTF-8''…` percent-encoded, which every current browser prefers
///     and which is the one that keeps the real name.
String contentDispositionAttachment(String remotePath) {
  final base =
      remotePath.split('/').where((p) => p.isNotEmpty).lastOrNull ?? '';
  final name = base.isEmpty ? 'download' : base;
  // The ASCII fallback keeps only characters that are safe unquoted, so there is
  // nothing left that could close the quote or break the line.
  final ascii = name
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final safeAscii = ascii.isEmpty ? 'download' : ascii;
  final encoded = Uri.encodeComponent(name);
  return "attachment; filename=\"$safeAscii\"; filename*=UTF-8''$encoded";
}
