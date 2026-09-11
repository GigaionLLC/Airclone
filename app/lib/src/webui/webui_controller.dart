/// Owns the Web UI server's lifecycle when Airclone is running with a window.
///
/// The same [WebUiServer] the `--webui` host runs, started from Settings
/// instead of from a command line. One difference, and it is the reason this
/// file exists rather than the GUI calling the runner: the log goes to the
/// in-app diagnostics channel here, not to stdout, because there is a person
/// present who can read it.
///
/// Desktop only. A phone is not the machine you point a browser at, and the web
/// bundle is not shipped in the mobile builds.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/diagnostics.dart';
import '../state/engine_controller.dart';
import '../state/host_platform.dart';
import 'webui_assets.dart';
import 'webui_credentials.dart';
import 'webui_options.dart';
import 'webui_server.dart';

/// Diagnostics area tag for everything this feature logs.
const String kWebUiDiagArea = 'webui';

const String _prefBind = 'webui.bind';
const String _prefPort = 'webui.port';

/// What Settings needs to render.
@immutable
class WebUiUi {
  const WebUiUi({
    required this.options,
    this.running = false,
    this.busy = false,
    this.url,
    this.username,
    this.password,
    this.credentialSource,
    this.message,
    this.bundleMissing = false,
  });

  final WebUiOptions options;
  final bool running;

  /// A start or stop is in flight; the toggle is disabled.
  final bool busy;

  final String? url;
  final String? username;

  /// Shown only behind an explicit reveal in the UI.
  final String? password;

  final WebUiCredentialSource? credentialSource;

  /// Last error or notice, for the panel.
  final String? message;

  /// True when the server would start but has no interface to serve.
  final bool bundleMissing;

  /// Whether to warn that this is reachable beyond the machine.
  bool get exposed => running && !options.isLoopback;

  WebUiUi copyWith({
    WebUiOptions? options,
    bool? running,
    bool? busy,
    String? url,
    String? username,
    String? password,
    WebUiCredentialSource? credentialSource,
    String? message,
    bool? bundleMissing,
  }) => WebUiUi(
    options: options ?? this.options,
    running: running ?? this.running,
    busy: busy ?? this.busy,
    url: url ?? this.url,
    username: username ?? this.username,
    password: password ?? this.password,
    credentialSource: credentialSource ?? this.credentialSource,
    message: message,
    bundleMissing: bundleMissing ?? this.bundleMissing,
  );
}

class WebUiController extends Notifier<WebUiUi> {
  WebUiServer? _server;
  bool _loaded = false;

  @override
  WebUiUi build() {
    ref.onDispose(() {
      // The window is closing; do not leave a socket listening behind it.
      _server?.stop();
      _server = null;
    });
    return const WebUiUi(options: WebUiOptions());
  }

  /// Hydrates the saved bind address and port. Safe to call repeatedly.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final bind = prefs.getString(_prefBind);
    final port = prefs.getInt(_prefPort);
    state = state.copyWith(
      options: WebUiOptions(
        bindAddress: (bind != null && resolveBindAddress(bind) != null)
            ? bind
            : kDefaultWebUiBind,
        port: (port != null && port > 0 && port < 65536)
            ? port
            : kDefaultWebUiPort,
      ),
    );
  }

  /// Saves the address and port to use next time the server starts.
  ///
  /// Rejects an address that is not an IP rather than storing it: a saved bad
  /// value would fail at every future start, far from where it was typed.
  Future<String?> configure({String? bindAddress, int? port}) async {
    var options = state.options;
    if (bindAddress != null) {
      final resolved = resolveBindAddress(bindAddress);
      if (resolved == null) {
        return '"$bindAddress" is not an IP address. Use this machine\'s '
            'address, $kDefaultWebUiBind for this machine only, or '
            '"$kBindAllAlias" for every network.';
      }
      options = options.copyWith(bindAddress: resolved);
    }
    if (port != null) {
      if (port < 1 || port > 65535) return 'Pick a port between 1 and 65535.';
      options = options.copyWith(port: port);
    }
    state = state.copyWith(options: options);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBind, options.bindAddress);
    await prefs.setInt(_prefPort, options.port);
    return null;
  }

  Future<void> start() async {
    if (state.running || state.busy) return;
    await ensureLoaded();
    state = state.copyWith(busy: true, message: null);
    final diag = ref.read(diagnosticsProvider.notifier);

    final engine = ref.read(engineControllerProvider);
    if (!engine.isReady) {
      state = state.copyWith(
        busy: false,
        message:
            'The rclone engine is not running yet, so there would be nothing '
            'to serve. Wait for it to start and try again.',
      );
      return;
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      final envPath =
          '${supportDir.path}${Platform.pathSeparator}$kWebUiEnvFileName';
      final creds = await loadOrCreateCredentials(
        envFilePath: envPath,
        environment: Platform.environment,
      );
      final bundle = resolveWebUiBundle();
      final server = WebUiServer(
        options: state.options,
        credentials: creds.credentials,
        engineClient: () => ref.read(engineControllerProvider).client!,
        bundle: bundle,
        log: (level, message, {detail}) =>
            _toDiagnostics(diag, level, message, detail),
      );
      await server.start();
      _server = server;
      state = state.copyWith(
        running: true,
        busy: false,
        url: state.options.displayUrl,
        username: creds.credentials.username,
        password: creds.credentials.password,
        credentialSource: creds.source,
        bundleMissing: bundle == null,
        message: creds.warning,
      );
    } on SocketException catch (e) {
      diag.error(
        kWebUiDiagArea,
        'Web UI could not listen on '
        '${state.options.bindAddress}:${state.options.port}',
        detail: e,
      );
      state = state.copyWith(
        busy: false,
        message:
            'Could not listen on ${state.options.bindAddress}:'
            '${state.options.port} — ${e.osError?.message ?? e.message}. '
            'Another program may already be using that port.',
      );
    } catch (e) {
      diag.error(kWebUiDiagArea, 'Web UI failed to start', detail: e);
      state = state.copyWith(busy: false, message: 'Could not start: $e');
    }
  }

  Future<void> stop() async {
    if (!state.running || state.busy) return;
    state = state.copyWith(busy: true);
    await _server?.stop();
    _server = null;
    state = const WebUiUi(
      options: WebUiOptions(),
    ).copyWith(options: state.options);
  }

  /// Issues a new password, signs every session out, and rewrites the env file.
  Future<void> regenerateCredentials() async {
    final diag = ref.read(diagnosticsProvider.notifier);
    try {
      final supportDir = await getApplicationSupportDirectory();
      final envPath =
          '${supportDir.path}${Platform.pathSeparator}$kWebUiEnvFileName';
      // Deleting first is what makes this a rotation rather than a read: the
      // loader returns the EXISTING credentials whenever the file parses.
      final file = File(envPath);
      if (file.existsSync()) await file.delete();
      final creds = await loadOrCreateCredentials(
        envFilePath: envPath,
        environment: const {},
      );
      _server?.rotateCredentials(creds.credentials);
      state = state.copyWith(
        username: creds.credentials.username,
        password: creds.credentials.password,
        credentialSource: creds.source,
        message:
            'A new password was generated. Everyone signed in was signed '
            'out.',
      );
      diag.info(kWebUiDiagArea, 'Web UI credentials regenerated.');
    } catch (e) {
      diag.error(
        kWebUiDiagArea,
        'Could not regenerate Web UI credentials',
        detail: e,
      );
      state = state.copyWith(message: 'Could not write new credentials: $e');
    }
  }

  void _toDiagnostics(
    DiagnosticsLog diag,
    WebUiLogLevel level,
    String message,
    Object? detail,
  ) {
    switch (level) {
      case WebUiLogLevel.info:
        diag.info(kWebUiDiagArea, message, detail: detail);
      case WebUiLogLevel.warning:
        diag.warn(kWebUiDiagArea, message, detail: detail);
      case WebUiLogLevel.error:
        diag.error(kWebUiDiagArea, message, detail: detail);
    }
  }
}

final webUiControllerProvider = NotifierProvider<WebUiController, WebUiUi>(
  WebUiController.new,
);

/// Whether this build can host the Web UI at all.
///
/// Desktop only, and never from the Web UI itself: a browser tab cannot listen
/// on a socket, and letting the served app offer to serve itself would be a
/// confusing thing to put in front of someone.
bool get webUiHostingSupported => !HostPlatform.isWeb && HostPlatform.isDesktop;
