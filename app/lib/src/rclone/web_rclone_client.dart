/// The [RcloneClient] used by the Web UI build.
///
/// The third implementation of the one seam, and the simplest — because it owns
/// no engine at all. The desktop client spawns `rcd`; the mobile client loads
/// `librclone` in-process; this one talks to the Airclone that served the page
/// and lets *it* do everything. Every method below is therefore either a thin
/// POST or an honest no-op.
///
/// That asymmetry is the point of the whole feature. `mount/mount` sent from
/// here mounts a drive on the host. `operations/list` reads the host's
/// filesystem. The browser contributes a viewport and a pair of hands.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../webui/webui_protocol.dart';
import 'rclone_client.dart';

/// Thrown when the server says the session is gone. Surfaced distinctly from a
/// normal [RcloneException] so the app can send the operator back to sign in
/// rather than showing them an rclone error they cannot act on.
class WebUiSessionExpired implements Exception {
  const WebUiSessionExpired();

  @override
  String toString() => 'WebUiSessionExpired';
}

/// Drives the rclone engine on the host, through the Web UI server.
class WebRcloneClient implements RcloneClient, ObjectUploader {
  WebRcloneClient({http.Client? httpClient, Uri? base})
    : _http = httpClient ?? http.Client(),
      _base = base ?? Uri.base;

  final http.Client _http;
  final Uri _base;

  String? _version;

  /// Sends the operator to the sign-in page. Same tab: this is not a popup,
  /// it is the session ending.
  Future<void> _toLogin() async {
    await launchUrl(_base.resolve(kLoginPath), webOnlyWindowName: '_self');
  }

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    final body = jsonEncode({'method': method, 'params': params});
    if (body.length > kMaxRcBodyBytes) {
      throw RcloneException(method, 'Request is too large to send.');
    }

    http.Response response;
    try {
      response = await _http.post(
        _base.resolve(kRcPath),
        headers: const {
          'Content-Type': 'application/json',
          kWebUiCsrfHeader: '1',
        },
        body: body,
      );
    } on http.ClientException catch (e) {
      throw RcloneException(method, 'Could not reach Airclone: ${e.message}');
    }

    if (response.statusCode == 401) {
      // Do not await: the navigation tears this page down, and awaiting it
      // would leave the caller hanging on a future that never completes.
      _toLogin();
      throw const WebUiSessionExpired();
    }

    Map<String, dynamic> decoded;
    try {
      decoded = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } on FormatException {
      throw RcloneException(
        method,
        'Airclone returned a response that was not JSON '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw RcloneException(
      method,
      (decoded['error'] as String?) ?? 'HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  /// Confirms the session is live and caches the engine version.
  ///
  /// There is nothing to launch — the engine was already running before this
  /// page was served — so "start" here means "prove we can reach it".
  @override
  Future<void> start() async {
    final res = await rpc('core/version');
    _version = res['version'] as String?;
  }

  /// No-op. The engine belongs to the host, and a browser tab closing must not
  /// stop it — other sessions, the desktop window and any scheduled task are
  /// all still using it. `core/quit` is refused by the server for the same
  /// reason (see `webui_rc_policy.dart`).
  @override
  Future<void> quit() async {}

  /// No-op, for the same reason as [quit]. Restarting the engine is done from
  /// the host, where someone can see what it breaks.
  @override
  Future<void> restart() async {}

  @override
  Future<EngineStatus> status() async {
    try {
      final res = await rpc('core/version');
      _version = res['version'] as String? ?? _version;
      return EngineStatus(EngineState.running, version: _version);
    } on WebUiSessionExpired {
      return const EngineStatus(
        EngineState.error,
        message: 'Signed out. Sign in again to continue.',
      );
    } on RcloneException catch (e) {
      return EngineStatus(EngineState.error, message: e.message);
    }
  }

  /// The same-origin URL that makes the browser SAVE an object rather than
  /// display it. `download=1` is what adds `Content-Disposition: attachment` on
  /// the server; everything else about the request is the preview request.
  Uri downloadUrl(String fs, String remote) => _base
      .resolve(kObjectPath)
      .replace(queryParameters: {'fs': fs, 'remote': remote, 'download': '1'});

  /// POSTs the bytes to the Web UI server, which writes them to the remote with
  /// whichever engine the host is running.
  ///
  /// The body is the file itself, not a multipart envelope — see [kUploadPath].
  /// The CSRF header is what distinguishes this from a cross-origin form post,
  /// and the session cookie rides along automatically because the URL is
  /// same-origin.
  @override
  Future<void> putObject(
    String fs,
    String remote,
    Stream<List<int>> bytes, {
    int? length,
  }) async {
    final uri = _base
        .resolve(kUploadPath)
        .replace(queryParameters: {'fs': fs, 'remote': remote});
    final req = http.StreamedRequest('POST', uri)
      ..headers[kWebUiCsrfHeader] = '1'
      ..headers['Content-Type'] = 'application/octet-stream';
    if (length != null) req.contentLength = length;
    unawaited(
      bytes
          .forEach(req.sink.add)
          .whenComplete(() => req.sink.close())
          .catchError((_) {}),
    );
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RcloneException(
        kUploadPath,
        'upload failed: ${res.body}',
        statusCode: res.statusCode,
      );
    }
  }

  /// A same-origin URL the browser can fetch object bytes from.
  ///
  /// No `Authorization` header: the session cookie already authenticates it,
  /// and because the URL is same-origin the browser attaches that cookie to
  /// `Image.network`, the video element and every other fetch without being
  /// told to. That is what lets the preview widgets work here unchanged.
  @override
  ObjectRef objectRef(String fs, String remote) {
    final uri = _base
        .resolve(kObjectPath)
        .replace(queryParameters: {'fs': fs, 'remote': remote});
    return ObjectRef(uri.toString(), const {});
  }
}
