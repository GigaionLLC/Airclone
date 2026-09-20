@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

/// Live integration against a real `rclone` binary — the spawned-engine half of
/// this package, and the counterpart of `librclone_integration_test.dart`.
/// OPT-IN: set `AIRCLONE_RCLONE` to the absolute path of an `rclone`
/// executable. Skipped when the var is unset, so the pure suite stays green on
/// a machine that has no binary.
///
/// Run locally, e.g.:
///   $env:AIRCLONE_RCLONE = "C:\Program Files\Airclone\rclone.exe"
///   dart test test/rcd_integration_test.dart
///
/// Every client here gets its own `--config` inside a temp directory, so the
/// test never reads, writes or locks the config of whoever is running it.
void main() {
  final rclonePath = Platform.environment['AIRCLONE_RCLONE'];
  final skip = (rclonePath == null || rclonePath.isEmpty)
      ? 'set AIRCLONE_RCLONE to an rclone binary to run'
      : (!File(rclonePath).existsSync()
            ? 'rclone not found at $rclonePath'
            : false);

  // Never 'airclone': the reaper kills by tag, and a test run must not be able
  // to reach an Airclone engine running on the same machine. This is the rule
  // the README states, exercised here.
  const tag = 'rctest';

  String sep(String dir, String name) => '$dir${Platform.pathSeparator}$name';

  group('HttpRcloneClient (live rclone rcd)', () {
    late Directory home;
    late HttpRcloneClient client;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('airclone-rc-rcd');
      client = HttpRcloneClient(
        instanceTag: tag,
        rclonePath: rclonePath ?? 'rclone',
        configPath: sep(home.path, 'rclone.conf'),
      );
    });

    tearDown(() async {
      await client.quit();
      try {
        await home.delete(recursive: true);
      } catch (_) {
        // Windows can still hold the config open for a beat after the child
        // exits; a leftover temp dir is not a test failure.
      }
    });

    test('start() spawns the engine and reports a version', () async {
      await client.start();
      final st = await client.status();
      expect(st.state, EngineState.running);
      // Shape, not a pinned version — same reasoning as the librclone test:
      // ci.yml's rclone-pin job owns the pin, and asserting a minor here just
      // breaks on every bump.
      expect(st.version, matches(RegExp(r'^v?\d+\.\d+\.\d+')));
    });

    test('the child really got our --config, not the caller\'s', () async {
      await client.start();
      final path = await client.engineConfigPath();
      expect(path, sep(home.path, 'rclone.conf'));

      // And it is an empty config, which is the proof that this run cannot see
      // the remotes of whoever is running the test.
      final remotes = await client.rpc('config/listremotes');
      expect(remotes['remotes'], anyOf(isNull, isEmpty));
    });

    test('rpc round-trips: core/version, rc/noop echo', () async {
      await client.start();

      final version = await client.rpc('core/version');
      expect(version['version'], isNotNull);

      final echo = await client.rpc('rc/noop', {'ping': 'pong'});
      expect(echo['ping'], 'pong');
    });

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

    test('restart() kills the child and brings a fresh one up', () async {
      await client.start();
      await client.restart();
      final st = await client.status();
      expect(st.state, EngineState.running);
    });

    test(
      '_async sync/copy round-trips: jobid → job/status → the file lands',
      () async {
        final src = await Directory.systemTemp.createTemp('airclone-rcd-src');
        final dst = await Directory.systemTemp.createTemp('airclone-rcd-dst');
        await File(sep(src.path, 'hello.txt')).writeAsString('spawned');
        try {
          await client.start();
          final res = await client.rpc('sync/copy', {
            'srcFs': src.path,
            'dstFs': dst.path,
            '_async': true,
            '_group': 'rctest/copy',
          });
          final jobid = res['jobid'];
          expect(jobid, isA<num>(), reason: '_async must return a jobid');

          // Poll the way JobsController does.
          Map<String, dynamic> status = const {};
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(deadline)) {
            status = await client.rpc('job/status', {'jobid': jobid});
            if (status['finished'] == true) break;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(status['finished'], true, reason: 'job never finished');
          expect(status['success'], true, reason: 'job/status.success');

          final stats = await client.rpc('core/stats', {
            'group': 'rctest/copy',
          });
          expect(stats, isA<Map<String, dynamic>>());

          expect(File(sep(dst.path, 'hello.txt')).existsSync(), isTrue);
        } finally {
          await src.delete(recursive: true);
          await dst.delete(recursive: true);
        }
      },
    );

    test(
      'objectRef serves bytes over loopback — full, Range, and no auth',
      () async {
        final srcDir = await Directory.systemTemp.createTemp(
          'airclone-rcd-obj',
        );
        final data = List<int>.generate(5000, (i) => i % 256);
        await File(sep(srcDir.path, 'blob.bin')).writeAsBytes(data);
        final http = HttpClient();
        try {
          await client.start();
          final ref = client.objectRef(srcDir.path, 'blob.bin');

          Future<(int, List<int>)> get(String? range) async {
            final req = await http.getUrl(Uri.parse(ref.url));
            ref.headers.forEach(req.headers.set);
            if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
            final resp = await req.close();
            final bytes = await resp.fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            );
            return (resp.statusCode, bytes);
          }

          final (fullStatus, fullBytes) = await get(null);
          expect(fullStatus, 200);
          expect(fullBytes, equals(data));

          final (rangeStatus, rangeBytes) = await get('bytes=100-199');
          expect(rangeStatus, 206);
          expect(rangeBytes, equals(data.sublist(100, 200)));

          // The rc listener is on loopback, but loopback is not a permission:
          // without the per-session Basic credentials it answers 401.
          final bare = await http.getUrl(Uri.parse(ref.url));
          final bareResp = await bare.close();
          await bareResp.drain<void>();
          expect(bareResp.statusCode, HttpStatus.unauthorized);
        } finally {
          http.close(force: true);
          await srcDir.delete(recursive: true);
        }
      },
    );

    test(
      'putObject streams an upload through the hand-built multipart body',
      () async {
        final dst = await Directory.systemTemp.createTemp('airclone-rcd-up');
        final data = List<int>.generate(70000, (i) => (i * 7) % 256);
        try {
          await client.start();
          await client.putObject(
            dst.path,
            'sub/uploaded.bin',
            Stream<List<int>>.fromIterable([data]),
            length: data.length,
          );
          final landed = File(sep(sep(dst.path, 'sub'), 'uploaded.bin'));
          expect(landed.existsSync(), isTrue, reason: 'upload did not land');
          expect(await landed.readAsBytes(), equals(data));
        } finally {
          await dst.delete(recursive: true);
        }
      },
    );

    test('commandStream pipes core/command output line by line', () async {
      await client.start();
      final lines = await (await client.commandStream(
        'version',
        const [],
      )).take(4).toList();
      expect(
        lines.join('\n'),
        contains('rclone v'),
        reason: 'core/command STREAM must reach us as lines',
      );
    });

    test('at -vv the rc password never reaches the output', () async {
      // The leak this guards against is not hypothetical, and it is more
      // direct than the Authorization header everyone expects: at -vv rclone
      // echoes the password it read out of RCLONE_RC_PASS, in three separate
      // lines, before it has served a single request. Without redaction this
      // test prints the real token - it was written by watching it happen.
      // echoEngineLines is the loudest path there is, so if anything is
      // redacted, it is redacted here.
      final printed = <String>[];
      final loud = HttpRcloneClient(
        instanceTag: tag,
        rclonePath: rclonePath ?? 'rclone',
        configPath: sep(home.path, 'loud.conf'),
        extraArgs: const ['-vv', '--dump', 'headers'],
        echoEngineLines: true,
      );
      await runZoned(
        () async {
          await loud.start();
          await loud.rpc('rc/noop', {'ping': 'pong'});
          await loud.rpc('core/version');
          // The child writes on its own schedule; give it a moment to drain.
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await loud.quit();
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      final all = printed.join('\n');
      expect(
        printed,
        isNotEmpty,
        reason: '-vv produced no output at all - the test proves nothing',
      );
      // What rclone actually echoes is not the Authorization header (rcd
      // dumps its OUTBOUND backend traffic, not the rc calls made to it) but
      // something more direct: the password it reads out of the environment,
      // three times, at DEBUG and INFO. Those lines are the leak, and their
      // redacted form is what must appear.
      expect(
        all,
        contains('--pass <redacted>'),
        reason:
            'the authenticated-user line did not appear, so this test is '
            'not exercising what it claims',
      );
      expect(all, contains('rc_pass="<redacted>"'));
      // And the token itself is nowhere: _randomToken is 24 random bytes as
      // base64url, so anything that long in a password position is the real
      // one having walked straight through.
      expect(
        RegExp(
          r'(rc_pass="|--pass |--rc-pass )[A-Za-z0-9_-]{12,}',
        ).hasMatch(all),
        isFalse,
        reason: 'an un-redacted rc password reached the output',
      );
    });

    test('quit() leaves no reap marker behind for the next launch', () async {
      await client.start();
      final marker = File(
        sep(Directory.systemTemp.path, '${tag}_rcd_$pid.pid'),
      );
      expect(
        marker.existsSync(),
        isTrue,
        reason: 'a running engine must be reapable after a hard exit',
      );
      final markerPid = int.parse((await marker.readAsString()).trim());
      expect(markerPid, greaterThan(0));

      await client.quit();
      expect(
        marker.existsSync(),
        isFalse,
        reason: 'a clean shutdown must not leave a PID for a future reap',
      );
      // And the PID it named is gone: no orphaned rcd is still listening.
      expect(_processAlive(markerPid), isFalse, reason: 'rcd outlived quit()');
    });
  }, skip: skip);
}

/// True when [processPid] still exists. Dart has no signal 0, so each platform
/// gets asked the way it answers: `tasklist` on Windows, `/proc` on Linux,
/// `kill -0` on anything else.
bool _processAlive(int processPid) {
  if (Platform.isWindows) {
    final res = Process.runSync('tasklist', [
      '/FI',
      'PID eq $processPid',
      '/NH',
    ], stdoutEncoding: utf8);
    return '${res.stdout}'.contains('$processPid');
  }
  if (Platform.isLinux) return Directory('/proc/$processPid').existsSync();
  final res = Process.runSync('kill', ['-0', '$processPid']);
  return res.exitCode == 0;
}
