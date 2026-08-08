import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../rclone/ffi_rclone_client.dart';
import '../rclone/http_rclone_client.dart';
import '../rclone/librclone_ffi.dart';
import '../rclone/rclone_client.dart';
import '../rclone/rclone_engine.dart';
import 'biometric_unlock.dart';
import 'cache_crypto.dart';
import 'config_password_vault.dart';
import 'engine_flags.dart';
import 'engine_mode.dart';
import 'settings_controller.dart';

/// Resolves the `--config` path the engine should spawn with (null = "let rclone
/// use its own default location"). Pure and platform-parameterised so the
/// decision is unit-tested without a process — see `config_override_test.dart`.
///
/// Resolution order:
///  - **Android** always uses its app-private config ([androidConfigPath]); the
///    sandbox has nowhere else the engine may exec/read a config against, and the
///    override picker is desktop-only.
///  - **Desktop** uses [override] when set (Settings → Config → "Use a different
///    config file…"), otherwise null — rclone resolves its own default.
String? resolveConfigPath({
  required bool isAndroid,
  String? androidConfigPath,
  String? override,
}) {
  if (isAndroid) return androidConfigPath;
  return (override != null && override.isNotEmpty) ? override : null;
}

/// The argv for the pre-switch validation probe the settings "Use a different
/// config file…" action runs: `rclone config dump --config <path>`. Pure so the
/// exact vector is unit-tested without spawning a process. A non-zero exit means
/// the file isn't a loadable rclone config; the caller surfaces that inline and
/// blocks the switch. (An *encrypted* pick is detected out-of-band beforehand
/// and skips this probe — it gates on the launch password instead.)
List<String> configDumpArgs(String configPath) => [
  'config',
  'dump',
  '--config',
  configPath,
];

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

  /// The engine actually in use this run, resolved once at [bootstrap] from the
  /// user's [EngineMode] setting + platform + what is available. Drives whether
  /// [_startWith] builds a spawned [HttpRcloneClient] or an in-process
  /// [FfiRcloneClient], and gates the binary-only `_rclonePath == null` paths.
  EngineMode _resolvedMode = EngineMode.binary;

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
    _rclonePath = path;
    _resolvedMode = await _resolveEngineMode(binaryAvailable: path != null);

    // In-process engine: the bundled library stands in for the binary, so skip
    // the "binary not found" branch entirely and go straight to the gate.
    if (_resolvedMode == EngineMode.inProcess) {
      if (!File(defaultLibrclonePath()).existsSync()) {
        state = const EngineUi(
          phase: EnginePhase.error,
          message:
              'The in-process engine library was not found in this build. '
              'Switch to the binary engine in Settings, or reinstall.',
        );
        return;
      }
      await _proceedWith(null);
      return;
    }

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

  /// Resolve the engine to run from the persisted setting + availability. Android
  /// always runs its bundled binary (its jniLib-subprocess model is the only one
  /// wired there); engine choice is desktop-only. Desktop DMG allows a subprocess
  /// — the iOS/MAS "library only" constraint lands with those targets.
  Future<EngineMode> _resolveEngineMode({required bool binaryAvailable}) async {
    if (Platform.isAndroid) return EngineMode.binary;
    await ref.read(settingsControllerProvider.notifier).ensureLoaded();
    final setting = ref.read(settingsControllerProvider).engineMode;
    return resolveEngineMode(
      setting: setting,
      subprocessAllowed: true,
      libraryAvailable: File(defaultLibrclonePath()).existsSync(),
      binaryAvailable: binaryAvailable,
    );
  }

  /// Android runs the engine sandboxed: the config lives in the app's own
  /// storage (passed via `--config`), temp files go to the app cache (there is
  /// no /tmp), and `local` writes skip chtimes, which Android storage rejects.
  /// Desktop lets rclone use its own default location UNLESS the user set a
  /// config-file override (Settings → Config), which flows through here as the
  /// spawn's `--config` arg AND the file `isConfigEncrypted` reads directly.
  Future<(String?, Map<String, String>)> _platformSetup() async {
    // Hydrate the persisted override before reading it: build() returns the
    // default synchronously and fills from disk on a later microtask, so a cold
    // bootstrap that skipped this could spawn against the DEFAULT config while
    // the user's override is still loading. ensureLoaded() is idempotent.
    await ref.read(settingsControllerProvider.notifier).ensureLoaded();
    final override = ref.read(settingsControllerProvider).configPathOverride;
    if (!Platform.isAndroid) {
      return (
        resolveConfigPath(isAndroid: false, override: override),
        const <String, String>{},
      );
    }
    final support = await getApplicationSupportDirectory();
    final cache = await getTemporaryDirectory();
    final configPath = resolveConfigPath(
      isAndroid: true,
      androidConfigPath: '${support.path}/rclone.conf',
      override: override,
    );
    return (
      configPath,
      <String, String>{
        'TMPDIR': cache.path,
        'HOME': support.path,
        // Without this, rclone derives its cache dir from HOME and VFS/preview
        // cache data lands in persistent app storage the OS can't reclaim.
        'XDG_CACHE_HOME': cache.path,
        'RCLONE_LOCAL_NO_SET_MODTIME': 'true',
        // The parent `rcd` gets --config explicitly, but `core/command` (the
        // console) and the archive subprocess re-exec a FRESH rclone that does
        // NOT inherit that flag. Pass the config via env too so those children
        // read the SAME config (rclone precedence flag > env > default, so the
        // parent is unaffected). Without this they resolve an empty
        // $HOME/.config/rclone/rclone.conf — none of the user's remotes.
        'RCLONE_CONFIG': ?configPath,
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
  /// Use this ONLY when the config FILE is unchanged — for a config-path/content
  /// change use [switchConfigAndStart], which re-gates on the new config.
  Future<void> restartEngine() async {
    // Binary mode needs a located binary; the in-process engine does not. A path
    // override may have been set (Settings) since the last bootstrap without a
    // restart, leaving `_rclonePath` null — re-resolve it here rather than
    // silently no-opping, so a post-config-op restart actually comes back up.
    if (_resolvedMode != EngineMode.inProcess && _rclonePath == null) {
      _rclonePath = await RcloneEngine.findExisting(
        overridePath: ref.read(settingsControllerProvider).rclonePathOverride,
      );
      if (_rclonePath == null) return;
    }
    final password = ref.read(cachePassphraseProvider);
    await state.client?.quit();
    await _startWith(password: password);
  }

  /// Stop the running engine WITHOUT tearing down the resolved binary/mode, so a
  /// config-FILE operation ([ConfigTransferController.applyConfigEncryption]) can
  /// rewrite the config with NO second writer racing it — rclone's own OAuth
  /// token auto-save would otherwise write the file concurrently with the
  /// encryption CLI's atomic rename and lose an update. [reloadWithConfigPassword]
  /// brings the engine back afterward. Parks the phase in `starting` (client
  /// cleared) so the UI never shows a "ready" engine wired to a stopped process.
  Future<void> quiesceForConfigOp() async {
    _quiescing = true;
    await state.client?.quit();
    state = const EngineUi(
      phase: EnginePhase.starting,
      message: 'Applying config change…',
    );
  }

  /// True while a config-file op holds the engine down between [quiesceForConfigOp]
  /// and its follow-up restart — lets callers distinguish a deliberate pause from
  /// a crash.
  bool _quiescing = false;
  bool get isQuiescing => _quiescing;

  /// Restart the engine for a CONFIG-PATH / CONFIG-CONTENT change (switch config
  /// file, back to default, replace, or restore). Unlike [restartEngine] — which
  /// reuses the password held for the OLD config against the SAME file — this
  /// re-runs the encryption gate against the RESOLVED NEW config via
  /// [_proceedWith]: detect encryption, try a silent vault unlock, else enter
  /// [EnginePhase.needsPassword]. It first CLEARS the held password so the new
  /// config's actual encryption state decides what unlocks it — otherwise a
  /// switch to an encrypted config would spawn with the wrong password (never
  /// reaching the gate), and a switch to a PLAINTEXT config would leave the stale
  /// password bound to the cache + the Settings "Encrypted" badge lit. The caller
  /// persists the new override BEFORE calling this so [_platformSetup] resolves
  /// the new path.
  Future<void> switchConfigAndStart() async {
    // Binary mode without a located binary can't proceed — (re)bootstrap.
    if (_resolvedMode != EngineMode.inProcess && _rclonePath == null) {
      return bootstrap();
    }
    await state.client?.quit();
    // Drop the previous config's password before re-gating; _proceedWith only
    // reaches for the vault when no session password is held.
    ref.read(cachePassphraseProvider.notifier).state = null;
    await _proceedWith(_rclonePath);
  }

  /// Switch engines after the user changes the [EngineMode] setting: tear down
  /// the current engine, drop the held password, and re-bootstrap so the mode is
  /// resolved afresh (binary ↔ in-process). Resetting the phase clears the
  /// ready-guard so [bootstrap] runs its full resolve-and-start path.
  Future<void> switchEngineAndStart() async {
    await state.client?.quit();
    ref.read(cachePassphraseProvider.notifier).state = null;
    state = const EngineUi(phase: EnginePhase.idle);
    await bootstrap();
  }

  /// Desktop: download the latest verified rclone, repoint the cached path, and
  /// restart the engine — preserving the held config password so an encrypted
  /// config stays unlocked across the swap. Throws on failure so the caller (the
  /// settings "Update engine" affordance) can surface it inline. Android and the
  /// desktop Microsoft Store (MSIX) build ship a managed engine, so
  /// [RcloneEngine.downloadLatest] throws for them by design (see
  /// [RcloneEngine.isStoreManaged]); the unpackaged zip/installer bundle rclone
  /// but may still update it here.
  Future<void> updateEngine() async {
    final password = ref.read(cachePassphraseProvider);

    // 1. Download + verify BEFORE stopping anything, into a staging file. The
    //    running engine holds its own binary open, and on Windows you cannot
    //    replace a running executable — writing the managed path here is what
    //    made this always fail with "Update failed" once an engine had been
    //    downloaded. Staging first also means a failed download costs nothing:
    //    the working engine is still up and untouched.
    final staged = await RcloneEngine.downloadLatestToStaging();

    // 2. Now stop the engine, releasing the lock on the old binary.
    await state.client?.quit();

    // 3. Swap. The previous binary is kept so a bad engine can be undone.
    final String path;
    try {
      path = await RcloneEngine.installStaged(staged);
    } catch (_) {
      // Swap failed — the old binary is still in place, so bring it back up
      // rather than leaving the user with a stopped engine.
      await _startWith(password: password);
      rethrow;
    }

    _rclonePath = path;
    // "Update engine" downloads + runs a binary — force binary mode for the
    // restart (the in-process library ships with the app and isn't updated here).
    _resolvedMode = EngineMode.binary;
    await _startWith(password: password);

    // _startWith never throws — it parks failures in the error/needsPassword
    // phase for the engine gate. Surface a failed post-update start to the
    // caller explicitly, or Settings would report "Engine updated." while the
    // engine is actually down.
    if (!state.isReady) {
      // 4. The new engine will not run: put the old one back and restart it, so
      //    a bad rclone release cannot leave Airclone permanently broken.
      final failure =
          state.message ?? 'the engine did not start after the update';
      await RcloneEngine.rollbackEngine();
      await _startWith(password: password);
      throw StateError(failure);
    }
    await RcloneEngine.discardPreviousEngine();
  }

  /// Provided by the password gate when the config is encrypted.
  Future<void> unlockAndStart(String password) async {
    if (_resolvedMode != EngineMode.inProcess && _rclonePath == null) {
      return bootstrap();
    }
    await _startWith(password: password);
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

  /// Restart the engine after the config's OWN encryption state was changed
  /// out-of-band — Airclone ran `rclone config encryption set/remove` on the
  /// file via [ConfigTransferController.applyConfigEncryption]. Unlike
  /// [switchConfigAndStart] (which re-runs the encryption GATE because it can't
  /// know the new state), here we KNOW the resulting state, so we start straight
  /// with [newPassword] — the password the config now needs, or null after a
  /// decrypt. Persists/clears the OS vault per the remember opt-in exactly like an
  /// interactive [unlockAndStart], so a just-encrypted config stays unlocked for
  /// unattended runs (when opted in) and a just-decrypted one never leaves a stale
  /// password behind. Throws if the engine fails to come back up.
  Future<void> reloadWithConfigPassword(String? newPassword) async {
    // restartEngine reads the held password to respawn with — set it first so the
    // engine comes up against the NEW encryption state (null ⇒ plaintext spawn).
    ref.read(cachePassphraseProvider.notifier).state = newPassword;
    await restartEngine();
    _quiescing = false;
    // Reconcile the OS vault to the new ON-DISK state BEFORE surfacing any restart
    // failure. The encryption CLI already committed the file change atomically, so
    // the vault must match it whether or not the engine came back up — throwing
    // first (as this used to) would strand a stale password after a decrypt or the
    // OLD, now-wrong password after a change if the restart failed.
    final vault = ref.read(configPasswordVaultProvider);
    await ref.read(rememberConfigPasswordProvider.notifier).ensureLoaded();
    if (newPassword != null &&
        newPassword.isNotEmpty &&
        ref.read(rememberConfigPasswordProvider)) {
      await vault.save(newPassword);
    } else {
      await vault.clear();
    }
    if (!state.isReady) {
      throw StateError(
        state.message ??
            'the engine did not restart after the encryption change',
      );
    }
  }

  /// After the engine is resolved (binary located, or in-process library
  /// present): gate on the config password if the config is encrypted, else
  /// start. [rclonePath] is null in in-process mode (there is no binary).
  Future<void> _proceedWith(String? rclonePath) async {
    _rclonePath = rclonePath;
    final (configPath, _) = await _platformSetup();
    if (await _isConfigEncrypted(configPath)) {
      // Encrypted config. Before gating on manual entry, try a password the user
      // chose to remember in the OS vault (the headless-unlock prerequisite): a
      // successful read is a silent unlock straight to start, while a wrong or
      // absent one falls through to the needsPassword gate exactly as before. We
      // only reach for it on a cold start (no session password held yet).
      if (ref.read(cachePassphraseProvider) == null) {
        // Biometric release gate (plan §6). Biometric adds NO crypto — the OS
        // keystore already holds the password; a successful fingerprint/face
        // prompt merely *releases* it here instead of showing the typing gate.
        // Hydrate both opt-ins first (their build() default is a synchronous
        // `false` that fills from disk on a later microtask), then gate: only
        // when the user opted into biometric unlock AND into remembering the
        // password AND the device actually has a biometric do we prompt — and
        // we require it BEFORE reading the stored secret, so the plaintext is
        // never pulled into memory unless the prompt passes. A failed/cancelled/
        // locked-out prompt (or no biometrics / opt-in off) leaves the release
        // exactly as today: silent when un-gated, manual gate when the vault is
        // empty or the wrong password. Biometric NEVER hard-blocks startup.
        await ref.read(rememberConfigPasswordProvider.notifier).ensureLoaded();
        await ref.read(biometricUnlockOptInProvider.notifier).ensureLoaded();
        final biometricOptIn = ref.read(biometricUnlockOptInProvider);
        final rememberOptIn = ref.read(rememberConfigPasswordProvider);
        // Only probe the biometric hardware (a platform call) once the cheap
        // opt-in flags say it could matter — non-opted-in launches pay nothing.
        final available = (biometricOptIn && rememberOptIn)
            ? await ref.read(biometricUnlockProvider).available()
            : false;
        var mayReleaseVault = true;
        if (biometricGateApplies(
          biometricOptIn: biometricOptIn,
          rememberOptIn: rememberOptIn,
          available: available,
        )) {
          mayReleaseVault = await ref
              .read(biometricUnlockProvider)
              .authenticate('Unlock your rclone config');
        }
        if (mayReleaseVault) {
          final remembered = await ref.read(configPasswordVaultProvider).read();
          if (remembered != null && remembered.isNotEmpty) {
            await _startWith(password: remembered);
            if (state.isReady) return;
          }
        }
      }
      state = const EngineUi(
        phase: EnginePhase.needsPassword,
        message:
            'Your rclone config is encrypted. Enter its password to unlock.',
      );
      return;
    }
    await _startWith();
  }

  /// Is the resolved config encrypted? Binary mode asks rclone (or reads the
  /// header when the path is explicit); in-process mode has no binary to spawn,
  /// so it resolves the config path (explicit override, else asks the library
  /// via `config/paths`) and reads the header directly.
  Future<bool> _isConfigEncrypted(String? configPath) async {
    if (_resolvedMode == EngineMode.inProcess) {
      final path = configPath ?? await _probeLibraryConfigPath();
      if (path == null) return false;
      return RcloneEngine.isConfigEncrypted('', configPath: path);
    }
    return RcloneEngine.isConfigEncrypted(_rclonePath!, configPath: configPath);
  }

  /// Ask the in-process engine where its config file lives (the `config/paths`
  /// RC method), so we can check encryption without a binary. Starts a throwaway
  /// library engine with no password — `config/paths` returns the path without
  /// decrypting, so this works even for an encrypted config. Null on any failure
  /// (then we assume unencrypted and let the real start surface any error).
  Future<String?> _probeLibraryConfigPath() async {
    final probe = FfiRcloneClient(libraryPath: defaultLibrclonePath());
    try {
      await probe.start();
      final res = await probe.rpc('config/paths');
      final path = res['config'];
      return (path is String && path.isNotEmpty) ? path : null;
    } catch (_) {
      return null;
    } finally {
      await probe.quit();
    }
  }

  Future<void> _startWith({String? password}) async {
    state = const EngineUi(
      phase: EnginePhase.starting,
      message: 'Starting engine…',
    );
    final (configPath, extraEnv) = await _platformSetup();
    final RcloneClient client;
    if (_resolvedMode == EngineMode.inProcess) {
      // In-process librclone. Its preview byte-bridge needs a writable cache dir
      // (the OS temp dir) since there is no rcd file server. No onDied: an
      // in-process engine is as alive as the app.
      client = FfiRcloneClient(
        libraryPath: defaultLibrclonePath(),
        configPath: configPath,
        configPassword: password,
        previewCacheDir: (await getTemporaryDirectory()).path,
      );
    } else {
      final http = HttpRcloneClient(
        rclonePath: _rclonePath!,
        configPath: configPath,
        configPassword: password,
        extraArgs: parseEngineFlags(ref.read(engineFlagsProvider)),
        extraEnv: extraEnv,
      );
      // If rcd dies out from under us (crash, Android LMK), don't keep showing
      // a "ready" engine wired to a corpse — surface it with a restart path.
      http.onDied = () {
        if (state.client == http) {
          state = const EngineUi(
            phase: EnginePhase.error,
            message:
                'The engine stopped unexpectedly. Start it again to '
                'continue.',
          );
        }
      };
      client = http;
    }
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
