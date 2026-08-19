/// What KIND of build this binary is — decided at COMPILE time.
///
/// Distinct from [InstallChannel] in `install_source.dart`, which detects at
/// RUNTIME where an already-built binary was installed from. Both exist because
/// they answer different questions:
///
/// - *"Where do my updates come from?"* is a runtime question. One macOS binary
///   can legitimately arrive as a `.dmg` download or (in principle) a store
///   package, so `install_source.dart` sniffs for a `_MASReceipt` and adjusts.
/// - *"May I spawn a subprocess?"* is a BUILD question. The Mac App Store binary
///   is signed with the App Sandbox entitlement and must not contain the spawn
///   path at all; the `.dmg` binary must keep it. That is not a preference a
///   running app can discover — it is baked into how the artifact was signed.
///
/// So this flag is set once, on the build command line:
///
///     flutter build macos --dart-define=AIRCLONE_MAS=true
///
/// `bool.fromEnvironment` is a compile-time constant, so the branches it guards
/// are const-folded and the unreachable path is tree-shaken out of the binary —
/// which is precisely what a sandboxed store build needs. Defaults to `false`,
/// so every existing build (DMG, Windows, Linux, Android) is unchanged.
///
/// See `dev/plans/apple-appstore-plan.md` Gate C1.
library;

import 'dart:io';

/// True only in a Mac App Store build (`--dart-define=AIRCLONE_MAS=true`).
const bool kMacAppStoreBuild = bool.fromEnvironment('AIRCLONE_MAS');

/// Whether this build may `fork`/`exec` a bundled rclone binary.
///
/// Pure and parameterised rather than reading the globals directly, so the
/// policy is unit-testable without a MAS build or an iOS device — the same
/// shape as [resolveEngineMode] in `engine_mode.dart`, which consumes this.
///
/// - **Mac App Store:** forbidden. A sandboxed app may only execute code that
///   was bundled and signed with it, and an `inherit`-sandboxed child cannot
///   receive the security-scoped folder grants the parent holds — so rclone,
///   which does all the local file I/O, would be unable to read the very
///   folders the user just picked.
/// - **iOS:** forbidden outright by the OS; there is no subprocess API at all.
/// - **Everywhere else:** allowed, and still the default engine.
bool subprocessAllowedFor({required bool macAppStore, required bool isIOS}) =>
    !macAppStore && !isIOS;

/// [subprocessAllowedFor] applied to the platform this binary is running on.
bool get subprocessAllowedHere =>
    subprocessAllowedFor(macAppStore: kMacAppStoreBuild, isIOS: Platform.isIOS);

/// Whether this build must keep its rclone config in APP-PRIVATE storage, at a
/// path we choose explicitly, rather than letting rclone resolve its own default.
///
/// Note what this is NOT about: under the macOS App Sandbox `$HOME` is already
/// redirected into the app's container, so rclone's default
/// `$HOME/.config/rclone/rclone.conf` is perfectly writable there. Nothing is
/// blocked. The reason to be explicit is that several features need to *locate*
/// the active config file, and the way they do it today is
/// `Process.run(rclone, ['config', 'file'])` - a subprocess, which a sandboxed
/// or iOS build cannot spawn. Without an explicit path, config backup, restore
/// and "export exact copy" all fail with "Couldn't locate the config" on a build
/// that is otherwise working fine.
///
/// - **Android** already does this, for a stronger reason: its sandbox genuinely
///   has nowhere else the engine may read a config from.
/// - **Mac App Store / iOS** join it, so the path is known without spawning.
/// - **Desktop** keeps rclone's own default, so Airclone and the `rclone` CLI
///   share one config - which is the whole point on a machine that has both.
bool configMustBeAppPrivateFor({
  required bool isAndroid,
  required bool macAppStore,
  required bool isIOS,
}) => isAndroid || macAppStore || isIOS;

/// [configMustBeAppPrivateFor] applied to the platform this binary is running on.
bool get configMustBeAppPrivateHere => configMustBeAppPrivateFor(
  isAndroid: Platform.isAndroid,
  macAppStore: kMacAppStoreBuild,
  isIOS: Platform.isIOS,
);
