/// libmpv access for the native builds — see `mpv_access.dart`.
library;

import 'package:media_kit/media_kit.dart';

/// Whether [player] is backed by libmpv (always, on a native build — but the
/// platform object is media_kit's to choose, so it is checked, not assumed).
bool hasMpv(Player player) => player.platform is NativePlayer;

/// The mpv property [name] as a string, or null when there is no libmpv.
/// Throws what libmpv throws.
Future<String?> mpvGetProperty(Player player, String name) async {
  final native = player.platform;
  if (native is! NativePlayer) return null;
  return native.getProperty(name);
}

/// Sets the mpv property [name]; a no-op without libmpv. Throws what libmpv
/// throws.
Future<void> mpvSetProperty(Player player, String name, String value) async {
  final native = player.platform;
  if (native is! NativePlayer) return;
  await native.setProperty(name, value);
}

/// Runs the mpv command [args]; a no-op without libmpv. Throws what libmpv
/// throws.
Future<void> mpvCommand(Player player, List<String> args) async {
  final native = player.platform;
  if (native is! NativePlayer) return;
  await native.command(args);
}
