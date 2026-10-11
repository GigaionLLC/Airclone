import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'platform.dart';
import 'rclone_client.dart';
import 'log_redaction.dart';
import 'rclone_log.dart';

/// A tiny loopback HTTP file server that gives the in-process ([FfiRcloneClient])
/// engine the ONE thing librclone lacks: a byte endpoint for object previews.
///
/// The spawned-`rcd` engine serves object bytes from its built-in `--rc-serve`
/// file server; librclone has no HTTP server and `RcloneRPC` returns JSON only.
/// So in library mode this bridge stands in. It STREAMS when it can: the first
/// request for an object on a remote starts rclone's own `serve http` for that
/// remote (rc `serve/start`, on loopback with a per-session login) and every
/// request is proxied to it, Range header included, so playback starts at once
/// and seeking reads only what it needs (#45). A librclone built without
/// rclone's serve commands fails `serve/start`, and then the bridge falls back
/// to materializing the bytes into a cache file via the `operations/copyfile`
/// RC method (run as an ASYNC job so a large download never blocks the engine
/// worker) and serving that file with Range support. That cache is capped
/// ([maxCacheBytes], [maxCacheAge]): before #45 it was never cleaned, and every
/// video played or thumbnailed on iOS stayed on the phone in full. Because it
/// returns the exact
/// same `http://…` URL + `Authorization` header shape as the rcd file server,
/// every preview widget (`Image.network`, media_kit, the text/pdf fetchers) works
/// UNCHANGED. See dev/archive-plans/dual-engine-plan.md §"objectRef under FFI".
class LibrcloneObjectServer {
  LibrcloneObjectServer({
    required this.rpc,
    required this.cacheDir,
    this.logSink = discardRcloneLog,
    this.maxCacheBytes = 1024 * 1024 * 1024,
    this.maxCacheAge = const Duration(days: 1),
  });

  /// The fallback cache's size cap: oldest files go first once it is exceeded.
  /// The file being served right now is never evicted, even when it alone is
  /// bigger.
  final int maxCacheBytes;

  /// Fallback cache files older than this are deleted.
  final Duration maxCacheAge;

  /// Where serving failures go. Defaults to discarding them.
  final RcloneLogSink logSink;

  /// The engine's RC entry point (typically `FfiRcloneClient.rpc`).
  final Future<Map<String, dynamic>> Function(
    String method, [
    Map<String, dynamic>? params,
  ])
  rpc;

  /// A writable directory for the materialized preview files, used by nothing
  /// else: pruning deletes whatever it finds there.
  final String cacheDir;

  HttpServer? _server;
  int? _port;
  String? _token;

  /// In-flight materializations, deduped by cache key, so two rapid requests for
  /// the same object (e.g. a thumbnail + a full preview) share one copy job.
  final _inflight = <String, Future<File>>{};

  /// The `serve http` behind each remote, started on first use; null when it
  /// could not start (then that remote uses the copy fallback).
  final _upstreams = <String, Future<_Upstream?>>{};

  /// Login for the `serve http` instances. Loopback is reachable by other apps
  /// on the device, so they are not left open.
  String? _upstreamAuth;

  final _client = HttpClient()..autoUncompress = false;

  bool get isRunning => _server != null;

  /// Bind loopback:0 and start serving. Mints a per-session bearer token so only
  /// this app's requests (which carry it) are honoured.
  Future<void> start() async {
    if (_server != null) return;
    _token = _randomToken();
    final user = _randomToken();
    final pass = _randomToken();
    _upstreamAuth = 'Basic ${base64.encode(utf8.encode('$user:$pass'))}';
    _upstreamLogin = (user, pass);
    await Directory(cacheDir).create(recursive: true);
    await pruneCache();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _port = server.port;
    unawaited(_serve(server));
  }

  (String, String)? _upstreamLogin;

  /// Stop serving, stop the `serve http` instances and drop the session
  /// secrets. Cached files stay for the next session, within the caps.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = null;
    _token = null;
    _upstreamAuth = null;
    _upstreamLogin = null;
    _inflight.clear();
    final upstreams = _upstreams.values.toList();
    _upstreams.clear();
    for (final up in upstreams) {
      try {
        final u = await up;
        if (u != null) await rpc('serve/stop', {'id': u.id});
      } catch (_) {}
    }
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
      // Never let one bad request tear the server down — but do not lose it
      // either. This swallowed every failure silently, including the paths that
      // throw before any response is written, so a regression here would have
      // been invisible: no log, no diagnostics entry, just a preview that never
      // arrived. The Web UI server's equivalent loop logs; this one now does too.
      unawaited(
        _handle(req).catchError(
          (Object e) => logSink(
            RcloneLogLevel.warning,
            'preview',
            'The in-process object server could not serve a request.',
            // The bearer token is this server's whole access control, and an
            // error can carry the request that quoted it.
            detail: redactEngineLine('$e', sessionSecrets: [?_token]),
          ),
        ),
      );
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
    if (req.method != 'GET') {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final String? fs;
    final String? remote;
    if (req.uri.path == '/obj') {
      fs = req.uri.queryParameters['fs'];
      remote = req.uri.queryParameters['remote'];
    } else {
      // Path-shaped form, `/o/[fs]/dir/file`. See objectRefPathShaped.
      final parsed = parseObjectPath(req.uri.path);
      fs = parsed?.$1;
      remote = parsed?.$2;
    }
    if (fs == null || remote == null) {
      res.statusCode = HttpStatus.badRequest;
      await res.close();
      return;
    }

    if (await _stream(req, res, fs, remote)) return;

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
  /// The path-shaped URL for [remote] on [fs], for content that fetches its own
  /// RELATIVE references.
  ///
  /// The query-shaped [objectRef] is fine for a self-contained object, but a
  /// streaming manifest is a list of segment names resolved against the URL it
  /// was loaded from. Given `…/obj?fs=X&remote=dir/v.m3u8`, a relative `seg1.ts`
  /// resolves to `…/seg1.ts` — losing the query entirely, and with it any idea
  /// of which remote or directory was meant. Every segment then 404s, which
  /// presents as a stream that simply never starts.
  ///
  /// Shaped like the rcd file server's `/[fs]/path` for the same reason it works
  /// there: the remote path lives in the URL path, so relative resolution lands
  /// back in the same directory on the same remote.
  ObjectRef objectRefPathShaped(String fs, String remote) {
    final segments = remote.split('/').map(Uri.encodeComponent).join('/');
    final uri =
        'http://${InternetAddress.loopbackIPv4.address}:$_port'
        '/o/${Uri.encodeComponent('[$fs]')}/$segments';
    return ObjectRef(uri, {'Authorization': 'Bearer $_token'});
  }

  /// Proxies the request to the remote's `serve http`. False when there is no
  /// upstream or it could not answer, and the caller falls back to the copy.
  Future<bool> _stream(
    HttpRequest req,
    HttpResponse res,
    String fs,
    String remote,
  ) async {
    final up = await _upstreamFor(fs);
    final auth = _upstreamAuth;
    if (up == null || auth == null) return false;
    Future<HttpClientResponse?> fetch() async {
      try {
        final out = await _client.getUrl(up.urlFor(remote));
        out.headers.set(HttpHeaders.authorizationHeader, auth);
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range != null) out.headers.set(HttpHeaders.rangeHeader, range);
        return await out.close();
      } catch (_) {
        return null;
      }
    }

    var upRes = await fetch();
    if (upRes == null) return false;
    if (upRes.statusCode == HttpStatus.notFound) {
      // serve http keeps directory listings for a few minutes, so a file added
      // since the folder was first read is not there yet. Forget that folder's
      // listing and ask once more.
      await upRes.drain<void>();
      final slash = remote.lastIndexOf('/');
      try {
        await rpc('vfs/forget', {
          'fs': fs,
          'dir': slash < 0 ? '' : remote.substring(0, slash),
        });
      } catch (_) {}
      upRes = await fetch();
      if (upRes == null) return false;
    }
    // Still a 404, or a server error: let the copy path try, and report.
    if (upRes.statusCode == HttpStatus.notFound || upRes.statusCode >= 500) {
      await upRes.drain<void>();
      return false;
    }
    res.statusCode = upRes.statusCode;
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    for (final h in [
      HttpHeaders.contentRangeHeader,
      HttpHeaders.lastModifiedHeader,
    ]) {
      final v = upRes.headers.value(h);
      if (v != null) res.headers.set(h, v);
    }
    if (upRes.contentLength >= 0) {
      res.headers.contentLength = upRes.contentLength;
    }
    final ct = _contentTypeFor(remote) ?? upRes.headers.contentType;
    if (ct != null) res.headers.contentType = ct;
    await res.addStream(upRes);
    await res.close();
    return true;
  }

  Future<_Upstream?> _upstreamFor(String fs) {
    final login = _upstreamLogin;
    if (login == null) return Future.value(null);
    return _upstreams.putIfAbsent(fs, () async {
      try {
        final out = await rpc('serve/start', {
          'type': 'http',
          'fs': fs,
          'addr': '127.0.0.1:0',
          'user': login.$1,
          'pass': login.$2,
        });
        final id = out['id'];
        final addr = out['addr'];
        if (id is! String || addr is! String) return null;
        return _Upstream(id, addr);
      } catch (e) {
        logSink(
          RcloneLogLevel.notice,
          'preview',
          'Streaming is not available here, so previews download first.',
          detail: redactEngineLine('$e'),
        );
        return null;
      }
    });
  }

  /// Deletes leftover partial copies and files older than [maxCacheAge], then
  /// the oldest files until the cache fits [maxCacheBytes]. Never touches
  /// [keep] or a copy still being written. Best-effort.
  Future<void> pruneCache({String? keep}) async {
    try {
      final dir = Directory(cacheDir);
      if (!await dir.exists()) return;
      final inflight = _inflight.keys.toSet();
      final cutoff = DateTime.now().subtract(maxCacheAge);
      final files = <(File, int, DateTime)>[];
      var kept = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final leaf = e.uri.pathSegments.last;
        final key = leaf.endsWith('.part')
            ? leaf.substring(0, leaf.length - 5)
            : leaf;
        final stat = await e.stat();
        if (leaf == keep || inflight.contains(key)) {
          // Counted, so the others make room for it, but never deleted.
          kept += stat.size;
          continue;
        }
        if (leaf.endsWith('.part') || stat.modified.isBefore(cutoff)) {
          await _delete(e);
          continue;
        }
        files.add((e, stat.size, stat.modified));
      }
      var total = files.fold<int>(kept, (n, f) => n + f.$2);
      files.sort((a, b) => a.$3.compareTo(b.$3));
      for (final f in files) {
        if (total <= maxCacheBytes) break;
        await _delete(f.$1);
        total -= f.$2;
      }
    } catch (_) {}
  }

  static Future<void> _delete(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }

  Future<File> _materialize(String fs, String remote) {
    final key = sha1.convert(utf8.encode('$fs\u0000$remote')).toString();
    final dst = File('$cacheDir${EnginePlatform.pathSeparator}$key');
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
        final partFile = File('$cacheDir${EnginePlatform.pathSeparator}$part');
        if (await dst.exists()) await dst.delete();
        await partFile.rename(dst.path);
        _inflight.remove(key);
        await pruneCache(keep: key);
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

/// Splits `/o/[fs]/dir/file` back into its fs and remote path, or null when the
/// shape does not match. Pure, so the encoding round-trip is testable.
(String, String)? parseObjectPath(String path) {
  if (!path.startsWith('/o/')) return null;
  final rest = path.substring(3);
  final slash = rest.indexOf('/');
  if (slash <= 0) return null;
  final rawFs = Uri.decodeComponent(rest.substring(0, slash));
  if (!rawFs.startsWith('[') || !rawFs.endsWith(']')) return null;
  final fs = rawFs.substring(1, rawFs.length - 1);
  if (fs.isEmpty) return null;
  final remote = rest
      .substring(slash + 1)
      .split('/')
      .map(Uri.decodeComponent)
      .join('/');
  if (remote.isEmpty) return null;
  // A decoded `..` segment would climb out of the intended directory. rclone
  // resolves the path itself, but refusing here keeps the bridge from ever
  // being the thing that asked.
  // Both separators, for the reason the upload guard gives: rclone's local
  // backend treats a backslash as one on Windows.
  if (remote.split(RegExp(r'[/\\]')).contains('..')) return null;
  return (fs, remote);
}

/// One running `serve http`, rooted at the remote it serves.
class _Upstream {
  _Upstream(this.id, this.addr);

  final String id;

  /// `host:port`, as `serve/start` reported it.
  final String addr;

  Uri urlFor(String remote) => Uri.parse(
    'http://$addr/${remote.split('/').map(Uri.encodeComponent).join('/')}',
  );
}
