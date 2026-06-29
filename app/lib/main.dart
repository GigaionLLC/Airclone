import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/state/window_backdrop.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // libmpv backend for video/audio previews
  // Prepare the window-effect plugin and apply the saved backdrop (if any)
  // before the first frame so there's no flash. Both are silent no-ops if the
  // effect is unsupported on this platform.
  await initWindowBackdrop();
  await applyWindowBackdrop(await loadSavedBackdrop());
  runApp(const ProviderScope(child: AircloneApp()));
}
