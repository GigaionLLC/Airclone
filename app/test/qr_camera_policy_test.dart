import 'package:airclone/src/state/build_flavor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which devices may offer a live QR scan, for importing a config by camera.
///
/// This used to be "is it a desktop?", on the reasoning that a computer has no
/// camera. A MacBook has one, and `mobile_scanner` ships a macOS implementation
/// to drive it, so the rule is now about what can actually be reached rather
/// than about form factor.
///
/// The two exclusions are the interesting part, and both are easy to
/// re-introduce by accident: a television has no camera at all, and a Mac App
/// Store build would need a sandbox entitlement that has to be justified to App
/// Review and declared in the privacy label — a submission decision, not a code
/// one.
void main() {
  bool available({
    bool isAndroid = false,
    bool isIOS = false,
    bool isMacOS = false,
    bool isAndroidTv = false,
    bool macAppStore = false,
  }) => qrCameraScanAvailableFor(
    isAndroid: isAndroid,
    isIOS: isIOS,
    isMacOS: isMacOS,
    isAndroidTv: isAndroidTv,
    macAppStore: macAppStore,
  );

  test('phones can scan', () {
    expect(available(isAndroid: true), isTrue);
    expect(available(isIOS: true), isTrue);
  });

  test('a Mac can scan — it has a camera and an implementation', () {
    expect(available(isMacOS: true), isTrue);
  });

  test('a Mac App Store build does not, until the entitlement is decided', () {
    expect(available(isMacOS: true, macAppStore: true), isFalse);
  });

  test('Windows and Linux cannot — no scanner implementation exists', () {
    // Both fall through every branch: not a phone, not macOS.
    expect(available(), isFalse);
  });

  test('Android TV cannot, even though it is Android', () {
    expect(available(isAndroid: true, isAndroidTv: true), isFalse);
  });

  test('the TV exclusion wins over every other signal', () {
    expect(
      available(isAndroid: true, isIOS: true, isMacOS: true, isAndroidTv: true),
      isFalse,
      reason: 'a television has no camera whatever else is true of it',
    );
  });
}
