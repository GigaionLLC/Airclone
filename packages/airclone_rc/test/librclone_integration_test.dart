@TestOn('vm')
library;

import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

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

  /// The guided sign-in, against a REAL librclone on this OS.
  ///
  /// This is the part no unit test with a fake client can prove: that rclone,
  /// running IN THIS PROCESS through dart:ffi, hands back the sign-in URL,
  /// binds the loopback listener the provider redirects to, and lets go of both
  /// when told. On macOS this is the only automated evidence the Apple builds
  /// have — nobody on this project owns a Mac.
  ///
  /// No account, no credentials, and no call to any provider: rclone binds the
  /// listener and waits, and everything here happens on this machine.
  group('guided sign-in mechanism (live librclone)', () {
    late Directory tmp;
    late FfiRcloneClient client;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('airclone-oauth');
      // Its own config file. This creates a remote, and it must never be the
      // developer's or the runner's real one.
      client = FfiRcloneClient(
        libraryPath: libPath!,
        configPath: '${tmp.path}${Platform.pathSeparator}rclone.conf',
      );
    });

    tearDown(() async {
      // Always let go of the port, whatever the test did. A leaked listener
      // would fail every following test with a bind error rather than with
      // whatever actually went wrong.
      try {
        await client.rpc('config/oauthstop');
      } catch (_) {
        /* nothing was running, which is the state we wanted anyway */
      }
      await client.quit();
      await tmp.delete(recursive: true);
    });

    /// Starts a Drive sign-in as an async job, pre-answering everything up to
    /// the OAuth wait. Returns the job id.
    Future<num> beginSignIn() async {
      final started = await client.rpc('config/create', {
        'name': 'oauthprobe',
        'type': 'drive',
        'parameters': {
          'config_shared_client_id': 'true',
          'config_is_local': 'true',
          'config_auth_no_browser': 'true',
        },
        'opt': {'nonInteractive': true, 'obscure': true},
        '_async': true,
      });
      final jobid = started['jobid'];
      expect(
        jobid,
        isA<num>(),
        reason:
            'config/create must run as a job — a blocking one would freeze the '
            'single worker isolate for as long as a sign-in takes',
      );
      return jobid as num;
    }

    Future<Map<String, dynamic>> awaitJob(num jobid) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        final status = await client.rpc('job/status', {'jobid': jobid});
        if (status['finished'] == true) return status;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('the job never finished');
    }

    /// Waits until rclone reports a sign-in is waiting, and returns its URL.
    Future<Uri?> awaitAuthUrl() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        final status = await client.rpc('config/oauthstatus');
        if (status['status'] == 'running') {
          final raw = status['authUrl'];
          // Validated by the same function the app uses, so this also proves
          // that what the app will accept is what rclone actually produces.
          return raw is String ? asAuthUrl(raw) : null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return null;
    }

    test(
      'the auth URL is reported, the port is bound, and stop frees both',
      () async {
        await client.start();
        expect(
          (await client.rpc('config/oauthstatus'))['status'],
          'stopped',
          reason: 'nothing should be waiting before we start',
        );

        final jobid = await beginSignIn();
        final url = await awaitAuthUrl();

        expect(
          url,
          isNotNull,
          reason: 'config/oauthstatus never handed back a usable auth URL',
        );
        expect(url!.host, kOAuthHost);
        expect(url.port, kOAuthPort);
        expect(url.queryParameters['state'], isNotEmpty);

        // The engine is still answering while the sign-in waits. That is the
        // whole reason this runs as a job.
        expect((await client.rpc('core/version'))['version'], isNotNull);

        // The listener the provider would be redirected to is really there.
        final probe = await Socket.connect(
          kOAuthHost,
          kOAuthPort,
          timeout: const Duration(seconds: 5),
        );
        await probe.close();

        await client.rpc('config/oauthstop');

        final status = await awaitJob(jobid);
        expect(
          '${status['error']}',
          contains('cancel'),
          reason: 'the job should end because it was cancelled',
        );
        expect((await client.rpc('config/oauthstatus'))['status'], 'stopped');

        // And the port is free, so a second attempt can bind it.
        await expectLater(
          Socket.connect(
            kOAuthHost,
            kOAuthPort,
            timeout: const Duration(seconds: 2),
          ),
          throwsA(isA<SocketException>()),
          reason:
              'the listener must let go of the port, or the NEXT sign-in '
              'fails to bind',
        );
      },
    );

    test(
      'cancelOAuth() ends a real flow, and says so when there is none',
      () async {
        await client.start();
        // Nothing running: rclone answers HTTP 500 "no oauth authentication is
        // in progress", which is the state cancel wanted, not a failure.
        expect(await cancelOAuth(client), isTrue);

        final jobid = await beginSignIn();
        expect(await awaitAuthUrl(), isNotNull);

        expect(await cancelOAuth(client), isTrue);
        await awaitJob(jobid);
        expect(await cancelOAuth(client), isTrue, reason: 'idempotent');
      },
    );

    test('the pre-1.75 fallback still unblocks a waiting sign-in', () async {
      // Engines older than 1.75 have neither RC method, and the app falls back
      // to a plain GET at the redirect address: rclone pushes a failure onto
      // the same channel the flow is blocked on for any request carrying no
      // code. Exercised because the minimum supported rclone is 1.73.5 and a
      // desktop user may point Airclone at their own binary.
      //
      // It also proves the listener RECEIVES and ACTS ON an inbound request —
      // the redirect leg — without contacting any provider. Completing a real
      // redirect would mean handing a code to Google, which needs an account
      // and a person; this covers everything on our side of that.
      await client.start();
      final jobid = await beginSignIn();
      expect(await awaitAuthUrl(), isNotNull);

      final http = HttpClient();
      try {
        final req = await http.getUrl(
          Uri.parse('http://$kOAuthHost:$kOAuthPort/'),
        );
        final resp = await req.close();
        await resp.drain<void>();
        expect(resp.statusCode, 400, reason: 'a redirect carrying no code');
      } finally {
        http.close(force: true);
      }

      final status = await awaitJob(jobid);
      expect('${status['error']}', isNotEmpty);
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
