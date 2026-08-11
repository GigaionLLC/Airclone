// AppExitResponse (the onExitRequested return) lives in dart:ui — services.dart
// only ever refers to it prefixed, so it is not re-exported by material.
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/mount_info.dart';
import '../state/diagnostics.dart';
import '../state/engine_controller.dart';
import '../state/mount_controller.dart';
import '../state/settings_controller.dart';
import '../state/skin.dart';
import '../state/window_backdrop.dart';
import 'close_with_mounts_dialog.dart';
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

  /// Lets [_onExitRequested] — which runs above [MaterialApp] — put the
  /// mounts-still-active confirmation on screen.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _installErrorHooks();
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

  /// Routes framework and uncaught-async errors into the local diagnostics log
  /// (state/diagnostics.dart) so a user hitting a crash has something concrete
  /// to attach to a bug report. Purely local — nothing is transmitted — and the
  /// default handlers still run, so console output in debug is unchanged.
  void _installErrorHooks() {
    attachGlobalDiagnostics(ref.read(diagnosticsProvider.notifier));
    final priorFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      logDiagnostic(
        DiagLevel.error,
        'ui',
        details.exceptionAsString(),
        // A full stack is noise in a report; the top frames are the signal.
        detail: details.stack?.toString().split('\n').take(8).join('\n'),
      );
      priorFlutterError?.call(details);
    };
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final priorPlatformError = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      logDiagnostic(
        DiagLevel.error,
        'async',
        error.toString(),
        detail: stack.toString().split('\n').take(8).join('\n'),
      );
      return priorPlatformError?.call(error, stack) ?? false;
    };
  }

  /// Always answers [AppExitResponse.exit] — the close is never cancelled, we
  /// only take the chance to stop `rcd` first. Bounded and failure-tolerant:
  /// `quit()` has its own internal timeouts and the outer one guarantees a wedged
  /// engine can never leave the window hanging (a user clicking X and getting
  /// nothing is far worse than a stray process, which the job object reaps).
  Future<AppExitResponse> _onExitRequested() async {
    // Mounted drives are the one thing a close can take away from OTHER apps:
    // an editor with an unsaved file on X:, a copy running in Explorer. Ask
    // before pulling them out from under it. Queried fresh rather than read off
    // the 2s-polled list, so a mount made moments ago still counts.
    final mounts = await _activeMountPoints();
    if (mounts.isNotEmpty && !await _confirmCloseWithMounts(mounts)) {
      return AppExitResponse.cancel;
    }

    // Unmount FIRST, while the engine is still alive. rclone serves every OS
    // mount from the `rcd` process, so stopping the engine first strands the
    // mount: on Windows the drive letter stays in Explorer after Airclone is
    // gone, and only disappears when the app is next launched. A mount that
    // outlives the app is exactly the accident to avoid — someone can be left
    // with a live-looking drive backed by nothing.
    //
    // Bounded separately from quit() so a wedged unmount cannot eat the whole
    // budget, and swallowed: an exit must never be blocked by cleanup. The
    // disorderly-exit case (crash / taskkill) is unreachable from here and
    // stays covered by [WindowsChildJob].
    try {
      await ref
          .read(mountControllerProvider.notifier)
          .unmountAllForExit()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      /* best effort — fall through and still stop the engine */
    }
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

  /// Mount points live right now, asked of the engine directly.
  ///
  /// FAIL-OPEN: any error, timeout, or missing engine yields an empty list, so
  /// a sick engine can never trap the user in an app that refuses to close.
  /// Bounded tightly — this runs on every close, including the common case of
  /// no mounts at all.
  Future<List<String>> _activeMountPoints() async {
    try {
      final client = ref.read(engineControllerProvider).client;
      if (client == null) return const [];
      final res = await client
          .rpc('mount/listmounts')
          .timeout(const Duration(seconds: 3));
      final list = res['mountPoints'];
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (MountInfo.fromList(e).mountPoint.isNotEmpty)
            MountInfo.fromList(e).mountPoint,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// True when the user still wants to close. Fails OPEN (returns true) when
  /// there is no navigator to ask on — never strand a close behind a dialog
  /// that cannot be shown.
  Future<bool> _confirmCloseWithMounts(List<String> mounts) async {
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return true;
    return confirmCloseWithMounts(context, mounts);
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
      // The exit confirmation is raised from onExitRequested, which runs ABOVE
      // MaterialApp and so has no Navigator of its own to push a dialog onto.
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: withBackdrop(AppTheme.build(skin, Brightness.light)),
      darkTheme: withBackdrop(AppTheme.build(skin, Brightness.dark)),
      themeMode: mode,
      home: const HomeScreen(),
    );
  }
}
