import 'dart:io';

import 'package:airclone/src/state/install_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// The store-routing rules behind the v0.6.0 Microsoft Store certification
/// failure (policy 10.2.5: a Store product must update only through the Store).
/// The detection itself needs a device; what is pinned here is the mapping —
/// which installers count as store-managed, and what link each one gets.
void main() {
  group('androidInstallSource', () {
    const pkg = 'com.gigaionllc.airclone';

    test('Play Store install is managed and deep-links into Play', () {
      final s = androidInstallSource('com.android.vending', pkg);
      expect(s.channel, InstallChannel.playStore);
      expect(s.managedByStore, isTrue);
      expect(s.storeUrl, 'market://details?id=$pkg');
    });

    test('legacy Play installer id is still Play', () {
      expect(
        androidInstallSource('com.google.android.feedback', pkg).channel,
        InstallChannel.playStore,
      );
    });

    test('Amazon, F-Droid and Galaxy each get their own scheme', () {
      expect(
        androidInstallSource('com.amazon.venezia', pkg).storeUrl,
        'amzn://apps/android?p=$pkg',
      );
      expect(
        androidInstallSource('org.fdroid.fdroid', pkg).storeUrl,
        'fdroid.link://details?id=$pkg',
      );
      expect(
        androidInstallSource('com.sec.android.app.samsungapps', pkg).storeUrl,
        'samsungapps://ProductDetail/$pkg',
      );
    });

    test('a sideloaded APK stays on the direct-download path', () {
      // `adb install` leaves no installer; a file manager sets the system
      // package installer. Neither is a store, so the GitHub release check —
      // which is exactly what these users installed the app for — still runs.
      for (final installer in <String?>[
        null,
        '',
        'com.android.packageinstaller',
        'com.google.android.packageinstaller',
        'com.some.filemanager',
      ]) {
        final s = androidInstallSource(installer, pkg);
        expect(
          s.channel,
          InstallChannel.directDownload,
          reason: 'installer=$installer',
        );
        expect(s.managedByStore, isFalse);
      }
    });
  });

  group('linuxInstallSource', () {
    test('Flatpak and Snap own their own updates', () {
      expect(
        linuxInstallSource({'FLATPAK_ID': 'com.gigaion.Airclone'}).channel,
        InstallChannel.flathub,
      );
      expect(
        linuxInstallSource({'SNAP': '/snap/airclone/12'}).channel,
        InstallChannel.snapStore,
      );
    });

    test('a plain tarball is a direct download', () {
      expect(
        linuxInstallSource(const {}).channel,
        InstallChannel.directDownload,
      );
      // An empty value is not a Flatpak — treat it as absent.
      expect(
        linuxInstallSource(const {'FLATPAK_ID': '', 'SNAP': ''}).channel,
        InstallChannel.directDownload,
      );
    });
  });

  group('microsoftStoreUrl', () {
    test('deep-links to the product page when the PFN is known', () {
      expect(
        microsoftStoreUrl('Gigaion.Airclone_abc123'),
        'ms-windows-store://pdp/?PFN=Gigaion.Airclone_abc123',
      );
    });

    test('falls back to the Store updates page without a PFN', () {
      // Never a download link: the fallback still lands the user where an
      // update is actually applied.
      for (final pfn in <String?>[null, '']) {
        expect(
          microsoftStoreUrl(pfn),
          'ms-windows-store://downloadsandupdates',
        );
      }
    });
  });

  group('windowsPackageFamilyName', () {
    test('returns null for an unpackaged process', () {
      // The test runner is never MSIX-packaged, so this exercises the real
      // GetCurrentPackageFamilyName call (on Windows) and its non-Windows
      // short-circuit elsewhere. What matters is that neither path throws or
      // leaks the allocation — a crash here would take the whole Settings
      // panel down on the one build that must not crash: the Store one.
      expect(windowsPackageFamilyName(), isNull);
      expect(Platform.isWindows || windowsPackageFamilyName() == null, isTrue);
    });
  });

  group('macAppStoreReceiptPresent', () {
    const exe = '/Applications/Airclone.app/Contents/MacOS/airclone';

    test('true when the bundle carries a _MASReceipt', () {
      expect(
        macAppStoreReceiptPresent(
          exe,
          (p) => p == '/Applications/Airclone.app/Contents/_MASReceipt/receipt',
        ),
        isTrue,
      );
    });

    test('false for a direct download (dmg) with no receipt', () {
      expect(macAppStoreReceiptPresent(exe, (_) => false), isFalse);
    });

    test('short/odd executable paths never crash', () {
      expect(macAppStoreReceiptPresent('airclone', (_) => true), isFalse);
    });
  });
}
