/// Which OS-interop actions this build may offer.
///
/// Both of the things gated here spawn a SUBPROCESS, which is the one thing a
/// Mac App Store or iOS build cannot do (see [subprocessAllowedFor]). They are
/// gated rather than left to fail because a menu item that always errors is
/// worse than one that isn't there — and, on the App Store, a reviewer finding a
/// dead action is a rejection.
///
/// Note what is deliberately NOT gated: **Open with the default app**. It looks
/// like it belongs here, but it goes through `url_launcher` (NSWorkspace on
/// macOS), not a process spawn, and the sandbox permits handing off a file the
/// user granted access to. Gating it would remove a feature that works.
/// Likewise **Copy path**, which is pure clipboard.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'build_flavor.dart';

/// Whether "Reveal/Show in file manager" is available.
///
/// Implemented as `open -R` on macOS, `explorer.exe /select,` on Windows and a
/// `dbus-send` on Linux — every one of them a spawned process. There is no
/// sandbox-legal equivalent worth keeping (NSWorkspace can activate Finder at a
/// URL, but that is a different, weaker gesture and not worth a special case for
/// the first store build).
bool revealInFileManagerAllowedFor({required bool subprocessAllowed}) =>
    subprocessAllowed;

/// [revealInFileManagerAllowedFor] for the platform this binary runs on.
final revealEnabledProvider = Provider<bool>(
  (ref) =>
      revealInFileManagerAllowedFor(subprocessAllowed: subprocessAllowedHere),
);

/// Whether archive create/extract/list is available.
///
/// rclone exposes NO RC method for archives, so `ArchiveService` shells out to
/// `rclone archive` as a real subprocess. That makes it doubly impossible in a
/// store build: no subprocess, and no bundled rclone binary to be the subject of
/// one. Unlike Mount, this is not a sandbox-capability question that a future
/// entitlement could solve — it needs an RC method upstream.
bool archiveAllowedFor({required bool subprocessAllowed}) => subprocessAllowed;

/// [archiveAllowedFor] for the platform this binary runs on.
final archiveEnabledProvider = Provider<bool>(
  (ref) => archiveAllowedFor(subprocessAllowed: subprocessAllowedHere),
);
