/// Web build of the libmpv seam — see `mpv_access.dart`. The browser's
/// `<video>` element is the player here; there is no libmpv to ask.
library;

import 'package:media_kit/media_kit.dart';

/// False: a browser has no libmpv.
bool hasMpv(Player player) => false;

/// Null: nothing to read.
Future<String?> mpvGetProperty(Player player, String name) async => null;

/// Nothing to set.
Future<void> mpvSetProperty(Player player, String name, String value) async {}

/// Nothing to run.
Future<void> mpvCommand(Player player, List<String> args) async {}
