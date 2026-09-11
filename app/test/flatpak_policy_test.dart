import 'package:airclone/src/state/build_flavor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mounting a remote as a drive is FUSE, and two shipped builds cannot do it:
/// the Mac App Store build (the App Sandbox forbids it) and the Flatpak (our
/// manifest deliberately does not request `--device=all`, because blanket device
/// access is a much larger permission than the feature is worth).
///
/// Both must HIDE the feature rather than fail when it is used. A button that
/// cannot work is the dead end an Android TV review already failed this project
/// on once, and it is worth not repeating on Linux.
void main() {
  group('detecting a Flatpak sandbox', () {
    test('FLATPAK_ID present means yes', () {
      expect(runningInFlatpak({'FLATPAK_ID': 'app.airclone.airclone'}), isTrue);
    });

    test('an ordinary desktop environment means no', () {
      expect(runningInFlatpak({}), isFalse);
      expect(runningInFlatpak({'HOME': '/home/someone'}), isFalse);
    });

    test('an empty value is not a sandbox', () {
      // An exported-but-empty variable would otherwise disable mounting on a
      // machine that can perfectly well do it.
      expect(runningInFlatpak({'FLATPAK_ID': ''}), isFalse);
    });
  });

  group('whether mounting is possible', () {
    test('an ordinary desktop build can mount', () {
      expect(mountPossibleFor(macAppStore: false, flatpak: false), isTrue);
    });

    test('a Flatpak cannot — no /dev/fuse in the sandbox', () {
      expect(mountPossibleFor(macAppStore: false, flatpak: true), isFalse);
    });

    test('a Mac App Store build cannot', () {
      expect(mountPossibleFor(macAppStore: true, flatpak: false), isFalse);
    });

    test('either one alone is enough to rule it out', () {
      expect(mountPossibleFor(macAppStore: true, flatpak: true), isFalse);
    });
  });
}
