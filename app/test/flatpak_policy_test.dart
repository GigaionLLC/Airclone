import 'dart:io';

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
      expect(
        runningInFlatpak({'FLATPAK_ID': 'com.gigaionllc.airclone'}),
        isTrue,
      );
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

  /// Two questions that used to be answered by one check, FLATPAK_ID, and must
  /// not be. "Am I sandboxed?" decides what the app CAN do - it cannot mount,
  /// there is no /dev/fuse - and is true of every Flatpak. "Did Flathub ship
  /// me?" decides who owns updates, and is true only of a build that says so.
  /// The GitHub-release .flatpak is the first and not the second.
  group('sandboxed is not the same as distributed by Flathub', () {
    const bundle = {'FLATPAK_ID': 'com.gigaionllc.airclone'};
    const flathub = {
      'FLATPAK_ID': 'com.gigaionllc.airclone',
      kInstallChannelEnv: kFlathubChannelValue,
    };

    test('both are sandboxed, so neither can mount', () {
      expect(runningInFlatpak(bundle), isTrue);
      expect(runningInFlatpak(flathub), isTrue);
      expect(
        mountPossibleFor(macAppStore: false, flatpak: runningInFlatpak(bundle)),
        isFalse,
        reason: 'the sandbox limit applies to the bundle too',
      );
    });

    test('only the marked build is Flathub', () {
      expect(flathubChannelMarked(bundle), isFalse);
      expect(flathubChannelMarked(flathub), isTrue);
    });

    test('the marker without a sandbox is not Flathub', () {
      expect(
        flathubChannelMarked({kInstallChannelEnv: kFlathubChannelValue}),
        isFalse,
      );
    });
  });

  /// The manifest in app/linux/packaging builds the DIRECT-DOWNLOAD bundle.
  /// If it ever sets the Flathub marker, the GitHub .flatpak is misreported as
  /// Flathub again and loses its update check - the bug this test guards.
  test('the release-bundle manifest does not claim to be Flathub', () {
    final f = File('linux/packaging/com.gigaionllc.airclone.yml');
    if (!f.existsSync()) return;
    expect(
      f.readAsStringSync(),
      isNot(contains(kInstallChannelEnv)),
      reason:
          'marking the direct-download manifest recreates the Flatpak update '
          'bug; only a Flathub-submitted manifest may set it',
    );
  });
}
