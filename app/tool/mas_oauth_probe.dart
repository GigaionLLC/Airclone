import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';

/// Can a sandboxed Mac App Store build bind the port an OAuth sign-in needs?
///
/// **Why a separate executable.** The App Sandbox is enforced by the code
/// signature plus the entitlement, not by the App Store — so a binary placed
/// INSIDE the signed `Airclone.app` and signed with `MacAppStore.entitlements`
/// gets exactly the sandbox a customer gets. That makes the one MAS question
/// this feature raises answerable without a Mac and without driving a GUI:
/// completing a sign-in means rclone listens on `127.0.0.1:53682` for the
/// provider's redirect, and the sandbox refuses to `listen()` at all without
/// `com.apple.security.network.server`.
///
/// Having the entitlement in the file is not the same as the listener binding.
/// This checks the second thing. If it is ever removed — or if Apple changes
/// what it covers — every Mac App Store copy loses the ability to add a cloud,
/// silently, and nothing else in the pipeline would notice.
///
/// Run from inside the bundle, so [defaultLibrclonePath] resolves
/// `Contents/Frameworks/librclone.dylib` the same way the real app does:
///
///     Airclone.app/Contents/MacOS/mas-oauth-probe
///
/// Exit 0 = the sign-in mechanism works under the sandbox. Non-zero = it does
/// not, and the message says which step failed.
Future<void> main(List<String> args) async {
  exitCode = await _probe(args);
  // The engine leaves its worker isolate alive; nothing here should wait on it.
  exit(exitCode);
}

Future<int> _probe(List<String> args) async {
  final libPath = args.isNotEmpty ? args.first : defaultLibrclonePath();
  stdout.writeln('[probe] librclone: $libPath');
  if (libPath.isNotEmpty && !File(libPath).existsSync()) {
    stdout.writeln('[probe] FAIL: librclone is not where the app looks for it');
    return 2;
  }

  final tmp = await Directory.systemTemp.createTemp('airclone-mas-probe');
  final client = FfiRcloneClient(
    libraryPath: libPath,
    configPath: '${tmp.path}/rclone.conf',
  );

  try {
    await client.start();
    stdout.writeln('[probe] engine up: ${(await client.status()).version}');

    final started = await client.rpc('config/create', {
      'name': 'masprobe',
      'type': 'drive',
      'parameters': {
        'config_shared_client_id': 'true',
        'config_is_local': 'true',
        'config_auth_no_browser': 'true',
      },
      'opt': {'nonInteractive': true, 'obscure': true},
      '_async': true,
    });
    if (started['jobid'] is! num) {
      stdout.writeln('[probe] FAIL: config/create did not run as a job');
      return 3;
    }

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
    if (url == null) {
      stdout.writeln(
        '[probe] FAIL: no auth URL. If the sandbox denied the listener, '
        'rclone never got far enough to report one.',
      );
      return 4;
    }
    stdout.writeln('[probe] auth URL reported on port ${url.port}');

    // The actual question: is the listener reachable under the sandbox?
    try {
      final sock = await Socket.connect(
        kOAuthHost,
        kOAuthPort,
        timeout: const Duration(seconds: 5),
      );
      await sock.close();
      stdout.writeln(
        '[probe] listener on $kOAuthHost:$kOAuthPort is reachable',
      );
    } on SocketException catch (e) {
      stdout.writeln(
        '[probe] FAIL: the sign-in listener is not reachable under the '
        'sandbox — check com.apple.security.network.server. $e',
      );
      return 5;
    }

    final stopped = await cancelOAuth(client);
    stdout.writeln('[probe] cancel: $stopped');
    stdout.writeln('[probe] PASS');
    return 0;
  } catch (e) {
    stdout.writeln('[probe] FAIL: $e');
    return 1;
  } finally {
    try {
      await cancelOAuth(client);
    } catch (_) {
      /* the port must not be left held */
    }
    await client.quit();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {
      /* a temp dir the OS will reclaim */
    }
  }
}
