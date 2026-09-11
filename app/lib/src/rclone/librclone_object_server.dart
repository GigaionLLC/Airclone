import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../state/host_platform.dart';
import 'rclone_client.dart';

/// A tiny loopback HTTP file server that gives the in-process ([FfiRcloneClient])
/// engine the ONE thing librclone lacks: a byte endpoint for object previews.
///
/// The spawned-`rcd` engine serves object bytes from its built-in `--rc-serve`
/// file server; librclone has no HTTP server and `RcloneRPC` returns JSON only.
/// So in library mode this bridge stands in: on the first request for an object
/// it materializes the bytes to a temp cache file via the `operations/copyfile`
/// RC method (run as an ASYNC job so a large download never blocks the engine
/// worker), then streams that file back — with HTTP Range support, so media
/// seeking works and re-opens/paging hit the cache. Because it returns the exact
/// same `http://…` URL + `Authorization` header shape as the rcd file server,
/// every preview widget (`Image.network`, media_kit, the text/pdf fetchers) works
/// UNCHANGED. See dev/archive-plans/dual-engine-plan.md §"objectRef under FFI".
class LibrcloneObjectServer {
  LibrcloneObjectServer({required this.rpc, required this.cacheDir});

  /// The engine's RC entry point (typically `FfiRcloneClient.rpc`).
  final Future<Map<String, dynamic>> Function(
    String method, [
    Map<String, dynamic>? params,
  ])
  rpc;

  /// A writable directory for the materialized preview files (the app cache).
  final String cacheDir;

  HttpServer? _server;
  int? _port;
  String? _token;

  /// In-flight materializations, deduped by cache key, so two rapid requests for
  /// the same object (e.g. a thumbnail + a full preview) share one copy job.
  final _inflight = <String, Future<File>>{};

  bool get isRunning => _server != null;

  /// Bind loopback:0 and start serving. Mints a per-session bearer token so only
  /// this app's requests (which carry it) are honoured.
  Future<void> start() async {
    if (_server != null) return;
    _token = _randomToken();
    await Directory(cacheDir).create(recursive: true);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _port = server.port;
    unawaited(_serve(server));
  }

  /// Stop serving and drop the session token. Materialized temp files are left
  /// for the OS/app cache policy to reclaim (they live under [cacheDir]).
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = null;
    _token = null;
    _inflight.clear();
    await server?.close(force: true);
  }

  /// The authenticated URL + header pair for [remote] on [fs], drop-in for the
  /// rcd file server's [ObjectRef]. Synchronous: the bytes are fetched lazily on
  /// the first GET.
  ObjectRef objectRef(String fs, String remote) {
    final uri =
        'http://${InternetAddress.loopbackIPv4.address}:$_port/obj'
        '?fs=${Uri.encodeQueryComponent(fs)}'
        '&remote=${Uri.encodeQueryComponent(remote)}';
    return ObjectRef(uri, {'Authorization': 'Bearer $_token'});
  }

  Future<void> _serve(HttpServer server) async {
    await for (final req in server) {
      // Never let one bad request tear the server down.
      unawaited(_handle(req).catchError((_) {}));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    // Constant-ish token check (length-guarded equality is fine on loopback).
    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    final token = _token;
    if (token == null || auth != 'Bearer $token') {
      res.statusCode = HttpStatus.forbidden;
      await res.close();
      return;
    }
    if (req.method != 'GET' || req.uri.path != '/obj') {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final fs = req.uri.queryParameters['fs'];
    final remote = req.uri.queryParameters['remote'];
    if (fs == null || remote == null) {
      res.statusCode = HttpStatus.badRequest;
      await res.close();
      return;
    }

    final File file;
    try {
      file = await _materialize(fs, remote);
    } catch (e) {
      res.statusCode = HttpStatus.notFound;
      res.write('preview unavailable: $e');
      await res.close();
      return;
    }

    await _sendFile(req, res, file, remote);
  }

  /// Copy `fs:remote` into the cache (once) and return the local file. The copy
  /// runs as an async RC job so a large object never blocks the engine worker.
  Future<File> _materialize(String fs, String remote) {
    final key = sha1.convert(utf8.encode('$fs\u0000$remote')).toString();
    final dst = File('$cacheDir${HostPlatform.pathSeparator}$key');
    return _inflight.putIfAbsent(key, () async {
      try {
        if (await dst.exists() && await dst.length() > 0) return dst;
        final part = '$key.part';
        final res = await rpc('operations/copyfile', {
          'srcFs': fs,
          'srcRemote': remote,
          'dstFs': cacheDir,
          'dstRemote': part,
          '_async': true,
        });
        final jobid = (res['jobid'] as num?)?.toInt();
        if (jobid == null) {
          throw StateError('copyfile did not return a jobid');
        }
        await _awaitJob(jobid);
        final partFile = File('$cacheDir${HostPlatform.pathSeparator}$part');
        if (await dst.exists()) await dst.delete();
        await partFile.rename(dst.path);
        return dst;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  /// Poll `job/status` until the async copy finishes; throw on failure.
  Future<void> _awaitJob(int jobid) async {
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (DateTime.now().isBefore(deadline)) {
      final st = await rpc('job/status', {'jobid': jobid});
      if (st['finished'] == true) {
        if (st['success'] == true) return;
        throw StateError('copy failed: ${st['error'] ?? 'unknown error'}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('copy timed out');
  }

  /// Stream [file] to the response, honouring a single `Range: bytes=a-b` header
  /// (a 206 partial), else the whole file (a 200). Sets Accept-Ranges + a
  /// best-effort content type so media/image widgets behave like they do against
  /// the rcd file server.
  Future<void> _sendFile(
    HttpRequest req,
    HttpResponse res,
    File file,
    String remote,
  ) async {
    final total = await file.length();
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final ct = _contentTypeFor(remote);
    if (ct != null) res.headers.contentType = ct;

    final range = req.headers.value(HttpHeaders.rangeHeader);
    final parsed = range == null ? null : parseByteRange(range, total);
    if (parsed == null) {
      res.statusCode = HttpStatus.ok;
      res.headers.contentLength = total;
      await res.addStream(file.openRead());
      await res.close();
      return;
    }
    final (start, end) = parsed; // inclusive
    res.statusCode = HttpStatus.partialContent;
    res.headers
      ..set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total')
      ..contentLength = end - start + 1;
    await res.addStream(file.openRead(start, end + 1));
    await res.close();
  }

  static ContentType? _contentTypeFor(String remote) {
    final dot = remote.lastIndexOf('.');
    if (dot < 0) return null;
    switch (remote.substring(dot + 1).toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'png':
        return ContentType('image', 'png');
      case 'gif':
        return ContentType('image', 'gif');
      case 'webp':
        return ContentType('image', 'webp');
      case 'bmp':
        return ContentType('image', 'bmp');
      case 'svg':
        return ContentType('image', 'svg+xml');
      case 'mp4':
      case 'm4v':
        return ContentType('video', 'mp4');
      case 'webm':
        return ContentType('video', 'webm');
      case 'mp3':
        return ContentType('audio', 'mpeg');
      case 'flac':
        return ContentType('audio', 'flac');
      case 'wav':
        return ContentType('audio', 'wav');
      case 'pdf':
        return ContentType('application', 'pdf');
      case 'txt':
      case 'md':
      case 'log':
        return ContentType('text', 'plain', charset: 'utf-8');
      default:
        return null;
    }
  }

  static String _randomToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Parse a single-range `bytes=a-b` / `bytes=a-` / `bytes=-n` header into an
/// inclusive `(start, end)` clamped to `[0, total)`. Returns null if malformed
/// or unsatisfiable (the caller then sends the whole file). Pure — unit-tested.
(int, int)? parseByteRange(String header, int total) {
  if (total <= 0 || !header.startsWith('bytes=')) return null;
  final spec = header.substring(6).split(',').first.trim();
  final dash = spec.indexOf('-');
  if (dash < 0) return null;
  final startStr = spec.substring(0, dash);
  final endStr = spec.substring(dash + 1);
  int start;
  int end;
  if (startStr.isEmpty) {
    // suffix form: the last N bytes
    final n = int.tryParse(endStr);
    if (n == null || n <= 0) return null;
    start = max(0, total - n);
    end = total - 1;
  } else {
    final s = int.tryParse(startStr);
    if (s == null) return null;
    start = s;
    end = endStr.isEmpty ? total - 1 : (int.tryParse(endStr) ?? total - 1);
  }
  if (start > end || start >= total) return null;
  return (start, min(end, total - 1));
}
