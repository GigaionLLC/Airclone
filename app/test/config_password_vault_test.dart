import 'package:airclone/src/state/config_password_vault.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the OS keystore so the vault seam can be exercised
/// without a platform channel. Overrides only the three methods the vault uses;
/// [throwing] models an unavailable/locked vault (every op throws).
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({this.throwing = false});

  final bool throwing;
  final Map<String, String> store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwing) throw Exception('vault unavailable');
    return store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwing) throw Exception('vault unavailable');
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwing) throw Exception('vault unavailable');
    store.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigPasswordVault', () {
    test('save/read/clear round-trip through the injected store', () async {
      final vault = ConfigPasswordVault(_FakeSecureStorage());

      // Empty vault reads as null.
      expect(await vault.read(), isNull);
      // Saved value round-trips back out.
      await vault.save('hunter2');
      expect(await vault.read(), 'hunter2');
      // Clearing removes it.
      await vault.clear();
      expect(await vault.read(), isNull);
    });

    test('clear() reports success, and failure on a rejecting vault', () async {
      final ok = ConfigPasswordVault(_FakeSecureStorage());
      await ok.save('x');
      expect(await ok.clear(), isTrue); // removed cleanly
      expect(await ok.clear(), isTrue); // nothing to remove is still success

      // A failed delete must report false so the security-sensitive opt-out UI
      // can warn instead of claiming the recoverable secret was cleared.
      final broken = ConfigPasswordVault(_FakeSecureStorage(throwing: true));
      expect(await broken.clear(), isFalse);
    });

    test(
      'read() returns null (never throws) when the vault is unavailable',
      () async {
        final vault = ConfigPasswordVault(_FakeSecureStorage(throwing: true));
        // A locked/missing/unsupported keystore must degrade to "no password",
        // never crash the startup unlock flow.
        expect(await vault.read(), isNull);
      },
    );

    test('stores under a single namespaced key', () async {
      final store = _FakeSecureStorage();
      final vault = ConfigPasswordVault(store);
      await vault.save('s3cret');
      expect(ConfigPasswordVault.key, 'airclone.configPassword');
      // The vault owns exactly one namespaced entry — nothing else leaks in.
      expect(store.store.keys, ['airclone.configPassword']);
      expect(store.store['airclone.configPassword'], 's3cret');
    });
  });

  group('RememberConfigPassword.ensureLoaded', () {
    test('hydrates the persisted opt-in before completing', () async {
      SharedPreferences.setMockInitialValues({
        'remember_config_password': true,
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(rememberConfigPasswordProvider.notifier);
      // The synchronous build() default is false until the async load lands —
      // reading here (before any await) would make a save-vs-clear decision on
      // the WRONG value. This is the exact race ensureLoaded() closes.
      expect(c.read(rememberConfigPasswordProvider), isFalse);
      await notifier.ensureLoaded();
      // After ensureLoaded() the persisted `true` is reflected, so the unlock
      // decision now honours the user's real choice.
      expect(c.read(rememberConfigPasswordProvider), isTrue);
    });

    test('is idempotent — the same cached future, hydrated once', () async {
      SharedPreferences.setMockInitialValues({
        'remember_config_password': true,
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(rememberConfigPasswordProvider.notifier);
      final f1 = n.ensureLoaded();
      final f2 = n.ensureLoaded();
      expect(identical(f1, f2), isTrue);
      await Future.wait([f1, f2]);
      expect(c.read(rememberConfigPasswordProvider), isTrue);
    });
  });
}
