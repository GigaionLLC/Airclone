import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/http_rclone_client.dart';
import '../rclone/rclone_client.dart';
import '../rclone/rclone_engine.dart';
import 'cache_crypto.dart';

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
      state = const EngineUi(
        phase: EnginePhase.notInstalled,
        message: 'The rclone engine was not found.',
      );
      return;
    }
    await _proceedWith(path);
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

  /// Provided by the password gate when the config is encrypted.
  Future<void> unlockAndStart(String password) async {
    final path = _rclonePath;
    if (path == null) return bootstrap();
    await _startWith(path, password: password);
  }

  /// After we have a binary: gate on the config password if encrypted, else start.
  Future<void> _proceedWith(String rclonePath) async {
    _rclonePath = rclonePath;
    if (await RcloneEngine.isConfigEncrypted(rclonePath)) {
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
    final client = HttpRcloneClient(
      rclonePath: rclonePath,
      configPassword: password,
    );
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
