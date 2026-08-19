import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'build_flavor.dart';

/// Enterprise kill-switch for the Mount feature (parallels [serveEnabledProvider]).
/// Defaults to enabled; a managed-config/MDM source can override it to disable
/// mounting fleet-wide. Checked by the toolbar button, the dialog, and
/// `MountController.mount()` itself so it can't be bypassed.
///
/// Also folded in here: the **Mac App Store** build cannot offer this feature at
/// all - FUSE is impossible under the App Sandbox, so there is nothing to degrade to.
/// Gating it at this one provider means every existing entry point already
/// honours it, and a MAS build hides the UI rather than failing at runtime.
/// See state/build_flavor.dart and dev/plans/apple-appstore-plan.md Gate C1.
final mountEnabledProvider = Provider<bool>((ref) => !kMacAppStoreBuild);
