/// May THIS copy of Airclone install an update over itself, and which file
/// would it download?
///
/// Two separate questions decide it, and both already have an answer elsewhere:
///
///   * WHERE it came from ([InstallChannel], install_source.dart). A store
///     delivers its own updates, and Microsoft policy 10.2.5, Google Play and
///     the App Store all forbid an app shipping its own - Airclone's v0.6.0
///     submission failed certification for merely LINKING to a download. So
///     every managed channel is refused here, before anything else is
///     considered.
///   * WHICH PACKAGE it is ([currentBuildKind], build_kind.dart). One channel
///     covers several packages that install in completely different ways: the
///     AppImage is a single file to replace, the tar.gz is a directory tree, the
///     Windows installer can rerun itself silently, and the portable zip has no
///     installer at all.
///
/// Mobile is refused on purpose, not by omission. A sideloaded APK is a direct
/// download and would pass the channel gate, but installing one needs
/// REQUEST_INSTALL_PACKAGES - a permission that would have to be declared in
/// EVERY build including the Play one, for a path Play scrutinises and phone
/// makers discourage. The web build has nothing to install.
library;

import '../state/host_platform.dart';
import '../state/install_source.dart';
import '../state/build_kind.dart';

/// What kind of self-update this copy can do, if any.
enum SelfUpdateTarget {
  /// Windows, installed by the Inno setup: rerun the new setup silently.
  windowsInstaller,

  /// Windows, unpacked from the portable zip: swap the files.
  windowsPortable,

  /// macOS, downloaded directly: swap the .app bundle.
  macApp,

  /// Linux AppImage: one file, replaced in place.
  linuxAppImage,

  /// Linux tar.gz: a directory tree, swapped.
  linuxTarball,

  /// Everything else: a store owns updates, or the package cannot be replaced
  /// from inside itself. The app still says a new version exists; it just does
  /// not offer to install it (and says nothing at all for a store build).
  unsupported,
}

extension SelfUpdateTargetX on SelfUpdateTarget {
  bool get canSelfUpdate => this != SelfUpdateTarget.unsupported;

  /// The release asset this target downloads, exactly as `release.yml` names it.
  /// Null when nothing is downloadable.
  ///
  /// macOS takes the `.zip` rather than the `.dmg`: both are published and both
  /// are notarized, but a zip is unpacked with no disk image to mount, attach
  /// and detach - three more ways for an update to strand a user.
  String? get assetName => switch (this) {
    SelfUpdateTarget.windowsInstaller => 'airclone-setup-x64.exe',
    SelfUpdateTarget.windowsPortable => 'airclone-windows-x64.zip',
    SelfUpdateTarget.macApp => 'airclone-macos.zip',
    SelfUpdateTarget.linuxAppImage => 'Airclone-x86_64.AppImage',
    SelfUpdateTarget.linuxTarball => 'airclone-linux-x64.tar.gz',
    SelfUpdateTarget.unsupported => null,
  };
}

/// Decides the target from facts a test can supply.
///
/// [packageKind] is [currentBuildKind]'s answer with its architecture suffix
/// still attached, because that is what the diagnostics report carries and
/// having one spelling of "which package is this" beats two.
SelfUpdateTarget selfUpdateTargetFor({
  required bool managedByStore,
  required String operatingSystem,
  required String packageKind,
}) {
  // A store owns updates. This is first for a reason: no later branch may
  // second-guess it, and a store build must not even ask what is available.
  if (managedByStore) return SelfUpdateTarget.unsupported;

  final package = packageKind.split(' (').first.trim();
  return switch (operatingSystem) {
    'windows' => switch (package) {
      'installer' => SelfUpdateTarget.windowsInstaller,
      'portable zip' => SelfUpdateTarget.windowsPortable,
      // An MSIX outside the Store is still an MSIX: the App Installer owns it,
      // and replacing its files from inside the package would break its
      // signature.
      _ => SelfUpdateTarget.unsupported,
    },
    'macos' => switch (package) {
      'app bundle' => SelfUpdateTarget.macApp,
      _ => SelfUpdateTarget.unsupported,
    },
    'linux' => switch (package) {
      'AppImage' => SelfUpdateTarget.linuxAppImage,
      'tar.gz' => SelfUpdateTarget.linuxTarball,
      // A Flatpak or a Snap updates through its own store, and could not
      // replace itself from inside the sandbox even if it wanted to. The
      // release-bundle Flatpak has no updater at all - the app says so rather
      // than pretending.
      _ => SelfUpdateTarget.unsupported,
    },
    // Android, iOS, the browser.
    _ => SelfUpdateTarget.unsupported,
  };
}

/// The target for the running process.
SelfUpdateTarget currentSelfUpdateTarget(InstallSource source) =>
    selfUpdateTargetFor(
      managedByStore: source.managedByStore,
      operatingSystem: HostPlatform.operatingSystem,
      packageKind: currentBuildKind(),
    );
