/// The `airclone --webui` entrypoint: run the engine and the Web UI, with no
/// window.
///
/// This is the headless-server shape of Airclone. It boots the same engine the
/// GUI would, starts [WebUiServer], prints how to reach it, and then stays up
/// until the process is signalled. Nothing is rendered locally — the interface
/// is served to whatever browser connects.
///
/// It deliberately mirrors `headless/headless_runner.dart`: same binding setup,
/// same `ProviderContainer`, and the *same* unattended engine boot, so an
/// encrypted config is unlocked from the OS vault here exactly as it is for a
/// scheduled task. A host that reboots at 3am must come back serving.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../headless/headless_runner.dart' show startEngineUnattended;
import '../state/engine_controller.dart';
import 'webui_assets.dart';
import 'webui_credentials.dart';
import 'webui_options.dart';
import 'webui_server.dart';

/// Started and serving.
const int kWebUiExitOk = 0;

/// Could not start: bad flags, no engine, or the port is taken. Matches the
/// headless runner's `kExitCannotStart` so one systemd unit can treat "2" as
/// "misconfigured, do not restart-loop me".
const int kWebUiExitCannotStart = 2;

/// Runs the Web UI until the process is terminated. Never returns normally.
Future<void> runWebUi(List<String> args) async {
  final code = await _run(args);
  // Only reached on a startup failure; a successful run parks forever below.
  exit(code);
}

Future<int> _run(List<String> args) async {
  final parsed = parseWebUiArgs(args);
  if (!parsed.ok) {
    for (final e in parsed.errors) {
      stderr.writeln('airclone: $e');
    }
    return kWebUiExitCannotStart;
  }
  final options = parsed.options;

  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();

  // Same hydration sync-point the headless runner uses: the engine reads saved
  // flags and the config-path override out of SharedPreferences during
  // bootstrap, and an un-hydrated read would silently start an engine the
  // operator did not configure.
  await SharedPreferences.getInstance();

  final startError = await startEngineUnattended(container);
  if (startError != null) {
    stderr.writeln('airclone: cannot start the Web UI — $startError');
    container.dispose();
    return kWebUiExitCannotStart;
  }

  final supportDir = await getApplicationSupportDirectory();
  final envPath =
      '${supportDir.path}${Platform.pathSeparator}$kWebUiEnvFileName';
  final creds = await loadOrCreateCredentials(
    envFilePath: envPath,
    environment: Platform.environment,
  );

  final server = WebUiServer(
    options: options,
    credentials: creds.credentials,
    engineClient: () => container.read(engineControllerProvider).client!,
    bundle: resolveWebUiBundle(),
    log: _stdoutSink,
    tlsDir: '${supportDir.path}${Platform.pathSeparator}webui',
  );

  try {
    await server.start();
  } on SocketException catch (e) {
    stderr.writeln(
      'airclone: could not listen on ${options.bindAddress}:${options.port} '
      '— ${e.osError?.message ?? e.message}. '
      'Another program may already be using that port; pass '
      '$kWebUiPortFlag to choose a different one.',
    );
    await container.read(engineControllerProvider).client?.quit();
    container.dispose();
    return kWebUiExitCannotStart;
  }

  _announce(options, creds, envPath);

  // Stop cleanly on Ctrl-C and on the TERM a service manager sends, so the
  // engine child is not orphaned. (SIGTERM is not deliverable on Windows;
  // watching it there throws, so it is guarded.)
  final shutdown = Completer<void>();
  void handle(ProcessSignal signal) {
    if (shutdown.isCompleted) return;
    stdout.writeln('airclone: ${signal.toString()} received, stopping…');
    shutdown.complete();
  }

  ProcessSignal.sigint.watch().listen(handle);
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(handle);
  }

  await shutdown.future;
  await server.stop();
  try {
    await container.read(engineControllerProvider).client?.quit();
  } catch (_) {
    // Best-effort: we are on the way out either way.
  }
  container.dispose();
  exit(kWebUiExitOk);
}

/// Prints the one block of text an operator actually needs.
///
/// The credentials are printed **only when they were just generated or could
/// not be saved**. Echoing a password on every start would spray it into
/// journald, screen sessions and scrollback forever; printing it once, at the
/// moment it is created and cannot be recovered any other way, is the whole
/// point. Every other run points at the file instead.
void _announce(
  WebUiOptions options,
  WebUiCredentialResult creds,
  String envPath,
) {
  stdout
    ..writeln('')
    ..writeln('  Airclone Web UI')
    ..writeln('  ${options.displayUrl}');
  if (!options.isLoopback) {
    stdout.writeln(
      '  Listening on ${options.bindAddress} — reachable from the network.',
    );
  }
  stdout.writeln('');
  switch (creds.source) {
    case WebUiCredentialSource.generated:
      stdout
        ..writeln('  A password was generated for you:')
        ..writeln('')
        ..writeln('    username: ${creds.credentials.username}')
        ..writeln('    password: ${creds.credentials.password}')
        ..writeln('')
        ..writeln('  Saved to $envPath')
        ..writeln('  Delete that file to generate a new one.');
    case WebUiCredentialSource.file:
      stdout
        ..writeln('  Sign in as "${creds.credentials.username}".')
        ..writeln('  The password is in $envPath');
    case WebUiCredentialSource.environment:
      stdout.writeln(
        '  Sign in as "${creds.credentials.username}" using the password from '
        '$kWebUiPasswordEnv.',
      );
  }
  final warning = creds.warning;
  if (warning != null) {
    stdout
      ..writeln('')
      ..writeln('  ! $warning');
  }
  stdout.writeln('');
}

void _stdoutSink(WebUiLogLevel level, String message, {Object? detail}) {
  final prefix = switch (level) {
    WebUiLogLevel.info => 'airclone',
    WebUiLogLevel.warning => 'airclone: warning',
    WebUiLogLevel.error => 'airclone: error',
  };
  final sink = level == WebUiLogLevel.error ? stderr : stdout;
  sink.writeln('$prefix: $message');
  if (detail != null) sink.writeln('  $detail');
}
