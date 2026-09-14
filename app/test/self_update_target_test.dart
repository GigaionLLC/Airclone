import 'dart:io';

import 'package:airclone/src/update/self_update_target.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which copies of Airclone may install an update over themselves.
///
/// The store half of this is not a preference. Microsoft policy 10.2.5 failed
/// Airclone's v0.6.0 submission for LINKING to a GitHub download; Google Play
/// and the App Store say the same. So a store build must be refused here
/// whatever else is true of it, and these tests exist to keep that true when
/// someone adds the sixth package type.
void main() {
  SelfUpdateTarget target({
    bool store = false,
    required String os,
    required String package,
  }) => selfUpdateTargetFor(
    managedByStore: store,
    operatingSystem: os,
    packageKind: package,
  );

  group('a store owns its updates', () {
    test('every managed channel is refused, whatever the package', () {
      for (final (os, package) in const [
        ('windows', 'MSIX package (windows_x64)'),
        ('windows', 'installer (windows_x64)'),
        ('macos', 'app bundle (macos_arm64)'),
        ('linux', 'Flatpak (Flathub) (linux_x64)'),
        ('linux', 'AppImage (linux_x64)'),
        ('android', 'phone 412x915 (android_arm64)'),
      ]) {
        expect(
          target(store: true, os: os, package: package),
          SelfUpdateTarget.unsupported,
          reason: '$os / $package',
        );
      }
    });
  });

  group('direct downloads that can', () {
    test('the Windows installer reruns itself', () {
      final t = target(os: 'windows', package: 'installer (windows_x64)');
      expect(t, SelfUpdateTarget.windowsInstaller);
      expect(t.assetName, 'airclone-setup-x64.exe');
    });

    test('the portable zip swaps its files', () {
      final t = target(os: 'windows', package: 'portable zip (windows_x64)');
      expect(t, SelfUpdateTarget.windowsPortable);
      expect(t.assetName, 'airclone-windows-x64.zip');
    });

    /// The .dmg is published too, but a zip needs no disk image mounted,
    /// attached and detached - three more ways to strand someone mid-update.
    test('the macOS app takes the zip, not the disk image', () {
      final t = target(os: 'macos', package: 'app bundle (macos_arm64)');
      expect(t, SelfUpdateTarget.macApp);
      expect(t.assetName, 'airclone-macos.zip');
    });

    test('the AppImage is one file to replace', () {
      final t = target(os: 'linux', package: 'AppImage (linux_x64)');
      expect(t, SelfUpdateTarget.linuxAppImage);
      expect(t.assetName, 'Airclone-x86_64.AppImage');
    });

    test('the tar.gz is a tree to swap', () {
      final t = target(os: 'linux', package: 'tar.gz (linux_x64)');
      expect(t, SelfUpdateTarget.linuxTarball);
      expect(t.assetName, 'airclone-linux-x64.tar.gz');
    });
  });

  group('direct downloads that cannot', () {
    /// Both Flatpaks: the Flathub one updates through Flathub, and the release
    /// bundle cannot update itself at all. Neither can replace its own files
    /// from inside the sandbox.
    test('a Flatpak, marked or not', () {
      expect(
        target(os: 'linux', package: 'Flatpak (Flathub) (linux_x64)'),
        SelfUpdateTarget.unsupported,
      );
      expect(
        target(os: 'linux', package: 'Flatpak (release bundle) (linux_x64)'),
        SelfUpdateTarget.unsupported,
      );
    });

    test('a Snap', () {
      expect(
        target(os: 'linux', package: 'Snap (linux_x64)'),
        SelfUpdateTarget.unsupported,
      );
    });

    /// A sideloaded MSIX is still an MSIX: its own installer owns it, and
    /// replacing files inside the package breaks its signature.
    test('an MSIX that did not come from the Store', () {
      expect(
        target(os: 'windows', package: 'MSIX package (windows_x64)'),
        SelfUpdateTarget.unsupported,
      );
    });

    /// Deliberate, not an oversight. A sideloaded APK passes the channel gate,
    /// but installing one needs REQUEST_INSTALL_PACKAGES declared in EVERY
    /// build, including the Play one.
    test('a phone or a tablet, sideloaded or not', () {
      expect(
        target(os: 'android', package: 'tablet 800x1280 (android_arm64)'),
        SelfUpdateTarget.unsupported,
      );
      expect(
        target(os: 'ios', package: 'phone 393x852 (ios_arm64)'),
        SelfUpdateTarget.unsupported,
      );
    });

    test('a browser', () {
      expect(
        target(os: 'web', package: 'browser'),
        SelfUpdateTarget.unsupported,
      );
    });

    /// An unrecognised package must refuse rather than guess: guessing means
    /// downloading the wrong asset and installing it over something else.
    test('a package nobody has taught it about', () {
      expect(
        target(os: 'linux', package: 'nix store (linux_x64)'),
        SelfUpdateTarget.unsupported,
      );
      expect(target(os: 'linux', package: ''), SelfUpdateTarget.unsupported);
      expect(
        target(os: 'plan9', package: 'AppImage'),
        SelfUpdateTarget.unsupported,
      );
    });
  });

  group('the asset name', () {
    test('every supported target names one, and unsupported names none', () {
      for (final t in SelfUpdateTarget.values) {
        if (t == SelfUpdateTarget.unsupported) {
          expect(t.assetName, isNull);
          expect(t.canSelfUpdate, isFalse);
        } else {
          expect(t.assetName, isNotEmpty, reason: '$t');
          expect(t.canSelfUpdate, isTrue);
        }
      }
    });

    /// Every name has to be one release.yml actually uploads, or the download
    /// is a 404 at the worst possible moment. Read from the workflow rather
    /// than copied into this file, so renaming an asset there fails HERE
    /// instead of in someone's update six months later.
    test('the names are the ones a release actually uploads', () {
      final workflow = File('../.github/workflows/release.yml');
      if (!workflow.existsSync()) return;
      final text = workflow.readAsStringSync();
      for (final t in SelfUpdateTarget.values) {
        final name = t.assetName;
        if (name == null) continue;
        expect(
          text,
          contains(name),
          reason: '$t downloads $name, which release.yml never publishes',
        );
      }
    });
  });
}
