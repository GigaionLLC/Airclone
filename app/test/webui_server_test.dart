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
      log: (_, _, {detail}) {},
    );
    await server.start();
    origin = 'http://127.0.0.1:${server.boundPort}';
    http = HttpClient();
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

    test('the cookie is not marked Secure over plain HTTP', () async {
      // Marking it Secure on an http:// origin makes the browser discard it,
      // which presents to the operator as "the password is wrong", forever.
      final res = await send(
        'POST',
        kLoginApiPath,
        json: {'username': creds.username, 'password': creds.password},
      );
      final cookie = res.cookies.firstWhere(
        (c) => c.name == kSessionCookieName,
      );
      expect(cookie.secure, isFalse);
      await res.drain<void>();
    });
  });

  group('throttling', () {
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
}
