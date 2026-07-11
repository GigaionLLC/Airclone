import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin, injectable wrapper over [LocalAuthentication] — the seam through which
/// the app asks the OS "is a fingerprint/face available?" and "prove it now".
///
/// **Semantics (the honest part).** Biometric unlock adds NO cryptography. The
/// rclone config password already lives in the OS credential vault
/// ([ConfigPasswordVault], shipped) bound to the user's OS/device unlock.
/// A successful biometric prompt does not decrypt anything — it merely *releases*
/// that already-stored secret at launch instead of showing the typing gate. So
/// this is an unlock-UX gate, not a security boundary: it raises the bar against
/// casual access on an already-unlocked device, but anyone who can unlock the
/// device (knows the passcode) can still reach the keystore. The Settings copy
/// says exactly that.
///
/// **Never crash startup.** Every platform call is wrapped so a device without
/// biometric hardware, a missing/again plugin, an OS that throws, or a keystore
/// that's momentarily unavailable degrades to `false` (no biometrics / auth
/// failed) rather than throwing into the engine's cold-start path — where the
/// only correct fallback is the existing manual password gate.
///
/// The [LocalAuthentication] is an injectable constructor param (default a real
/// one) so tests drive the seam over a fake without a platform channel, exactly
/// like [ConfigPasswordVault] takes a [FlutterSecureStorage].
class BiometricUnlock {
  BiometricUnlock([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// Whether this device can prompt for a biometric (enrolled fingerprint/face).
  /// True only when the OS reports the device supports authentication, the
  /// biometric hardware can be queried, AND at least one biometric is actually
  /// enrolled; any exception (unsupported platform, missing plugin, locked
  /// keystore) degrades to `false`. Used by Settings to decide whether to even
  /// offer the switch, and by the engine to decide whether to prompt before
  /// releasing the vault password.
  Future<bool> available() async {
    try {
      // isDeviceSupported() gates on the device being capable of auth at all;
      // canCheckBiometrics narrows that to biometric (vs. passcode-only) — we
      // authenticate biometricOnly, so both must hold. But canCheckBiometrics
      // reports HARDWARE capability: it is true on a device with a sensor even
      // when NOTHING is enrolled, which would make the toggle/gate engage
      // pointlessly (a biometricOnly prompt with nothing to match, failing straight
      // through to the manual gate every launch). So also require the OS's list of
      // actually-enrolled biometrics to be non-empty — that is what "enrolled" in
      // the docs/UX means, and what canCheckBiometrics alone does not guarantee.
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Prompt for a biometric and return whether it succeeded. [reason] is the
  /// OS-shown rationale string. `biometricOnly` keeps this a fingerprint/face
  /// gate (no silent device-passcode fallback — that would defeat the honest
  /// "not against someone with your passcode" framing); a failure, cancellation,
  /// lockout, or any platform exception returns `false` so the caller falls
  /// through to the manual password gate. Never throws.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

/// The app's single [BiometricUnlock], over a real [LocalAuthentication]. Tests
/// override this provider with a seam built on a fake LocalAuthentication.
final biometricUnlockProvider = Provider<BiometricUnlock>(
  (ref) => BiometricUnlock(),
);

/// Cold-start policy: does a biometric prompt gate release of the vault-stored
/// config password on THIS launch? Pure so the truth table is unit-tested
/// without a platform channel (mirrors [resolveConfigPath]'s pure-decision
/// style). The gate applies ONLY when all three hold:
///  - [biometricOptIn]: the user turned on "Unlock with fingerprint / face".
///  - [rememberOptIn]: the password is actually stored in the vault (biometric
///    gating a secret that isn't there is meaningless — nothing to release).
///  - [available]: the device really has an enrolled biometric.
/// When it does NOT apply, the vault unlocks silently — precisely the behavior
/// before this feature existed — so biometric can only ADD a prompt, never
/// remove the manual fallback.
bool biometricGateApplies({
  required bool biometricOptIn,
  required bool rememberOptIn,
  required bool available,
}) => biometricOptIn && rememberOptIn && available;

/// Opt-in (default **false**) to releasing the vault-stored config password with
/// a biometric prompt at launch instead of the typing gate. Persisted like the
/// app's other boolean settings (SharedPreferences), following
/// [rememberConfigPasswordProvider]'s exact pattern — including the awaitable
/// [ensureLoaded] so a cold-start engine decision reads the user's real choice
/// rather than the synchronous `false` default.
class BiometricUnlockOptIn extends Notifier<bool> {
  static const _key = 'biometric_unlock';

  /// The single in-flight/completed hydration future, cached so [ensureLoaded]
  /// is idempotent and every caller awaits the SAME read rather than racing the
  /// synchronous `false` default.
  Future<void>? _loading;

  @override
  bool build() {
    ensureLoaded();
    return false;
  }

  /// Awaitable hydration: completes once [state] reflects the persisted opt-in.
  /// build() returns `false` synchronously and fills from disk on a later
  /// microtask, so the engine's cold-start biometric gate must `await` this
  /// before reading the flag — otherwise a genuinely opted-in user could be
  /// silently un-gated on the very first launch after boot. Idempotent.
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

final biometricUnlockOptInProvider =
    NotifierProvider<BiometricUnlockOptIn, bool>(BiometricUnlockOptIn.new);
