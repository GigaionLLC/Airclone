import 'package:airclone/src/state/biometric_unlock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
// AuthMessages lives in the platform interface (local_auth.dart doesn't
// re-export it); the fake below overrides authenticate(), whose real signature
// names it, so we import it directly.
// ignore: depend_on_referenced_packages
import 'package:local_auth_platform_interface/types/auth_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the platform's [LocalAuthentication] so the seam can be
/// exercised without a MethodChannel — mirrors config_password_vault_test's fake
/// FlutterSecureStorage. Overrides only the three members the seam touches;
/// [throwing] models a device/plugin that raises on every call (missing plugin,
/// again-in-progress, locked keystore), which the seam MUST swallow to `false`.
class _FakeLocalAuth extends LocalAuthentication {
  _FakeLocalAuth({
    this.supported = true,
    this.canCheck = true,
    this.enrolled = const [BiometricType.fingerprint],
    this.authResult = true,
    this.throwing = false,
  });

  /// isDeviceSupported() result.
  final bool supported;

  /// canCheckBiometrics result.
  final bool canCheck;

  /// getAvailableBiometrics() result — the ENROLLED list. Distinct from [canCheck]
  /// (hardware capability): a device can have a sensor ([canCheck] true) yet no
  /// enrolled fingerprint/face (empty list), which [available] must treat as "no".
  final List<BiometricType> enrolled;

  /// authenticate() result.
  final bool authResult;

  /// When true every member throws a PlatformException (an unavailable device).
  final bool throwing;

  int isDeviceSupportedCalls = 0;
  int canCheckCalls = 0;
  int getAvailableCalls = 0;
  int authCalls = 0;
  String? lastReason;
  AuthenticationOptions? lastOptions;

  @override
  Future<bool> isDeviceSupported() async {
    isDeviceSupportedCalls++;
    if (throwing) throw PlatformException(code: 'NotAvailable');
    return supported;
  }

  @override
  Future<bool> get canCheckBiometrics async {
    canCheckCalls++;
    if (throwing) throw PlatformException(code: 'NotAvailable');
    return canCheck;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    getAvailableCalls++;
    if (throwing) throw PlatformException(code: 'NotAvailable');
    return enrolled;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authCalls++;
    lastReason = localizedReason;
    lastOptions = options;
    if (throwing) throw PlatformException(code: 'NotAvailable');
    return authResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiometricUnlock.available', () {
    test(
      'true only when supported, checkable, AND a biometric is enrolled',
      () async {
        final auth = _FakeLocalAuth();
        expect(await BiometricUnlock(auth).available(), isTrue);
        // Enrollment is actually consulted — not just hardware capability.
        expect(auth.getAvailableCalls, 1);
      },
    );

    test('false when the device is not supported', () async {
      final auth = _FakeLocalAuth(supported: false);
      expect(await BiometricUnlock(auth).available(), isFalse);
      // Short-circuits: an unsupported device never consults the later probes.
      expect(auth.canCheckCalls, 0);
      expect(auth.getAvailableCalls, 0);
    });

    test('false when supported but no biometric can be checked', () async {
      final auth = _FakeLocalAuth(canCheck: false);
      expect(await BiometricUnlock(auth).available(), isFalse);
      // Short-circuits before the enrollment probe.
      expect(auth.getAvailableCalls, 0);
    });

    test('false when supported + checkable but nothing is enrolled', () async {
      // canCheckBiometrics reports hardware capability, NOT enrollment — a device
      // with a sensor but no registered fingerprint/face must not offer the gate,
      // or it would prompt biometricOnly with nothing to match every launch.
      final auth = _FakeLocalAuth(enrolled: const []);
      expect(await BiometricUnlock(auth).available(), isFalse);
      expect(auth.getAvailableCalls, 1);
    });

    test('a platform exception degrades to false (never throws)', () async {
      // A missing/again/locked platform must not crash the engine's cold-start
      // path — the only safe fallback there is the manual password gate.
      expect(
        await BiometricUnlock(_FakeLocalAuth(throwing: true)).available(),
        isFalse,
      );
    });
  });

  group('BiometricUnlock.authenticate', () {
    test('returns true on a successful prompt', () async {
      expect(
        await BiometricUnlock(_FakeLocalAuth()).authenticate('unlock'),
        isTrue,
      );
    });

    test('returns false on a failed/cancelled prompt', () async {
      expect(
        await BiometricUnlock(
          _FakeLocalAuth(authResult: false),
        ).authenticate('unlock'),
        isFalse,
      );
    });

    test('a platform exception degrades to false (never throws)', () async {
      // Lockout / plugin error must fall through to the manual gate, not throw.
      expect(
        await BiometricUnlock(
          _FakeLocalAuth(throwing: true),
        ).authenticate('unlock'),
        isFalse,
      );
    });

    test('prompts biometric-only with the given reason', () async {
      final auth = _FakeLocalAuth();
      await BiometricUnlock(auth).authenticate('Unlock your rclone config');
      expect(auth.authCalls, 1);
      expect(auth.lastReason, 'Unlock your rclone config');
      // biometricOnly keeps this a fingerprint/face gate — no silent passcode
      // fallback, matching the honest "not against your passcode" framing.
      expect(auth.lastOptions?.biometricOnly, isTrue);
    });
  });

  group('biometricGateApplies — cold-start release policy', () {
    test(
      'applies only when opted in, remembered, AND a biometric is available',
      () {
        expect(
          biometricGateApplies(
            biometricOptIn: true,
            rememberOptIn: true,
            available: true,
          ),
          isTrue,
        );
      },
    );

    test(
      'never applies when biometric opt-in is off (silent unlock, as today)',
      () {
        expect(
          biometricGateApplies(
            biometricOptIn: false,
            rememberOptIn: true,
            available: true,
          ),
          isFalse,
        );
      },
    );

    test('never applies when nothing is stored (remember opt-in off)', () {
      // Gating the release of a secret that isn't in the vault is meaningless.
      expect(
        biometricGateApplies(
          biometricOptIn: true,
          rememberOptIn: false,
          available: true,
        ),
        isFalse,
      );
    });

    test('never applies when the device has no biometric available', () {
      expect(
        biometricGateApplies(
          biometricOptIn: true,
          rememberOptIn: true,
          available: false,
        ),
        isFalse,
      );
    });
  });

  group('biometricUnlockOptInProvider — persistence', () {
    test('defaults to false', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(biometricUnlockOptInProvider.notifier).ensureLoaded();
      expect(c.read(biometricUnlockOptInProvider), isFalse);
    });

    test(
      'set() persists and a fresh container hydrates it via ensureLoaded',
      () async {
        SharedPreferences.setMockInitialValues({});
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await c.read(biometricUnlockOptInProvider.notifier).ensureLoaded();
        await c.read(biometricUnlockOptInProvider.notifier).set(true);
        expect(c.read(biometricUnlockOptInProvider), isTrue);

        // A fresh container reads the persisted value back from disk.
        final c2 = ProviderContainer();
        addTearDown(c2.dispose);
        await c2.read(biometricUnlockOptInProvider.notifier).ensureLoaded();
        expect(c2.read(biometricUnlockOptInProvider), isTrue);
      },
    );

    test(
      'ensureLoaded hydrates the persisted opt-in before completing',
      () async {
        SharedPreferences.setMockInitialValues({'biometric_unlock': true});
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = c.read(biometricUnlockOptInProvider.notifier);
        // The synchronous build() default is false until the async load lands —
        // the exact race the engine's cold-start gate closes by awaiting.
        expect(c.read(biometricUnlockOptInProvider), isFalse);
        await n.ensureLoaded();
        expect(c.read(biometricUnlockOptInProvider), isTrue);
      },
    );

    test(
      'ensureLoaded is idempotent — same cached future, hydrated once',
      () async {
        SharedPreferences.setMockInitialValues({'biometric_unlock': true});
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = c.read(biometricUnlockOptInProvider.notifier);
        final f1 = n.ensureLoaded();
        final f2 = n.ensureLoaded();
        expect(identical(f1, f2), isTrue);
        await Future.wait([f1, f2]);
        expect(c.read(biometricUnlockOptInProvider), isTrue);
      },
    );
  });
}
