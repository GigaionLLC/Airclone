import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'build_flavor.dart';

/// The single enterprise kill-switch for the Serve feature. Defaults to enabled;
/// an MDM / managed-config / policy source can later override this provider to
/// disable serving fleet-wide. Every serve entry point — the toolbar button, the
/// dialog, and `ServeController.start()` itself — checks this one provider, so
/// flipping it to false hides the UI and refuses new servers (while
/// `panicStopAll()` stays callable to tear down anything already running).
///
/// Also folded in here: the **Mac App Store** build cannot offer this feature at
/// all - the MAS entitlement set deliberately omits com.apple.security.network.server.
/// Gating it at this one provider means every existing entry point already
/// honours it, and a MAS build hides the UI rather than failing at runtime.
/// See state/build_flavor.dart and dev/plans/apple-appstore-plan.md Gate C1.
final serveEnabledProvider = Provider<bool>((ref) => !kMacAppStoreBuild);
