import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../rclone/http_rclone_client.dart';
import '../rclone/rclone_client.dart';
import '../rclone/rclone_engine.dart';
import 'cache_crypto.dart';
import 'config_password_vault.dart';
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

  /// Desktop: download the latest verified rclone, repoint the cached path, and
  /// restart the engine — preserving the held config password so an encrypted
  /// config stays unlocked across the swap. Throws on failure so the caller (the
  /// settings "Update engine" affordance) can surface it inline. Android bundles
  /// its engine, so [RcloneEngine.downloadLatest] throws there by design.
  Future<void> updateEngine() async {
    final password = ref.read(cachePassphraseProvider);
    final path = await RcloneEngine.downloadLatest();
    _rclonePath = path;
    await state.client?.quit();
    await _startWith(path, password: password);
    // _startWith never throws — it parks failures in the error/needsPassword
    // phase for the engine gate. Surface a failed post-update start to the
    // caller explicitly, or Settings would report "Engine updated." while the
    // engine is actually down.
    if (!state.isReady) {
      throw StateError(
        state.message ?? 'the engine did not start after the update',
      );
    }
  }

  /// Provided by the password gate when the config is encrypted.
  Future<void> unlockAndStart(String password) async {
    final path = _rclonePath;
    if (path == null) return bootstrap();
    await _startWith(path, password: password);
    // A successful interactive unlock is the one moment we hold the plaintext
    // config password with the user watching. Honour their opt-in: stash it in
    // the OS vault so unattended (scheduled/background) runs can unlock the same
    // config later — or wipe any stale copy the moment they've opted out.
    if (!state.isReady) return;
    final vault = ref.read(configPasswordVaultProvider);
    // Hydrate the persisted opt-in BEFORE the save-vs-clear decision. On a cold
    // GUI start straight to the password gate this is the first read of the
    // remember provider, whose build() returns the default `false` synchronously
    // and fills from disk asynchronously; awaiting ensureLoaded() makes the
    // decision use the user's actual choice instead of wiping the just-typed
    // working password (which would then break every unattended run on this
    // config). This also removes the headless path's fragile read-ordering
    // dependency — the correct value is guaranteed regardless of read order.
    await ref.read(rememberConfigPasswordProvider.notifier).ensureLoaded();
    if (ref.read(rememberConfigPasswordProvider)) {
      await vault.save(password);
    } else {
      await vault.clear();
    }
  }

  /// After we have a binary: gate on the config password if encrypted, else start.
  Future<void> _proceedWith(String rclonePath) async {
    _rclonePath = rclonePath;
    final (configPath, _) = await _platformSetup();
    if (await RcloneEngine.isConfigEncrypted(
      rclonePath,
      configPath: configPath,
    )) {
      // Encrypted config. Before gating on manual entry, try a password the user
      // chose to remember in the OS vault (the headless-unlock prerequisite): a
      // successful read is a silent unlock straight to start, while a wrong or
      // absent one falls through to the needsPassword gate exactly as before. We
      // only reach for it on a cold start (no session password held yet).
      if (ref.read(cachePassphraseProvider) == null) {
        final remembered = await ref.read(configPasswordVaultProvider).read();
        if (remembered != null && remembered.isNotEmpty) {
          await _startWith(rclonePath, password: remembered);
          if (state.isReady) return;
        }
      }
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
          message:
              'The engine stopped unexpectedly. Start it again to '
              'continue.',
        );
      }
    };
    try {
      await client.start();
      final status = await client.status();
      // Refuse to run an engine older than the supported minimum: it misses RC
      // methods we depend on and carries the published rclone RC CVEs. Enter the
      // error phase so EngineGate offers the download/Retry CTA (which downloads
      // the latest and overwrites the stale managed/PATH binary).
      final reported = status.version;
      if (reported != null && !RcloneEngine.meetsMinRclone(reported)) {
        await client.quit();
        state = EngineUi(
          phase: EnginePhase.error,
          message:
              'rclone $reported is older than the minimum '
              '${RcloneEngine.minRcloneVersion} — update the engine to '
              'continue.',
        );
        return;
      }
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
