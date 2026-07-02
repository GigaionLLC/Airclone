import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../rclone/http_rclone_client.dart';
import '../rclone/rclone_client.dart';
import '../rclone/rclone_engine.dart';
import 'cache_crypto.dart';
import 'engine_flags.dart';

enum EnginePhase {
  idle,
  locating,
  notInstalled,
  needsPassword,
  provisioning,
  starting,
  ready,
  error,
}

@immutable
class EngineUi {
  const EngineUi({
    required this.phase,
    this.version,
    this.message,
    this.client,
  });

  final EnginePhase phase;
  final String? version;
  final String? message;
  final RcloneClient? client;

  bool get isReady => phase == EnginePhase.ready && client != null;

  EngineUi copyWith({
    EnginePhase? phase,
    String? version,
    String? message,
    RcloneClient? client,
  }) => EngineUi(
    phase: phase ?? this.phase,
    version: version ?? this.version,
    message: message,
    client: client ?? this.client,
  );
}

/// Owns the rclone engine lifecycle: locate/provision the binary, detect an
/// encrypted config and gate on its password, spawn `rcd`, and expose the live
/// [RcloneClient]. The rest of the app reads `state.client`.
class EngineController extends Notifier<EngineUi> {
  String? _rclonePath;

  @override
  EngineUi build() {
    ref.onDispose(() => state.client?.quit());
    return const EngineUi(phase: EnginePhase.idle);
  }

  /// Locate an existing rclone and start; otherwise surface "not installed".
  Future<void> bootstrap() async {
    if (state.phase == EnginePhase.locating || state.isReady) return;
    state = const EngineUi(phase: EnginePhase.locating);
    final path = await RcloneEngine.findExisting();
    if (path == null) {
      // On Android the engine ships inside the APK — its absence is a broken
      // build, not something a download can fix.
      state = Platform.isAndroid
          ? const EngineUi(
              phase: EnginePhase.error,
              message:
                  'This build is missing the bundled rclone engine. '
                  'Please reinstall the app.',
            )
          : const EngineUi(
              phase: EnginePhase.notInstalled,
              message: 'The rclone engine was not found.',
            );
      return;
    }
    await _proceedWith(path);
  }

  /// Android runs the engine sandboxed: the config lives in the app's own
  /// storage (passed via `--config`), temp files go to the app cache (there is
  /// no /tmp), and `local` writes skip chtimes, which Android storage rejects.
  /// Desktop returns nulls/empty — rclone's own defaults are right there.
  Future<(String?, Map<String, String>)> _platformSetup() async {
    if (!Platform.isAndroid) return (null, const <String, String>{});
    final support = await getApplicationSupportDirectory();
    final cache = await getTemporaryDirectory();
    return (
      '${support.path}/rclone.conf',
      <String, String>{
        'TMPDIR': cache.path,
        'HOME': support.path,
        // Without this, rclone derives its cache dir from HOME and VFS/preview
        // cache data lands in persistent app storage the OS can't reclaim.
        'XDG_CACHE_HOME': cache.path,
        'RCLONE_LOCAL_NO_SET_MODTIME': 'true',
      },
    );
  }

  /// Download + verify rclone, then start. Triggered from the "not installed" UI.
  Future<void> installAndStart() async {
    state = const EngineUi(
      phase: EnginePhase.provisioning,
      message: 'Preparing…',
    );
    try {
      final path = await RcloneEngine.downloadLatest(
        onStatus: (m) =>
            state = state.copyWith(phase: EnginePhase.provisioning, message: m),
      );
      await _proceedWith(path);
    } catch (e) {
      state = EngineUi(phase: EnginePhase.error, message: '$e');
    }
  }

  /// Stop and re-spawn the engine with current settings (e.g. after changing the
  /// global engine flags). Reuses the unlocked config password if one is held.
  Future<void> restartEngine() async {
    final path = _rclonePath;
    if (path == null) return;
    final password = ref.read(cachePassphraseProvider);
    await state.client?.quit();
    await _startWith(path, password: password);
  }

  /// Provided by the password gate when the config is encrypted.
  Future<void> unlockAndStart(String password) async {
    final path = _rclonePath;
    if (path == null) return bootstrap();
    await _startWith(path, password: password);
  }

  /// After we have a binary: gate on the config password if encrypted, else start.
  Future<void> _proceedWith(String rclonePath) async {
    _rclonePath = rclonePath;
    final (configPath, _) = await _platformSetup();
    if (await RcloneEngine.isConfigEncrypted(
      rclonePath,
      configPath: configPath,
    )) {
      state = const EngineUi(
        phase: EnginePhase.needsPassword,
        message:
            'Your rclone config is encrypted. Enter its password to unlock.',
      );
      return;
    }
    await _startWith(rclonePath);
  }

  Future<void> _startWith(String rclonePath, {String? password}) async {
    state = const EngineUi(
      phase: EnginePhase.starting,
      message: 'Starting engine…',
    );
    final (configPath, extraEnv) = await _platformSetup();
    final client = HttpRcloneClient(
      rclonePath: rclonePath,
      configPath: configPath,
      configPassword: password,
      extraArgs: parseEngineFlags(ref.read(engineFlagsProvider)),
      extraEnv: extraEnv,
    );
    // If rcd dies out from under us (crash, Android LMK), don't keep showing
    // a "ready" engine wired to a corpse — surface it with a restart path.
    client.onDied = () {
      if (state.client == client) {
        state = const EngineUi(
          phase: EnginePhase.error,
          message: 'The engine stopped unexpectedly. Start it again to '
              'continue.',
        );
      }
    };
    try {
      await client.start();
      final status = await client.status();
      // Bind the at-rest cache key to the config password (null when the config
      // is unencrypted → the cache falls back to a per-remote-name key).
      ref.read(cachePassphraseProvider.notifier).state = password;
      state = EngineUi(
        phase: EnginePhase.ready,
        version: status.version,
        client: client,
      );
    } catch (e) {
      await client.quit();
      // If we were unlocking, the likeliest cause is a wrong password.
      if (password != null) {
        state = const EngineUi(
          phase: EnginePhase.needsPassword,
          message:
              'Incorrect password (or the engine failed to start). Try again.',
        );
      } else {
        state = EngineUi(phase: EnginePhase.error, message: '$e');
      }
    }
  }
}

final engineControllerProvider = NotifierProvider<EngineController, EngineUi>(
  EngineController.new,
);
