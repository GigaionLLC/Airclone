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
        // Shape, not a pinned version. This test's job is to prove the FFI
        // round-trip works against whatever librclone was built; ci.yml's
        // rclone-pin job is what enforces the pin itself. Asserting a
        // hardcoded minor here just breaks on every bump — it did exactly
        // that on v1.74 -> v1.75, failing all three OS legs of
        // librclone.yml while the build and every other check passed.
        expect(st.version, matches(RegExp(r'^v?\d+\.\d+\.\d+')));
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

    test('_async sync/copy round-trips in-process: jobid → job/status → success '
        '(the Phase-4 RC-method console substrate)', () async {
      // The load-bearing assumption of the FFI RC-method console: _async + the
      // process-global jobs map + job/status work in-process via librclone,
      // exactly as TransferService relies on. Proven here against a real lib
      // with the local backend (fs = a directory path).
      final src = await Directory.systemTemp.createTemp('airclone-async-src');
      final dst = await Directory.systemTemp.createTemp('airclone-async-dst');
      await File(
        '${src.path}${Platform.pathSeparator}hello.txt',
      ).writeAsString('phase-4');
      try {
        await client.start();
        final res = await client.rpc('sync/copy', {
          'srcFs': src.path,
          'dstFs': dst.path,
          '_async': true,
          '_group': 'airclone/test',
        });
        final jobid = res['jobid'];
        expect(
          jobid,
          isA<num>(),
          reason: 'in-process _async must return a jobid',
        );

        // Poll job/status like JobsController._poll does, until finished.
        Map<String, dynamic> status = const {};
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(deadline)) {
          status = await client.rpc('job/status', {'jobid': jobid});
          if (status['finished'] == true) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(status['finished'], true, reason: 'job never finished');
        expect(status['success'], true, reason: 'job/status.success');

        // core/stats scoped to the group answers in-process too.
        final stats = await client.rpc('core/stats', {
          'group': 'airclone/test',
        });
        expect(stats, isA<Map<String, dynamic>>());

        // The file actually copied.
        expect(
          File('${dst.path}${Platform.pathSeparator}hello.txt').existsSync(),
          isTrue,
        );
      } finally {
        await src.delete(recursive: true);
        await dst.delete(recursive: true);
      }
    });

    test('two SEPARATE engines can run back-to-back in one process', () async {
      // Mirrors EngineController's encryption probe: a throwaway FfiRcloneClient
      // (config/paths) is started + quit, THEN the real engine starts. Each is a
      // fresh LibrcloneEngine (its own worker isolate) doing Initialize/Finalize
      // against the same in-process Go runtime.
      final lib = libPath!;
      final probe = FfiRcloneClient(libraryPath: lib);
      await probe.start();
      final paths = await probe.rpc('config/paths');
      expect(paths['config'], isA<String>());
      await probe.quit();

      final real = FfiRcloneClient(libraryPath: lib);
      await real.start();
      final st = await real.status();
      expect(st.state, EngineState.running);
      await real.quit();
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
