@TestOn('vm')
library;

import 'dart:io';

import 'package:airclone/src/rclone/ffi_rclone_client.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live integration against a real, locally-built librclone. OPT-IN: set
/// `AIRCLONE_LIBRCLONE` to the absolute path of a built
/// `librclone.dll`/`.dylib`/`.so` and ensure its runtime deps are resolvable
/// (on Windows, put the mingw bin on PATH). Skipped
/// everywhere the env var is unset — so CI (no native lib) stays green and this
/// never destabilizes the pure suite.
///
/// Run locally, e.g.:
///   $env:PATH = "C:\Users\<you>\tools\mingw64\bin;$env:PATH"
///   $env:AIRCLONE_LIBRCLONE = "C:\path\to\librclone.dll"
///   flutter test test/librclone_integration_test.dart
void main() {
  final libPath = Platform.environment['AIRCLONE_LIBRCLONE'];
  final skip = (libPath == null || libPath.isEmpty)
      ? 'set AIRCLONE_LIBRCLONE to a built librclone to run'
      : (!File(libPath).existsSync()
            ? 'librclone not found at $libPath'
            : false);

  group('FfiRcloneClient (live librclone)', () {
    late FfiRcloneClient client;

    setUp(() => client = FfiRcloneClient(libraryPath: libPath!));
    tearDown(() async => client.quit());

    test(
      'start() brings the in-process engine up and reports a version',
      () async {
        await client.start();
        final st = await client.status();
        expect(st.state, EngineState.running);
        expect(st.version, isNotNull);
        expect(st.version, contains('1.74'));
      },
    );

    test(
      'rpc round-trips: core/version, rc/noop echo, config/listremotes',
      () async {
        await client.start();

        final version = await client.rpc('core/version');
        expect(version['version'], isNotNull);

        final echo = await client.rpc('rc/noop', {'ping': 'pong'});
        expect(echo['ping'], 'pong');

        // Reads the same config the CLI would — shape check only (list may be empty).
        final remotes = await client.rpc('config/listremotes');
        expect(remotes['remotes'], isA<List<dynamic>>());
      },
    );

    test(
      'a bad method surfaces as an RcloneException with a status code',
      () async {
        await client.start();
        await expectLater(
          client.rpc('no/suchmethod'),
          throwsA(
            isA<RcloneException>().having(
              (e) => e.statusCode,
              'statusCode',
              isNot(anyOf(200, isNull)),
            ),
          ),
        );
      },
    );

    test('restart() tears down and brings the engine back up', () async {
      await client.start();
      await client.restart();
      final st = await client.status();
      expect(st.state, EngineState.running);
    });
  }, skip: skip);

  group('FfiRcloneClient objectRef bridge (live librclone)', () {
    test('serves object bytes over loopback — full + Range', () async {
      final srcDir = await Directory.systemTemp.createTemp('airclone-src');
      final cacheDir = await Directory.systemTemp.createTemp('airclone-cache');
      final data = List<int>.generate(5000, (i) => i % 256);
      await File(
        '${srcDir.path}${Platform.pathSeparator}blob.bin',
      ).writeAsBytes(data);

      final client = FfiRcloneClient(
        libraryPath: libPath!,
        previewCacheDir: cacheDir.path,
      );
      final http = HttpClient();
      try {
        await client.start();
        // The local backend: fs = the source dir, remote = the file within it.
        final ref = client.objectRef(srcDir.path, 'blob.bin');

        Future<(int, List<int>)> get(String? range) async {
          final req = await http.getUrl(Uri.parse(ref.url));
          ref.headers.forEach(req.headers.set);
          if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
          final resp = await req.close();
          final bytes = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
          return (resp.statusCode, bytes);
        }

        final (fullStatus, fullBytes) = await get(null);
        expect(fullStatus, 200);
        expect(fullBytes, equals(data));

        final (rangeStatus, rangeBytes) = await get('bytes=100-199');
        expect(rangeStatus, 206);
        expect(rangeBytes, equals(data.sublist(100, 200)));

        // Wrong/absent token is rejected.
        final bad = await http.getUrl(Uri.parse(ref.url));
        final badResp = await bad.close();
        expect(badResp.statusCode, HttpStatus.forbidden);
      } finally {
        http.close(force: true);
        await client.quit();
        await srcDir.delete(recursive: true);
        await cacheDir.delete(recursive: true);
      }
    });
  }, skip: skip);
}
