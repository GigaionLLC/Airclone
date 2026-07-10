import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/headless/headless_runner.dart';
import 'src/state/android_native.dart';
import 'src/state/window_backdrop.dart';
import 'src/ui/app.dart';

Future<void> main(List<String> args) async {
  // Headless background entrypoint (`--run-task <id>` / `--run-due`), invoked by
  // the OS scheduler registrations. It boots the engine and runs saved tasks
  // with NO UI, so it must branch before any window/backdrop init: the
  // flutter_acrylic pre-frame backdrop sequence below has no window to tint here
  // and, on mobile, hangs before the first frame (see cc9d330 +
  // window_backdrop.dart). runHeadless owns its own binding init and exits the
  // process, so this never returns.
  if (isHeadlessInvocation(args)) {
    return runHeadless(args);
  }
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // libmpv backend for video/audio previews
  // Android: resolve the real shared-storage root (multi-user aware) before
  // the location providers build. No-op elsewhere.
  await initAndroidStorageRoot();
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
