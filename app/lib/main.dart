import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/headless/headless_runner.dart';
import 'src/state/android_native.dart';
import 'src/state/host_platform.dart';
import 'src/state/local_locations.dart';
import 'src/state/window_backdrop.dart';
import 'src/ui/app.dart';
import 'src/ui/error_surface.dart';
import 'src/ui/popout_image_app.dart';
import 'src/webui/webui_options.dart';
import 'src/webui/webui_runner.dart';

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
  // Web UI host (`--webui`): boot the engine and serve this app's web build to
  // browsers instead of opening a window. Branches here for the same reasons as
  // the headless runner above — it owns its own binding init, never calls
  // runApp, and must not touch the pre-frame backdrop sequence — and it never
  // returns. The `!HostPlatform.isWeb` guard is a compile-time constant, so in
  // the browser build this branch and the server behind it are eliminated
  // entirely: the page you are looking at cannot also be the thing serving it.
  if (!HostPlatform.isWeb && isWebUiInvocation(args)) {
    return runWebUi(args);
  }
  WidgetsFlutterBinding.ensureInitialized();
  installVisibleErrorWidget();
  // Pop-out image sub-window (desktop only). desktop_multi_window spins up a
  // SECOND FlutterEngine in THIS process for each popped-out image; that engine
  // re-runs main(), but its payload arrives via the plugin channel
  // (WindowController.fromCurrentEngine().arguments), NOT argv — so it never
  // trips the argv-based headless check above, and the PRIMARY window (empty
  // arguments) simply falls through to the normal launch. This branch must run
  // BEFORE MediaKit/backdrop/Android-init/ProviderScope: a pop-out is a bare
  // image viewer that reuses this process's rcd (via the URL + auth header
  // baked into its args) and needs none of that init. It must never call
  // exit()/quit() — see popout_image_app.dart. Guarded to desktop so mobile
  // never touches the plugin channel.
  if (HostPlatform.isWindows || HostPlatform.isMacOS || HostPlatform.isLinux) {
    final popoutArgs = await readPopoutImageArgs();
    if (popoutArgs != null) {
      runApp(PopoutImageApp(args: popoutArgs));
      return;
    }
  }
  MediaKit.ensureInitialized(); // libmpv backend for video/audio previews
  // Android: resolve the real shared-storage root (multi-user aware) before
  // the location providers build. No-op elsewhere.
  await initAndroidStorageRoot();
  // Android: TV or not, which decides the shell. No-op elsewhere.
  await initAndroidIsTelevision();
  // iOS: resolve the app's Documents directory, which is the whole of "local"
  // there. Same reason as above - the location providers stay synchronous.
  await initIosDocumentsRoot();
  if (HostPlatform.isWindows || HostPlatform.isMacOS || HostPlatform.isLinux) {
    // Prepare the window-effect plugin and apply the saved backdrop (if any)
    // before the first frame so there's no flash. Desktop only: on mobile the
    // acrylic plugin would hang the app before the first frame (see
    // window_backdrop.dart), and there is no window to tint anyway.
    await initWindowBackdrop();
    await applyWindowBackdrop(await loadSavedBackdrop());
  }
  runApp(const ProviderScope(child: AircloneApp()));
}
