import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/state/window_backdrop.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // libmpv backend for video/audio previews
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    // Prepare the window-effect plugin and apply the saved backdrop (if any)
    // before the first frame so there's no flash. Desktop only: on mobile the
    // acrylic plugin would hang the app before the first frame (see
    // window_backdrop.dart), and there is no window to tint anyway.
    await initWindowBackdrop();
    await applyWindowBackdrop(await loadSavedBackdrop());
  }
  runApp(const ProviderScope(child: AircloneApp()));
}
