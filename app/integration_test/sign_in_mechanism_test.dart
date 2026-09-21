import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The guided sign-in mechanism, running inside a real Airclone process on a
/// real device or simulator.
///
/// **Why this exists.** Unit tests prove the driver sends the right calls, and
/// `librclone_integration_test.dart` proves rclone answers them on the desktop
/// OSes. Neither can speak for iOS, where librclone is a STATICALLY LINKED
/// c-archive rather than a loadable library, and where a loopback listener is
/// the thing most likely to be refused. This runs the mechanism where it will
/// actually run.
///
/// What it proves, end to end, in-process:
///   * `config/create` runs as an async job and the engine keeps answering
///   * `config/oauthstatus` hands back a usable auth URL
///   * the loopback listener the provider redirects to is really bound
///   * `config/oauthstop` ends the flow and frees the port
///
/// What it cannot prove: the token exchange. That needs a real account and a
/// person at a consent screen, and Google blocks automating it. Everything on
/// our side of that redirect is covered here.
///
/// It touches NO existing configuration: the engine it starts is given its own
/// config file in a temp directory, which it deletes.
///
/// Run: `flutter test integration_test/sign_in_mechanism_test.dart -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a sign-in can start, be seen, and be cancelled', (tester) async {
    final tmp = await Directory.systemTemp.createTemp('airclone-signin');
    // An empty libraryPath is the sentinel for "statically linked into this
    // executable", which is the only shape iOS has.
    final libPath = librcloneIsStaticallyLinked(Platform.operatingSystem)
        ? ''
        : defaultLibrclonePath();
    final client = FfiRcloneClient(
      libraryPath: libPath,
      configPath: '${tmp.path}${Platform.pathSeparator}rclone.conf',
    );

    try {
      await client.start();
      expect((await client.status()).state, EngineState.running);
      expect(
        (await client.rpc('config/oauthstatus'))['status'],
        'stopped',
        reason: 'nothing should be waiting before we start',
      );

      final started = await client.rpc('config/create', {
        'name': 'signinprobe',
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
            'a blocking create would freeze the single worker isolate for as '
            'long as the sign-in takes',
      );

      Uri? url;
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        final status = await client.rpc('config/oauthstatus');
        if (status['status'] == 'running') {
          final raw = status['authUrl'];
          url = raw is String ? asAuthUrl(raw) : null;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      expect(url, isNotNull, reason: 'no usable auth URL was reported');
      expect(url!.host, kOAuthHost);
      expect(url.port, kOAuthPort);

      // The engine is still answering while the sign-in waits.
      expect((await client.rpc('core/version'))['version'], isNotNull);

      // The listener is really bound. On a sandboxed or entitlement-restricted
      // platform this is the step that fails.
      final probe = await Socket.connect(
        kOAuthHost,
        kOAuthPort,
        timeout: const Duration(seconds: 5),
      );
      await probe.close();

      expect(await cancelOAuth(client), isTrue);

      Map<String, dynamic> job = const {};
      final endBy = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(endBy)) {
        job = await client.rpc('job/status', {'jobid': jobid});
        if (job['finished'] == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(job['finished'], isTrue, reason: 'the cancelled job never ended');
      expect((await client.rpc('config/oauthstatus'))['status'], 'stopped');
    } finally {
      try {
        await cancelOAuth(client);
      } catch (_) {
        /* best effort: the port must not be left held */
      }
      await client.quit();
      await tmp.delete(recursive: true);
    }
  });
}
