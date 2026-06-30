import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Enterprise kill-switch for the Mount feature (parallels [serveEnabledProvider]).
/// Defaults to enabled; a managed-config/MDM source can override it to disable
/// mounting fleet-wide. Checked by the toolbar button, the dialog, and
/// `MountController.mount()` itself so it can't be bypassed.
final mountEnabledProvider = Provider<bool>((ref) => true);
