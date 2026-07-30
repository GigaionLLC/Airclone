// AppExitResponse (the onExitRequested return) lives in dart:ui — services.dart
// only ever refers to it prefixed, so it is not re-exported by material.
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/engine_controller.dart';
import '../state/settings_controller.dart';
import '../state/skin.dart';
import '../state/window_backdrop.dart';
import 'home_screen.dart';
import 'theme/app_theme.dart';

/// Application root: themes (mode driven by settings) + the home shell.
class AircloneApp extends ConsumerStatefulWidget {
  const AircloneApp({super.key});

  @override
  ConsumerState<AircloneApp> createState() => _AircloneAppState();
}

class _AircloneAppState extends ConsumerState<AircloneApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Desktop: shut the rclone engine down BEFORE the process goes away.
    // `EngineController`'s `ref.onDispose(quit)` never runs on a window close —
    // the ProviderScope is not disposed, the process simply ends — and on Windows
    // a child outlives its parent, so `rcd` was left running after every close.
    // Beyond the leak, the orphan holds an open handle on `rclone.exe` *inside
    // the install directory*, which is why an uninstall left files behind in
    // `C:\Program Files\Airclone` (Microsoft Store certification failed the
    // product on that, 2026-07-29 — policy 10.2.7, clean removal).
    //
    // The Windows runner already forwards WM_CLOSE to the engine
    // (`HandleTopLevelWindowProc` in windows/runner/flutter_window.cpp), so
    // `onExitRequested` is what the platform actually calls. Mobile never sends
    // it, so this needs no platform guard. [WindowsChildJob] covers the
    // *disorderly* exits this hook cannot see.
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Always answers [AppExitResponse.exit] — the close is never cancelled, we
  /// only take the chance to stop `rcd` first. Bounded and failure-tolerant:
  /// `quit()` has its own internal timeouts and the outer one guarantees a wedged
  /// engine can never leave the window hanging (a user clicking X and getting
  /// nothing is far worse than a stray process, which the job object reaps).
  Future<AppExitResponse> _onExitRequested() async {
    try {
      await ref
          .read(engineControllerProvider)
          .client
          ?.quit()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      /* nothing left to do but exit */
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(
      settingsControllerProvider.select((s) => s.themeMode),
    );
    final skin = ref.watch(skinProvider);
    final backdrop = ref.watch(windowBackdropProvider);
    // A translucent backdrop (Mica/Acrylic) only shows if the app paints behind
    // it transparently — drop the scaffold/canvas fill so the OS material reads.
    final translucent =
        backdrop == WindowBackdrop.mica || backdrop == WindowBackdrop.acrylic;
    ThemeData withBackdrop(ThemeData t) => translucent
        ? t.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            canvasColor: Colors.transparent,
          )
        : t;
    return MaterialApp(
      title: 'Airclone',
      debugShowCheckedModeBanner: false,
      theme: withBackdrop(AppTheme.build(skin, Brightness.light)),
      darkTheme: withBackdrop(AppTheme.build(skin, Brightness.dark)),
      themeMode: mode,
      home: const HomeScreen(),
    );
  }
}
