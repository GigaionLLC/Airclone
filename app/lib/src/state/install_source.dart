/// How THIS copy of Airclone was installed — and therefore where its updates
/// must come from.
///
/// Airclone ships through several channels from one codebase: the Microsoft
/// Store (MSIX), Google Play, the Apple App Store, Flathub/Snap, and plain
/// downloads from the GitHub releases page. The binaries are identical, so
/// nothing at compile time tells them apart; each channel is detected at
/// RUNTIME here.
///
/// This is not cosmetic. Microsoft Store policy **10.2.5** ("Installing and
/// Updating Store Apps") requires a Store-distributed product to update only
/// through the Store — Airclone's v0.6.0 submission failed certification
/// precisely because its "Check for updates" offered an "Open release" button
/// pointing at the GitHub releases page. Google Play (§"Device and Network
/// Abuse") and the App Store (§2.4.5 / 3.2.2) have the same rule. So a
/// store-managed install must never be shown a download link out of band, and
/// must not even ask GitHub what the latest version is.
///
/// The rule this file exists to enforce:
///   managed channel  -> point at the store, never at a download;
///   direct download  -> the GitHub release check, as before.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../rclone/rclone_engine.dart' show RcloneEngine;

/// The distribution channel this install came from.
enum InstallChannel {
  /// Packaged MSIX from the Microsoft Store.
  microsoftStore,

  /// Installed by the Play Store app.
  playStore,

  /// Amazon Appstore (Android, `com.amazon.venezia`).
  amazonAppstore,

  /// F-Droid (Android).
  fDroid,

  /// Samsung Galaxy Store (Android).
  galaxyStore,

  /// Apple App Store / Mac App Store (a `_MASReceipt` in the bundle, or iOS).
  appStore,

  /// Flathub (Linux, `FLATPAK_ID` in the environment).
  flathub,

  /// Snap Store (Linux, `SNAP` in the environment).
  snapStore,

  /// A plain download: the installer, the portable zip, a sideloaded APK, the
  /// `.dmg`, the tarball. Airclone updates itself by pointing at the GitHub
  /// release, which is exactly what these users asked for.
  directDownload,
}

/// Where this install's updates come from, resolved once at runtime.
@immutable
class InstallSource {
  const InstallSource({
    required this.channel,
    required this.storeName,
    this.storeUrl,
  });

  final InstallChannel channel;

  /// Display name of the channel, phrased to drop into a sentence
  /// ("updates come from **the Microsoft Store**").
  final String storeName;

  /// A deep link that opens this app's page (or the updates page) in its store.
  /// Null when the channel has no launchable deep link — the UI then explains
  /// where updates come from without offering a button, which is still correct
  /// and still never links to a download.
  final String? storeUrl;

  /// True when the platform's store owns updates, so the app must not check
  /// GitHub or surface a download link.
  bool get managedByStore => channel != InstallChannel.directDownload;

  @override
  bool operator ==(Object other) =>
      other is InstallSource &&
      other.channel == channel &&
      other.storeName == storeName &&
      other.storeUrl == storeUrl;

  @override
  int get hashCode => Object.hash(channel, storeName, storeUrl);

  @override
  String toString() => 'InstallSource($channel, url: $storeUrl)';
}

/// The direct-download fallback, used for every unrecognised install.
const InstallSource _direct = InstallSource(
  channel: InstallChannel.directDownload,
  storeName: 'the Airclone releases page',
);

/// Android installer package names that mean "a store manages this app".
/// Anything else — `com.android.packageinstaller`, a file manager, `null` for
/// an `adb install` — is a sideload, which we keep updating from GitHub.
const Map<String, InstallChannel> _androidStoreInstallers = {
  'com.android.vending': InstallChannel.playStore,
  'com.google.android.feedback': InstallChannel.playStore, // legacy Play id
  'com.amazon.venezia': InstallChannel.amazonAppstore,
  'com.amazon.mShop.android.shopping': InstallChannel.amazonAppstore,
  'org.fdroid.fdroid': InstallChannel.fDroid,
  'org.fdroid.basic': InstallChannel.fDroid,
  'com.sec.android.app.samsungapps': InstallChannel.galaxyStore,
};

/// Builds the [InstallSource] for an Android install given the package that
/// installed us and our own [packageName]. Pure so the installer-id → channel
/// mapping (and its store deep links) is unit-tested without a device.
InstallSource androidInstallSource(String? installer, String packageName) {
  final channel = _androidStoreInstallers[installer];
  switch (channel) {
    case InstallChannel.playStore:
      return InstallSource(
        channel: InstallChannel.playStore,
        storeName: 'Google Play',
        // `market:` is the Play app's own scheme — it opens the installed Play
        // client directly rather than bouncing through a browser.
        storeUrl: 'market://details?id=$packageName',
      );
    case InstallChannel.amazonAppstore:
      return InstallSource(
        channel: InstallChannel.amazonAppstore,
        storeName: 'the Amazon Appstore',
        storeUrl: 'amzn://apps/android?p=$packageName',
      );
    case InstallChannel.fDroid:
      return InstallSource(
        channel: InstallChannel.fDroid,
        storeName: 'F-Droid',
        storeUrl: 'fdroid.link://details?id=$packageName',
      );
    case InstallChannel.galaxyStore:
      return InstallSource(
        channel: InstallChannel.galaxyStore,
        storeName: 'the Galaxy Store',
        storeUrl: 'samsungapps://ProductDetail/$packageName',
      );
    default:
      // Sideloaded APK (our own release asset, or someone else's build).
      return _direct;
  }
}

/// Builds the [InstallSource] for a Linux install from the environment: Flatpak
/// and Snap both advertise themselves there, and both own their own updates.
/// Pure for testing; production passes [Platform.environment].
InstallSource linuxInstallSource(Map<String, String> env) {
  if ((env['FLATPAK_ID'] ?? '').isNotEmpty) {
    return const InstallSource(
      channel: InstallChannel.flathub,
      storeName: 'Flathub',
    );
  }
  if ((env['SNAP'] ?? '').isNotEmpty) {
    return const InstallSource(
      channel: InstallChannel.snapStore,
      storeName: 'the Snap Store',
    );
  }
  return _direct;
}

/// The Microsoft Store deep link for a packaged app, given its package family
/// name. A PFN we could read gives the product's own page; otherwise we fall
/// back to the Store's "Downloads and updates" screen, which still lands the
/// user exactly where an update is applied. Pure for testing.
String microsoftStoreUrl(String? packageFamilyName) =>
    (packageFamilyName != null && packageFamilyName.isNotEmpty)
    ? 'ms-windows-store://pdp/?PFN=$packageFamilyName'
    : 'ms-windows-store://downloadsandupdates';

/// This process's Windows package family name, or null when the app is running
/// unpackaged (the installer/zip builds). Read from the same App Model API that
/// [RcloneEngine.isStoreManaged] uses to decide packaged-ness, so the link and
/// the decision can never disagree about which build this is.
String? windowsPackageFamilyName() {
  if (!Platform.isWindows) return null;
  const errorInsufficientBuffer = 122;
  try {
    final getCurrentPackageFamilyName = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(Pointer<Uint32>, Pointer<Utf16>),
          int Function(Pointer<Uint32>, Pointer<Utf16>)
        >('GetCurrentPackageFamilyName');
    final length = malloc<Uint32>()..value = 0;
    try {
      // First call sizes the buffer (in CHARACTERS, including the terminator).
      final probe = getCurrentPackageFamilyName(length, nullptr);
      if (probe != errorInsufficientBuffer || length.value == 0) return null;
      final buffer = malloc<Uint16>(length.value).cast<Utf16>();
      try {
        if (getCurrentPackageFamilyName(length, buffer) != 0) return null;
        return buffer.toDartString();
      } finally {
        malloc.free(buffer);
      }
    } finally {
      malloc.free(length);
    }
  } catch (_) {
    // Unpackaged, or the API is unavailable — the caller falls back to the
    // Store's updates page, which needs no identity.
    return null;
  }
}

/// True when this macOS build was installed from the Mac App Store: such a
/// bundle carries a `Contents/_MASReceipt/receipt` that a direct download never
/// has. [executable] is `Platform.resolvedExecutable`
/// (`Airclone.app/Contents/MacOS/airclone`), so the receipt sits two levels up.
/// Pure (takes the path + an existence probe) so it is testable off-macOS.
bool macAppStoreReceiptPresent(
  String executable,
  bool Function(String path) exists,
) {
  final parts = executable.split('/');
  if (parts.length < 3) return false;
  // …/Contents/MacOS/<exe> -> …/Contents
  final contents = parts.sublist(0, parts.length - 2).join('/');
  return exists('$contents/_MASReceipt/receipt');
}

/// Resolves how this copy was installed. Cheap and side-effect-free; cached by
/// the provider below because packaging cannot change within a run.
Future<InstallSource> detectInstallSource() async {
  if (Platform.isWindows) {
    if (!RcloneEngine.isStoreManaged()) return _direct;
    return InstallSource(
      channel: InstallChannel.microsoftStore,
      storeName: 'the Microsoft Store',
      storeUrl: microsoftStoreUrl(windowsPackageFamilyName()),
    );
  }
  if (Platform.isAndroid) {
    String? installer;
    try {
      installer = await const MethodChannel(
        'airclone/native',
      ).invokeMethod<String>('installerPackage');
    } catch (_) {
      // Older build of the platform side, or the call failed — treat as a
      // sideload, which is the conservative (non-store) answer.
      installer = null;
    }
    final pkg = (await PackageInfo.fromPlatform()).packageName;
    return androidInstallSource(installer, pkg);
  }
  if (Platform.isIOS) {
    // iOS has no other distribution channel: App Store or TestFlight, and both
    // deliver their own updates. There is no App Store id to deep-link to until
    // Airclone actually ships there, so the UI explains without a button.
    return const InstallSource(
      channel: InstallChannel.appStore,
      storeName: 'the App Store',
    );
  }
  if (Platform.isMacOS) {
    final fromStore = macAppStoreReceiptPresent(
      Platform.resolvedExecutable,
      (p) => File(p).existsSync(),
    );
    return fromStore
        ? const InstallSource(
            channel: InstallChannel.appStore,
            storeName: 'the Mac App Store',
            storeUrl: 'macappstore://showUpdatesPage',
          )
        : _direct;
  }
  if (Platform.isLinux) return linuxInstallSource(Platform.environment);
  return _direct;
}

/// This install's channel. A [FutureProvider] because Android's answer comes
/// over a platform channel; Riverpod caches it, so the detection runs once.
final installSourceProvider = FutureProvider<InstallSource>(
  (ref) => detectInstallSource(),
);
