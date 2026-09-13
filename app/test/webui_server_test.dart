/// End-to-end tests for the Web UI server, over a real loopback socket.
///
/// Deliberately not mocked at the HTTP layer: the things most worth proving
/// here — that an unauthenticated request cannot reach the RC proxy, that a
/// cookie is `HttpOnly`, that a missing CSRF header is refused — are properties
/// of real requests and real headers, and a fake would happily agree with
/// whatever the implementation did.
library;

import 'dart:convert';
import 'dart:io';

import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/webui/webui_credentials.dart';
import 'package:airclone/src/webui/webui_options.dart';
import 'package:airclone/src/webui/webui_protocol.dart';
import 'package:airclone/src/webui/webui_server.dart';
import 'package:airclone/src/webui/webui_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the server forwards, and answers without an engine.
class _FakeClient implements RcloneClient {
  final List<String> calls = [];
  Object? nextError;

  /// Answer to return instead of the echo, for a test that needs a real
  /// `operations/list` shape to be annotated.
  Map<String, dynamic>? nextResult;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    calls.add(method);
    final err = nextError;
    if (err != null) {
      nextError = null;
      throw err;
    }
    final canned = nextResult;
    if (canned != null) {
      nextResult = null;
      return canned;
    }
    return {'method': method, 'params': params};
  }

  @override
  Future<void> start() async {}
  @override
  Future<void> quit() async {}
  @override
  Future<void> restart() async {}
  @override
  Future<EngineStatus> status() async =>
      const EngineStatus(EngineState.running, version: 'test');
  @override
  ObjectRef objectRef(String fs, String remote) =>
      ObjectRef('http://127.0.0.1:1/$fs/$remote', const {});
}

void main() {
  late Directory tlsDir;
  setUpAll(() => tlsDir = Directory.systemTemp.createTempSync('acl_webui_tls'));
  tearDownAll(() {
    if (tlsDir.existsSync()) tlsDir.deleteSync(recursive: true);
  });
  const creds = WebUiCredentials(
    username: 'airclone',
    password: 'correct-horse',
  );

  late _FakeClient engine;
  late WebUiServer server;
  late HttpClient http;
  late String origin;

  setUp(() async {
    engine = _FakeClient();
    server = WebUiServer(
      // Port 0: let the OS pick, so tests never collide with a real Airclone.
      options: const WebUiOptions(enabled: true, port: 0),
      credentials: creds,
      engineClient: () => engine,
      // One directory for the whole file: generating an RSA key pair takes
      // about a second, and doing it per test would dominate the run.
      tlsDir: tlsDir.path,
      log: (_, _, {detail}) {},
    );
    await server.start();
    origin = 'https://127.0.0.1:${server.boundPort}';
    http = HttpClient()
      // The server is HTTPS with a self-signed certificate by design, which is
      // exactly what a browser warns about. A test client has no user to warn,
      // so it accepts it deliberately rather than by accident.
      ..badCertificateCallback = (_, _, _) => true;
  });

  tearDown(() async {
    http.close(force: true);
    await server.stop();
  });

  /// Issues a request, optionally carrying a session cookie and a JSON body.
  Future<HttpClientResponse> send(
    String method,
    String path, {
    String? cookie,
    Object? json,
    bool csrf = true,
  }) async {
    final req = await http.openUrl(method, Uri.parse('$origin$path'));
    req.followRedirects = false;
    if (cookie != null) req.headers.set(HttpHeaders.cookieHeader, cookie);
    if (csrf) req.headers.set(kWebUiCsrfHeader, '1');
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    }
    return req.close();
  }

  /// Signs in and returns the `name=value` session cookie.
  Future<String> signIn() async {
    final res = await send(
      'POST',
      kLoginApiPath,
      json: {'username': creds.username, 'password': creds.password},
    );
    expect(res.statusCode, 200);
    await res.drain<void>();
    final cookie = res.cookies.firstWhere((c) => c.name == kSessionCookieName);
    return '${cookie.name}=${cookie.value}';
  }

  group('unauthenticated', () {
    test('the RC proxy is closed', () async {
      final res = await send('POST', kRcPath, json: {'method': 'core/version'});
      expect(res.statusCode, HttpStatus.unauthorized);
      await res.drain<void>();
      // The engine must not have been touched at all.
      expect(engine.calls, isEmpty);
    });

    test('object bytes are closed', () async {
      final res = await send('GET', '$kObjectPath?fs=x:&remote=y');
      expect(res.statusCode, HttpStatus.unauthorized);
      await res.drain<void>();
    });

    test('the app bundle is closed and redirects to sign-in', () async {
      final res = await send('GET', '/');
      expect(res.statusCode, HttpStatus.found);
      expect(res.headers.value(HttpHeaders.locationHeader), kLoginPath);
      await res.drain<void>();
    });

    test('the sign-in page itself is reachable', () async {
      final res = await send('GET', kLoginPath);
      expect(res.statusCode, 200);
      final body = await res.transform(utf8.decoder).join();
      expect(body, contains('Sign in'));
      // It must be small — this is what an internet scanner gets.
      expect(body.length, lessThan(20000));
    });
  });

  group('sign-in', () {
    test('the right password issues a hardened cookie', () async {
      final res = await send(
        'POST',
        kLoginApiPath,
        json: {'username': creds.username, 'password': creds.password},
      );
      expect(res.statusCode, 200);
      await res.drain<void>();
      final cookie = res.cookies.firstWhere(
        (c) => c.name == kSessionCookieName,
      );
      expect(cookie.value, isNotEmpty);
      // HttpOnly keeps it away from any script that gets injected into the page.
      expect(cookie.httpOnly, isTrue);
      expect(cookie.sameSite, SameSite.strict);
    });

    test('a wrong password is refused, and so is a wrong username', () async {
      for (final body in [
        {'username': creds.username, 'password': 'nope'},
        {'username': 'someone-else', 'password': creds.password},
      ]) {
        final res = await send('POST', kLoginApiPath, json: body);
        expect(res.statusCode, HttpStatus.unauthorized);
        final text = await res.transform(utf8.decoder).join();
        // Identical wording either way: anything else is a username oracle.
        expect(text, contains('did not match'));
        expect(res.cookies.where((c) => c.name == kSessionCookieName), isEmpty);
      }
    });

    test('a cross-origin post with no CSRF header is refused', () async {
      final res = await send(
        'POST',
        kLoginApiPath,
        csrf: false,
        json: {'username': creds.username, 'password': creds.password},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      await res.drain<void>();
    });

    test('GET is not a way in', () async {
      final res = await send('GET', kLoginApiPath);
      expect(res.statusCode, HttpStatus.methodNotAllowed);
      await res.drain<void>();
    });
  });

  group('signed in', () {
    test('an allowed method reaches the engine', () async {
      final cookie = await signIn();
      final res = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        json: {
          'method': 'operations/list',
          'params': {'fs': 'remote:', 'remote': ''},
        },
      );
      expect(res.statusCode, 200);
      await res.drain<void>();
      expect(engine.calls, ['operations/list']);
    });

    test('core/command is refused even with a valid session', () async {
      // The allowlist is not an authentication check — it still applies to a
      // fully signed-in operator, because a stolen session is the case it
      // exists for.
      final cookie = await signIn();
      final res = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        json: {
          'method': 'core/command',
          'params': {'command': 'version'},
        },
      );
      expect(res.statusCode, HttpStatus.forbidden);
      await res.drain<void>();
      expect(engine.calls, isEmpty);
    });

    test('core/quit cannot kill the host engine', () async {
      final cookie = await signIn();
      final res = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        json: {'method': 'core/quit'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      await res.drain<void>();
      expect(engine.calls, isEmpty);
    });

    test('an RC call without the CSRF header is refused', () async {
      final cookie = await signIn();
      final res = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        csrf: false,
        json: {'method': 'core/version'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      await res.drain<void>();
      expect(engine.calls, isEmpty);
    });

    test('an rclone error is relayed, not swallowed', () async {
      final cookie = await signIn();
      engine.nextError = RcloneException(
        'operations/about',
        'not supported',
        statusCode: 500,
      );
      final res = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        json: {'method': 'operations/about'},
      );
      expect(res.statusCode, 500);
      final body = jsonDecode(await res.transform(utf8.decoder).join());
      expect(body['error'], 'not supported');
    });

    test('a body over the cap is refused', () async {
      final cookie = await signIn();
      final res = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        json: {
          'method': 'operations/list',
          'params': {'blob': 'x' * (kMaxRcBodyBytes + 1024)},
        },
      );
      expect(res.statusCode, HttpStatus.badRequest);
      await res.drain<void>();
      expect(engine.calls, isEmpty);
    });

    test('signing out invalidates the cookie immediately', () async {
      final cookie = await signIn();
      final out = await send('POST', kLogoutPath, cookie: cookie);
      expect(out.statusCode, 200);
      await out.drain<void>();
      final after = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        json: {'method': 'core/version'},
      );
      expect(after.statusCode, HttpStatus.unauthorized);
      await after.drain<void>();
    });

    test('a forged cookie value does not authenticate', () async {
      final res = await send(
        'POST',
        kRcPath,
        cookie: '$kSessionCookieName=not-a-real-token',
        json: {'method': 'core/version'},
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      await res.drain<void>();
    });

    test('rotating the credentials signs existing sessions out', () async {
      final cookie = await signIn();
      server.rotateCredentials(
        const WebUiCredentials(username: 'airclone', password: 'new'),
      );
      final res = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        json: {'method': 'core/version'},
      );
      // Otherwise "change the password" would not actually lock anyone out.
      expect(res.statusCode, HttpStatus.unauthorized);
      await res.drain<void>();
    });
  });

  group('response hardening', () {
    test('every response carries the security headers', () async {
      final res = await send('GET', kLoginPath);
      expect(res.headers.value('X-Content-Type-Options'), 'nosniff');
      expect(res.headers.value('X-Frame-Options'), 'DENY');
      expect(res.headers.value('Referrer-Policy'), 'no-referrer');
      final csp = res.headers.value('Content-Security-Policy')!;
      expect(csp, contains("frame-ancestors 'none'"));
      expect(csp, contains("object-src 'none'"));
      // CanvasKit is WebAssembly, which CSP counts as eval; this permits
      // exactly that and not JavaScript eval().
      expect(csp, contains("'wasm-unsafe-eval'"));
      await res.drain<void>();
    });

    test(
      'the sign-in page script carries a nonce the CSP actually allows',
      () async {
        // This is the bug that got through twice. `script-src 'self'` does not
        // cover inline script, so without a matching nonce the browser silently
        // drops the login script, the form degrades to a native POST, and the
        // CSRF check refuses it — presenting as "sign in does nothing". Neither
        // half is enough on its own: the first attempt shipped a nonce in the
        // page whose header counterpart was the literal text "$scriptNonce".
        final res = await send('GET', kLoginPath);
        final csp = res.headers.value('Content-Security-Policy')!;
        final body = await res.transform(utf8.decoder).join();

        final inPage = RegExp(
          r'<script nonce="([A-Za-z0-9_-]+)">',
        ).firstMatch(body);
        expect(inPage, isNotNull, reason: 'no nonce on the inline script');
        final nonce = inPage!.group(1)!;
        expect(nonce.length, greaterThanOrEqualTo(16));
        expect(csp, contains("'nonce-$nonce'"));
        // An un-interpolated placeholder would satisfy a laxer check than this.
        expect(csp, isNot(contains(r'$')));
      },
    );

    test('each sign-in page gets a fresh nonce', () async {
      // A nonce reused across responses is no better than 'unsafe-inline':
      // injected script could simply carry the known value.
      Future<String> nonceOf() async {
        final res = await send('GET', kLoginPath);
        final body = await res.transform(utf8.decoder).join();
        return RegExp(
          r'<script nonce="([A-Za-z0-9_-]+)">',
        ).firstMatch(body)!.group(1)!;
      }

      expect(await nonceOf(), isNot(await nonceOf()));
    });

    test('the session cookie is marked Secure', () async {
      // Unconditional now that the server is HTTPS-only. It used to depend on
      // an x-forwarded-proto header, because Secure on a plain-HTTP origin
      // makes the browser discard the cookie and that looks like a wrong
      // password forever. There is no plain-HTTP origin any more.
      final res = await send(
        'POST',
        kLoginApiPath,
        json: {'username': creds.username, 'password': creds.password},
      );
      final cookie = res.cookies.firstWhere(
        (c) => c.name == kSessionCookieName,
      );
      expect(cookie.secure, isTrue);
      expect(cookie.httpOnly, isTrue);
      expect(cookie.sameSite, SameSite.strict);
      await res.drain<void>();
    });
    test('repeated failures start refusing attempts', () async {
      for (var i = 0; i < kLoginFailuresBeforeBackoff; i++) {
        final res = await send(
          'POST',
          kLoginApiPath,
          json: {'username': creds.username, 'password': 'wrong'},
        );
        expect(res.statusCode, HttpStatus.unauthorized);
        await res.drain<void>();
      }
      final res = await send(
        'POST',
        kLoginApiPath,
        json: {'username': creds.username, 'password': creds.password},
      );
      // Even the CORRECT password waits: the lockout is on the peer, not on
      // whether this particular guess happened to be right.
      expect(res.statusCode, HttpStatus.tooManyRequests);
      expect(res.headers.value('Retry-After'), isNotNull);
      await res.drain<void>();
    });
  });

  group('static bundle', () {
    test('says something useful when it was never packaged', () async {
      final cookie = await signIn();
      final res = await send('GET', '/', cookie: cookie);
      expect(res.statusCode, HttpStatus.serviceUnavailable);
      final body = await res.transform(utf8.decoder).join();
      expect(body, contains('flutter build web'));
    });
  });
  group('upload', () {
    // The engine seam decides HOW bytes land; these cover what the endpoint
    // must refuse before any engine is involved.
    test('closed to an unauthenticated caller', () async {
      final res = await send('POST', '/api/upload?fs=x:&remote=a.txt');
      expect(res.statusCode, HttpStatus.unauthorized);
      await res.drain<void>();
    });

    test('refused without the CSRF header', () async {
      final cookie = await signIn();
      final res = await send(
        'POST',
        '/api/upload?fs=x:&remote=a.txt',
        cookie: cookie,
        csrf: false,
      );
      expect(res.statusCode, HttpStatus.forbidden);
      await res.drain<void>();
    });

    test('GET is not an upload', () async {
      final cookie = await signIn();
      final res = await send(
        'GET',
        '/api/upload?fs=x:&remote=a.txt',
        cookie: cookie,
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
      await res.drain<void>();
    });

    test('fs and remote are required', () async {
      final cookie = await signIn();
      final res = await send('POST', '/api/upload', cookie: cookie);
      expect(res.statusCode, HttpStatus.badRequest);
      await res.drain<void>();
    });

    test('a destination that climbs out is refused', () async {
      // Refused here rather than left to rclone, the same stance
      // resolveStaticFile takes for reads.
      final cookie = await signIn();
      final res = await send(
        'POST',
        '/api/upload?fs=x:&remote=a/../../etc/passwd',
        cookie: cookie,
      );
      expect(res.statusCode, HttpStatus.badRequest);
      await res.drain<void>();
    });

    test(
      'an engine that cannot upload says so, rather than failing oddly',
      () async {
        // _FakeClient implements RcloneClient but NOT ObjectUploader - which is
        // the point of making upload a separate capability.
        final cookie = await signIn();
        final res = await send(
          'POST',
          '/api/upload?fs=x:&remote=a.txt',
          cookie: cookie,
        );
        expect(res.statusCode, HttpStatus.serviceUnavailable);
        await res.drain<void>();
      },
    );
  });

  /// A user's Web UI downloaded several hundred Proton Drive files on one page
  /// load, and drew no cloud badges. Both are the same fault: the browser was
  /// answering a question only the host can answer, because the web build's
  /// native probes truthfully report "there is no filesystem here".
  ///
  /// The unit tests for [annotatePlaceholders] prove the logic. These prove the
  /// WIRING - that the annotation survives the RC proxy, real HTTP and JSON, and
  /// arrives in a shape [RcloneFile.fromJson] reads - which is the part that was
  /// actually broken and the part a unit test cannot see.
  group('placeholder annotation over real HTTP', () {
    late Directory files;
    setUp(() {
      files = Directory.systemTemp.createTempSync('acl_ph');
      File('${files.path}/a.png').writeAsBytesSync([1, 2, 3]);
      File('${files.path}/b.png').writeAsBytesSync([4, 5, 6]);
    });
    tearDown(() {
      if (files.existsSync()) files.deleteSync(recursive: true);
    });

    Future<List<dynamic>> listOver(String fs, String remote) async {
      final cookie = await signIn();
      engine.nextResult = {
        'list': [
          {'Path': 'a.png', 'Name': 'a.png', 'IsDir': false, 'Size': 3},
          {'Path': 'b.png', 'Name': 'b.png', 'IsDir': false, 'Size': 3},
        ],
      };
      final res = await send(
        'POST',
        kRcPath,
        cookie: cookie,
        json: {
          'method': 'operations/list',
          'params': {'fs': fs, 'remote': remote},
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.transform(utf8.decoder).join());
      return (body as Map)['list'] as List;
    }

    test('a local root comes back with every entry answered', () async {
      final list = await listOver(files.path, '');
      expect(list, hasLength(2));
      for (final e in list) {
        expect((e as Map).containsKey(kOnlineOnlyField), isTrue);
      }
    });

    test('and the client model reads it', () async {
      final list = await listOver(files.path, '');
      final parsed = [
        for (final e in list)
          RcloneFile.fromJson((e as Map).cast<String, dynamic>()),
      ];
      // These are ordinary files on a temp disk, so the host's answer is a
      // definite "resident" - NOT null, which is what an unanswered entry
      // would give and what the browser used to see for everything.
      expect(parsed.map((f) => f.onlineOnly), everyElement(isFalse));
    });

    test('a named remote is left unanswered, not answered "no"', () async {
      final list = await listOver('gdrive:', 'Photos');
      for (final e in list) {
        expect((e as Map).containsKey(kOnlineOnlyField), isFalse);
      }
      final parsed = RcloneFile.fromJson(
        (list.first as Map).cast<String, dynamic>(),
      );
      expect(parsed.onlineOnly, isNull);
    });
  });

  /// The object endpoint's guard was widened from `download=1` to EVERY content
  /// read, which is what stops a thumbnail hydrating a file. Widening a refusal
  /// is exactly the change that can start refusing everything, and that would
  /// break every preview, thumbnail and video in the Web UI at once.
  group('widening the hydration guard did not break ordinary files', () {
    late Directory files;
    setUp(() {
      files = Directory.systemTemp.createTempSync('acl_obj');
      File('${files.path}/plain.png').writeAsBytesSync([1, 2, 3]);
    });
    tearDown(() {
      if (files.existsSync()) files.deleteSync(recursive: true);
    });

    // The fake engine's object URL points at a dead port, so the request cannot
    // succeed. It does not need to: what is being proven is that the guard let
    // it THROUGH to the engine, and 409 is the one status that means it did not.
    test('a resident file is not refused as a placeholder', () async {
      final cookie = await signIn();
      final res = await send(
        'GET',
        '$kObjectPath?fs=${Uri.encodeQueryComponent(files.path)}'
            '&remote=plain.png',
        cookie: cookie,
      );
      expect(res.statusCode, isNot(HttpStatus.conflict));
      await res.drain<void>();
    });

    test('nor when it is a download rather than a preview', () async {
      final cookie = await signIn();
      final res = await send(
        'GET',
        '$kObjectPath?fs=${Uri.encodeQueryComponent(files.path)}'
            '&remote=plain.png&download=1',
        cookie: cookie,
      );
      expect(res.statusCode, isNot(HttpStatus.conflict));
      await res.drain<void>();
    });

    test('nor a file on a named remote, which cannot be resolved', () async {
      final cookie = await signIn();
      final res = await send(
        'GET',
        '$kObjectPath?fs=gdrive:&remote=Photos/holiday.jpg',
        cookie: cookie,
      );
      expect(res.statusCode, isNot(HttpStatus.conflict));
      await res.drain<void>();
    });
  });
}
