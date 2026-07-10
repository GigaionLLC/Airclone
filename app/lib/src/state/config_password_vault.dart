import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the rclone **config password** in the operating system's credential
/// vault (Windows DPAPI / Credential Manager, macOS Keychain, Linux Secret
/// Service) behind a single namespaced key.
///
/// This is the cross-cutting prerequisite for background/headless runs on an
/// *encrypted* config (see dev/plans/phase3-continuation-plan.md): an unattended
/// entrypoint has no human to type the password, so — only when the user has
/// explicitly opted in via [rememberConfigPasswordProvider] — we persist it here
/// for a later silent unlock. Security posture: default OFF, explicit opt-in, and
/// honest Settings copy. Anything running as the user's OS account can recover
/// the secret from the vault; that is the deliberate trade for unattended unlock.
///
/// Seam contract (a later headless agent consumes these three methods verbatim):
///   `Future<String?> read()` · `Future<void> save(String password)` ·
///   `Future<void> clear()`
///
/// The [FlutterSecureStorage] is an injectable constructor param so tests drive
/// the seam over an in-memory fake without touching a platform channel.
class ConfigPasswordVault {
  ConfigPasswordVault(this._storage);

  /// The one key we own inside the OS vault. Namespaced so it can't collide with
  /// any other secret the app (or another app sharing the store) might keep.
  static const String key = 'airclone.configPassword';

  final FlutterSecureStorage _storage;

  /// The stored config password, or `null` when none is stored **or the vault is
  /// unavailable**. A missing backend, a locked keyring, or any platform
  /// exception must never crash startup — the encrypted-config unlock flow treats
  /// a `null` here exactly as "no remembered password" and falls back to the
  /// manual password gate, so returning null on error is the safe degradation.
  Future<String?> read() async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // Vault unavailable (no backend, locked keyring, platform exception).
      return null;
    }
  }

  /// Persist [password] under our namespaced key. Best-effort: a vault failure is
  /// swallowed (the feature silently degrades to a manual unlock next time)
  /// rather than surfaced into the unlock/settings flows that call this.
  Future<void> save(String password) async {
    try {
      await _storage.write(key: key, value: password);
    } catch (e) {
      debugPrint('ConfigPasswordVault.save failed: $e');
    }
  }

  /// Remove the stored password. Returns true when the delete succeeded (or
  /// there was nothing to remove) and false when the vault rejected it — a
  /// security-sensitive opt-out must not silently leave the secret behind while
  /// the UI claims it was cleared, so the Settings toggle surfaces a false. The
  /// unlock opt-out branch ignores the result (it has no UI to warn from).
  Future<bool> clear() async {
    try {
      await _storage.delete(key: key);
      return true;
    } catch (e) {
      debugPrint('ConfigPasswordVault.clear failed: $e');
      return false;
    }
  }
}

/// The app's single [ConfigPasswordVault], over a default [FlutterSecureStorage]
/// (desktop uses DPAPI/Keychain/Secret Service out of the box). Tests override
/// this provider with a vault built on an in-memory fake store.
final configPasswordVaultProvider = Provider<ConfigPasswordVault>(
  (ref) => ConfigPasswordVault(const FlutterSecureStorage()),
);

/// Opt-in (default **false**) to remembering the encrypted-config password in the
/// OS vault. Persisted like the app's other boolean settings (SharedPreferences,
/// mirroring [engineFlagsProvider] / advanced mode). Kept next to the vault
/// because the two are only meaningful together.
class RememberConfigPassword extends Notifier<bool> {
  static const _key = 'remember_config_password';

  /// The single in-flight/completed hydration future, cached so [ensureLoaded]
  /// is idempotent and every caller awaits the SAME read rather than kicking off
  /// a fresh one (or racing the synchronous `false` default).
  Future<void>? _loading;

  @override
  bool build() {
    ensureLoaded();
    return false;
  }

  /// Awaitable hydration: completes once [state] reflects the persisted opt-in.
  /// build() returns the default `false` synchronously and fills from disk on a
  /// later microtask, so any consumer that makes an IRREVERSIBLE decision on
  /// this flag — [EngineController.unlockAndStart]'s save-vs-clear of the config
  /// password, the headless pre-hydration — must `await` this first, or on a
  /// cold start (its first read) it would see `false` and wipe a just-stored
  /// password. Idempotent: the cached [_load] future is kicked off in build().
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getBool(_key) ?? false;
    } catch (_) {
      // keep default
    }
  }

  Future<void> set(bool v) async {
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {
      // best-effort
    }
  }
}

final rememberConfigPasswordProvider =
    NotifierProvider<RememberConfigPassword, bool>(RememberConfigPassword.new);
