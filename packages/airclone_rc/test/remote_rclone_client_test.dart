import 'dart:convert';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// [RemoteRcloneClient] talks to an engine it does not own, so everything worth
/// asserting is on the wire: where it posts, what it sends, what it refuses to
/// do at all. A MockClient is the whole test rig - no engine, no process.
void main() {
  final calls = <http.Request>[];

  http.Client mock({
    int status = 200,
    Map<String, dynamic> body = const {'version': 'v1.75.1'},
  }) => MockClient((req) async {
    calls.add(req);
    return http.Response(jsonEncode(body), status);
  });

  setUp(calls.clear);

  group('the wire', () {
    test(
      'posts the method against the base URL, with the auth header',
      () async {
        final c = RemoteRcloneClient(
          baseUrl: Uri.parse('http://127.0.0.1:5572/'),
          authorization: basicAuth('user', 'hunter2'),
          httpClient: mock(body: const {'list': []}),
        );
        await c.rpc('operations/list', {'fs': 'gdrive:', 'remote': 'papers'});

        expect(
          calls.single.url.toString(),
          'http://127.0.0.1:5572/operations/list',
        );
        expect(calls.single.method, 'POST');
        expect(calls.single.headers['Authorization'], 'Basic dXNlcjpodW50ZXIy');
        expect(jsonDecode(calls.single.body), {
          'fs': 'gdrive:',
          'remote': 'papers',
        });
      },
    );

    test('a base URL with a path prefix is respected', () async {
      // A host that proxies the engine under a path - which is exactly how a
      // desktop app would expose it to its own web UI.
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('https://host.example/engine/'),
        httpClient: mock(),
      );
      await c.rpc('core/version');
      expect(
        calls.single.url.toString(),
        'https://host.example/engine/core/version',
      );
    });

    test('no authorization means no header, not an empty one', () async {
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('http://localhost:5572/'),
        httpClient: mock(),
      );
      await c.rpc('rc/noop');
      expect(calls.single.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'a non-2xx answer becomes an RcloneException carrying the code',
      () async {
        final c = RemoteRcloneClient(
          baseUrl: Uri.parse('http://127.0.0.1:5572/'),
          httpClient: mock(status: 500, body: const {'error': 'boom'}),
        );
        await expectLater(
          c.rpc('operations/list'),
          throwsA(
            isA<RcloneException>()
                .having((e) => e.statusCode, 'statusCode', 500)
                .having((e) => e.message, 'message', 'boom'),
          ),
        );
      },
    );

    test('a transport failure is reported redacted, not raw', () async {
      final sink = <String>[];
      final auth = basicAuth('user', 'hunter2');
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('http://127.0.0.1:5572/'),
        authorization: auth,
        logSink: (level, area, message, {detail}) =>
            sink.add('$message | $detail'),
        // Fails with a message that quotes the request, credentials included -
        // which is how a client library leaks them into someone's log.
        httpClient: MockClient((req) async {
          throw http.ClientException(
            'connection failed sending Authorization: $auth',
            req.url,
          );
        }),
      );
      await expectLater(c.rpc('core/version'), throwsA(isA<RcloneException>()));
      expect(sink, hasLength(1));
      expect(sink.single, isNot(contains(auth)));
      expect(sink.single, contains('<redacted>'));
    });
  });

  group('what it refuses', () {
    test('plaintext HTTP to a non-loopback host', () {
      expect(
        () =>
            RemoteRcloneClient(baseUrl: Uri.parse('http://192.168.1.10:5572/')),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('shell access'),
          ),
        ),
      );
      // Loopback is fine: nothing leaves the machine.
      expect(
        () => RemoteRcloneClient(baseUrl: Uri.parse('http://127.0.0.1:5572/')),
        returnsNormally,
      );
      // https anywhere is fine.
      expect(
        () => RemoteRcloneClient(baseUrl: Uri.parse('https://host.example/')),
        returnsNormally,
      );
      // And the refusal is a default, not a rule: a caller can decide.
      expect(
        () => RemoteRcloneClient(
          baseUrl: Uri.parse('http://192.168.1.10:5572/'),
          allowInsecure: true,
        ),
        returnsNormally,
      );
    });

    test('a URL that is not HTTP at all', () {
      expect(
        () => RemoteRcloneClient(baseUrl: Uri.parse('ftp://host/')),
        throwsA(isA<ArgumentError>()),
      );
      // No scheme at all, e.g. a path someone meant to be relative.
      expect(
        () => RemoteRcloneClient(baseUrl: Uri.parse('/engine/')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('restarting an engine it does not own', () async {
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('http://127.0.0.1:5572/'),
        httpClient: mock(),
      );
      await expectLater(c.restart(), throwsA(isA<UnsupportedError>()));
    });

    test('quit() does NOT ask the engine to exit', () async {
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('http://127.0.0.1:5572/'),
        httpClient: mock(),
      );
      await c.quit();
      // Nothing was sent - in particular not core/quit, which would take an
      // engine away from whoever else is using it.
      expect(calls, isEmpty);
      // And the client is done: using it again says so rather than failing
      // obscurely.
      await expectLater(c.rpc('rc/noop'), throwsA(isA<RcloneException>()));
      expect((await c.status()).state, EngineState.stopped);
    });

    test('a caller-supplied HTTP client is not closed by quit()', () async {
      // Closing it would break the caller's next request through their own
      // client, which they may be using for everything else.
      final shared = mock();
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('http://127.0.0.1:5572/'),
        httpClient: shared,
      );
      await c.quit();
      final res = await shared.post(Uri.parse('http://127.0.0.1:5572/rc/noop'));
      expect(res.statusCode, 200);
    });
  });

  group('status and start', () {
    test('status reports the version the engine gave', () async {
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('http://127.0.0.1:5572/'),
        httpClient: mock(body: const {'version': 'v1.75.1'}),
      );
      final st = await c.status();
      expect(st.state, EngineState.running);
      expect(st.version, 'v1.75.1');
    });

    test('start() is a reachability check that fails loudly', () async {
      final dead = RemoteRcloneClient(
        baseUrl: Uri.parse('http://127.0.0.1:5572/'),
        httpClient: MockClient((req) async => http.Response('nope', 502)),
      );
      await expectLater(
        dead.start(),
        throwsA(
          isA<RcloneException>().having(
            (e) => e.message,
            'message',
            contains('no engine answered'),
          ),
        ),
      );
    });

    test('objectRef points at the engine\'s own serve route', () {
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('http://127.0.0.1:5572/'),
        authorization: basicAuth('user', 'pass'),
        httpClient: mock(),
      );
      final ref = c.objectRef('gdrive:', 'papers/a b.pdf');
      expect(ref.url, 'http://127.0.0.1:5572/[gdrive:]/papers/a%20b.pdf');
      expect(ref.headers['Authorization'], isNotNull);
    });
  });

  test(
    'the typed API works over it, because it is just an RcloneClient',
    () async {
      final c = RemoteRcloneClient(
        baseUrl: Uri.parse('http://127.0.0.1:5572/'),
        httpClient: mock(
          body: const {
            'list': [
              {
                'Name': 'a.pdf',
                'Path': 'papers/a.pdf',
                'IsDir': false,
                'Size': 3,
              },
            ],
          },
        ),
      );
      final files = await RcApi(c).operations.list('gdrive:', 'papers');
      expect(files.single.name, 'a.pdf');
      expect(calls.single.url.path, '/operations/list');
    },
  );
}
