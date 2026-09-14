/// WHICH PACKAGE of Airclone this copy is — the first question a bug report
/// raises, and the one nothing else in the app could answer.
///
/// [InstallChannel] (install_source.dart) deliberately lumps packages together:
/// it answers "where do updates come from", so the AppImage, the tar.gz and the
/// single-file `.flatpak` on each release are all `directDownload`, because all
/// three update from the releases page. A bug report needs the opposite cut.
/// These packages differ in exactly the ways that produce reports:
///
///   * the Flatpak mounts through a helper that runs outside its sandbox, and
///     only with a permission the user grants (flatpak_host_access.dart);
///   * the AppImage carries fallback copies of ALSA and OpenGL ES that the
///     tar.gz does not, and uses them only on a system that lacks them;
///   * the Windows installer registers an uninstaller and file associations;
///     the portable zip does neither;
///   * a tablet and a TV run the same APK as a phone, and the shell they get is
///     chosen by width — so "my tablet shows the phone layout" is a real report
///     that needs the size to check.
///
/// Every answer here is a runtime fact about THIS process, gathered from what
/// each packager already announces. Nothing device-identifying is read: no
/// model, no serial, no machine name — the same standard the rest of the
/// diagnostics report holds to (diagnostics.dart).
library;

import 'dart:io' show File, Platform;

import 'android_native.dart' show androidIsTelevision;
import 'build_flavor.dart';
import 'host_platform.dart';
import 'install_source.dart' show macAppStoreReceiptPresent;

import '../native/native_probes.dart' as native;

/// The Linux package, from the environment each packager exports into its own
/// processes. Pure so all four cases are tested without four machines.
///
/// The AppImage runtime sets `APPIMAGE` (the path of the running image) before
/// `AppRun` starts, Flatpak sets `FLATPAK_ID`, Snap sets `SNAP`. The tar.gz sets
/// nothing, which is why it is the fallthrough rather than a detection.
String linuxBuildKind(Map<String, String> environment) {
  if ((environment['APPIMAGE'] ?? '').isNotEmpty) return 'AppImage';
  // Both Flatpaks set FLATPAK_ID; only a Flathub build carries the marker. The
  // difference matters in a report: the release bundle cannot update itself.
  if (runningInFlatpak(environment)) {
    return flathubChannelMarked(environment)
        ? 'Flatpak (Flathub)'
        : 'Flatpak (release bundle)';
  }
  if ((environment['SNAP'] ?? '').isNotEmpty) return 'Snap';
  return 'tar.gz';
}

/// The Windows package. [packaged] is the App Model answer (an MSIX, whether it
/// came from the Store or a sideloaded bundle); [uninstaller] is whether Inno's
/// `unins000.exe` sits beside the executable, which is what separates an
/// installed copy from the portable zip.
String windowsBuildKind({required bool packaged, required bool uninstaller}) {
  if (packaged) return 'MSIX package';
  return uninstaller ? 'installer' : 'portable zip';
}

/// The macOS package. The `.dmg` and the `.zip` unpack to the same bundle, so
/// there is nothing to tell apart once installed — but a sandboxed Mac App Store
/// build behaves differently enough (no subprocess, no mounting) to name.
String macBuildKind({required bool masBuild, required bool receipt}) =>
    (masBuild || receipt) ? 'Mac App Store app' : 'app bundle';

/// What the user is actually holding, and which shell they got.
///
/// The mobile shell is chosen by WIDTH (`home_screen.dart`: a TV, or narrower
/// than 700), not by device class, so a tablet in a narrow split-screen gets the
/// phone layout. Naming both means a layout report can be reproduced at the
/// right size instead of guessed at.
String mobileBuildKind({
  required bool television,
  required double width,
  required double height,
}) {
  final size = '${width.round()}x${height.round()}';
  if (television) return 'TV $size';
  final shortest = width < height ? width : height;
  // 600dp is Android's own tablet threshold (the sw600dp resource qualifier).
  final device = shortest >= 600 ? 'tablet' : 'phone';
  // Only worth saying when the two disagree; a phone always gets phone layout.
  final layout = (device == 'tablet' && width < 700) ? ', phone layout' : '';
  return '$device $size$layout';
}

/// True when Inno Setup's uninstaller sits beside the running executable, which
/// it does for an installed copy and never for the portable zip.
bool windowsInstallerPresent() {
  final exe = Platform.resolvedExecutable;
  final cut = exe.lastIndexOf(Platform.pathSeparator);
  if (cut <= 0) return false;
  return File(
    '${exe.substring(0, cut)}${Platform.pathSeparator}unins000.exe',
  ).existsSync();
}

/// The label for THIS process: the package, then the architecture it was built
/// for, which is what separates the Android split APKs from each other and an
/// Apple-silicon build from an Intel one.
///
/// [width] and [height] are the window's logical size, which only the UI can
/// read; they are ignored off mobile.
String currentBuildKind({double? width, double? height}) {
  final kind = _packageKind(width: width, height: height);
  if (HostPlatform.isWeb) return kind;
  return '$kind (${native.nativeAbiName()})';
}

String _packageKind({double? width, double? height}) {
  if (HostPlatform.isWeb) return 'browser';
  if (HostPlatform.isLinux) return linuxBuildKind(HostPlatform.environment);
  if (HostPlatform.isWindows) {
    return windowsBuildKind(
      packaged: native.isWindowsPackagedApp(),
      uninstaller: windowsInstallerPresent(),
    );
  }
  if (HostPlatform.isMacOS) {
    return macBuildKind(
      masBuild: kMacAppStoreBuild,
      receipt: macAppStoreReceiptPresent(
        Platform.resolvedExecutable,
        (p) => File(p).existsSync(),
      ),
    );
  }
  if (HostPlatform.isMobile) {
    // No window size to hand (a headless caller): name the device class only,
    // rather than printing a made-up one.
    if (width == null || height == null) {
      return androidIsTelevision ? 'TV' : HostPlatform.operatingSystem;
    }
    return mobileBuildKind(
      television: androidIsTelevision,
      width: width,
      height: height,
    );
  }
  return HostPlatform.operatingSystem;
}
