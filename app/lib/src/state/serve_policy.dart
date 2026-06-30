import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The single enterprise kill-switch for the Serve feature. Defaults to enabled;
/// an MDM / managed-config / policy source can later override this provider to
/// disable serving fleet-wide. Every serve entry point — the toolbar button, the
/// dialog, and `ServeController.start()` itself — checks this one provider, so
/// flipping it to false hides the UI and refuses new servers (while
/// `panicStopAll()` stays callable to tear down anything already running).
final serveEnabledProvider = Provider<bool>((ref) => true);
