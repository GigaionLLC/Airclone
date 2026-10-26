// AppExitResponse (the onExitRequested return) lives in dart:ui — services.dart
// only ever refers to it prefixed, so it is not re-exported by material.
import 'dart:async';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:airclone_rc/airclone_rc.dart';
import '../rclone/models/job.dart';
import '../state/android_native.dart';
import '../state/close_to_tray.dart';
import '../state/desktop_window.dart';
import '../state/diagnostics.dart';
import '../state/engine_controller.dart';
import '../state/host_platform.dart';
import '../state/interface_scale.dart';
import '../state/jobs_controller.dart';
import '../state/mount_controller.dart';
import '../state/settings_controller.dart';
import '../state/skin.dart';
import '../state/stats_controller.dart';
import '../state/tray_controller.dart';
import '../state/tray_status.dart';
import '../state/window_backdrop.dart';
import 'close_to_tray_dialog.dart';
import 'close_with_mounts_dialog.dart';
import 'home_screen.dart';
import 'theme/app_theme.dart';
import 'tv.dart';

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
    _startTray();
  }

  /// True while a quit chosen on purpose (the tray's Quit, or "Quit" in the
  /// close-to-tray question) is on its way through [_onExitRequested], so
  /// that pass skips the close-to-tray decision and goes straight to the
  /// mounts guard.
  bool _explicitQuit = false;

  /// Desktop tray (#54). Nothing happens on mobile or the web, or on a Linux
  /// desktop without an indicator host; X then quits as it always has.
  void _startTray() {
    if (!HostPlatform.isDesktop) return;
    if (HostPlatform.isWindows) {
      ref.listenManual<bool>(
        effectiveMinimizeToTrayProvider,
        (_, enabled) => unawaited(DesktopWindow.setMinimizeToTray(enabled)),
        fireImmediately: true,
      );
    }
    final tray = ref.read(trayControllerProvider)..onQuit = _quitApp;
    // macOS: Dart cannot tell the close button from Cmd-Q (both arrive as
    // applicationShouldTerminate), so with a tray up the runner intercepts
    // the button itself and asks here instead.
    DesktopWindow.onCloseRequested(_onMacWindowClose);
    WidgetsBinding.instance.addPostFrameCallback((_) => tray.start());
  }

  /// One close decision at a time. A second X, or Cmd-Q racing the close
  /// button, joins the question already on screen instead of stacking another.
  Future<CloseAction?>? _closeDecision;
  Future<AppExitResponse>? _exitResponse;

  /// A deliberate quit: the tray's Quit, the close-to-tray question's Quit.
  /// Goes through the platform's normal exit request, so [_onExitRequested]
  /// still runs the mounts guard, unmounts, and stops the engine.
  Future<void> _quitApp() async {
    if (_explicitQuit) return;
    _explicitQuit = true;
    try {
      final r = await ServicesBinding.instance.exitApplication(
        AppExitType.cancelable,
      );
      if (r == AppExitResponse.cancel) _explicitQuit = false;
    } catch (_) {
      _explicitQuit = false;
    }
  }

  /// Something is moving or waiting: what makes "never chosen" ask once
  /// instead of quitting.
  TrayActivity _activityNow() => trayActivityFrom(
    stats: ref.read(statsProvider),
    jobs: ref.read(jobsControllerProvider),
    queuePaused: false,
    bwLimit: 'off',
    engineReady: true,
  );

  bool _jobsRunning() => ref
      .read(jobsControllerProvider)
      .any(
        (j) => j.status == JobStatus.running || j.status == JobStatus.queued,
      );

  /// What the window's close button does now: hide, quit, or (null) nothing,
  /// when the user cancelled the one-time question.
  Future<CloseAction?> _resolveClose() async {
    final activity = _activityNow();
    final action = decideClose(
      closeToTray: ref.read(closeToTrayProvider),
      trayAvailable: ref.read(trayAvailableProvider),
      busy: activity.isBusy || _jobsRunning(),
    );
    if (action != CloseAction.ask) return action;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return CloseAction.quit;
    final line = trayStatusLine(activity);
    final answer = await askCloseToTray(
      context,
      activity: line == 'Idle' ? 'Transfers are queued' : line,
    );
    switch (answer) {
      case CloseToTrayAnswer.keepRunning:
        await ref.read(closeToTrayProvider.notifier).set(true);
        return CloseAction.hideToTray;
      case CloseToTrayAnswer.quit:
        await ref.read(closeToTrayProvider.notifier).set(false);
        return CloseAction.quit;
      case CloseToTrayAnswer.cancel:
        return null;
    }
  }

  /// [_resolveClose] once for concurrent callers; the Future is cleared when
  /// it settles, so the next close starts a fresh decision.
  Future<CloseAction?> _resolveCloseOnce() {
    final pending = _closeDecision;
    if (pending != null) return pending;
    late final Future<CloseAction?> future;
    future = _resolveClose().whenComplete(() {
      if (identical(_closeDecision, future)) _closeDecision = null;
    });
    _closeDecision = future;
    return future;
  }

  /// macOS close button while the tray is up (see [_startTray]).
  Future<void> _onMacWindowClose() async {
    final action = await _resolveCloseOnce();
    if (action == CloseAction.hideToTray) {
      await DesktopWindow.hide();
    } else if (action == CloseAction.quit) {
      await _quitApp();
    }
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
      // Fatal: a framework error is a screen that failed to draw, which the
      // user cannot work around. An uncaught async error (below) often has no
      // visible effect, so it stays an error.
      logDiagnostic(
        DiagLevel.fatal,
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

  /// Cancels only for a choice the user just made: hide to the tray, keep the
  /// mounts, or cancel the close-to-tray question. Otherwise the close always
  /// goes through, and we take the chance to stop `rcd` first. Bounded and
  /// failure-tolerant:
  /// `quit()` has its own internal timeouts and the outer one guarantees a wedged
  /// engine can never leave the window hanging (a user clicking X and getting
  /// nothing is far worse than a stray process, which the job object reaps).
  Future<AppExitResponse> _onExitRequested() {
    // One exit at a time: a second close or quit while the first is still
    // asking (close-to-tray, mounted drives) shares its answer instead of
    // opening a second dialog and running the unmount/quit twice.
    final pending = _exitResponse;
    if (pending != null) return pending;
    late final Future<AppExitResponse> future;
    future = _handleExitRequest().whenComplete(() {
      if (identical(_exitResponse, future)) _exitResponse = null;
    });
    return _exitResponse = future;
  }

  Future<AppExitResponse> _handleExitRequest() async {
    // Close-to-tray (#54). Windows and Linux deliver the close button here, so
    // it is decided here; macOS routes the button to [_onMacWindowClose], and
    // what arrives here is always a real quit (Cmd-Q, the app menu, logout).
    if (!_explicitQuit && !HostPlatform.isMacOS) {
      final action = await _resolveCloseOnce();
      if (action == null) return AppExitResponse.cancel;
      if (action == CloseAction.hideToTray) {
        await DesktopWindow.hide();
        return AppExitResponse.cancel;
      }
    }
    final response = await _quitFlow();
    if (response == AppExitResponse.cancel) _explicitQuit = false;
    return response;
  }

  Future<AppExitResponse> _quitFlow() async {
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
    // Take the tray icon down too, or Windows leaves a ghost icon in the
    // notification area until the mouse passes over it.
    try {
      await ref
          .read(trayControllerProvider)
          .stop()
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      /* cosmetic */
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
    // A quit from the tray can arrive with the window hidden; the question
    // has to be seen to be answered.
    await DesktopWindow.show();
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
    final interfaceScale = ref.watch(interfaceScaleProvider);
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
      // The television affordances go HERE, not around the home screen: builder
      // wraps the Navigator, so dialogs and every other pushed route inherit
      // them. Wrapping the home screen instead left every dialog without a
      // focus ring or a seeded focus, which is what made "Import config" and
      // "Add remote" impossible to finish with a remote. `androidIsTelevision`
      // is resolved in main() before runApp and is false everywhere else, so no
      // other platform sees any of this.
      builder: (context, child) {
        final app = child ?? const SizedBox.shrink();
        // Interface size (issue #32): the binding already lays the window out
        // at this scale; MediaQuery has to agree, because MediaQuery.fromView
        // reads the raw window. 1.0 everywhere the scaled binding is not in use.
        final scaled = MediaQuery(
          data: scaleMediaQuery(MediaQuery.of(context), interfaceScale),
          child: app,
        );
        return androidIsTelevision ? TvShell(child: scaled) : scaled;
      },
      home: const HomeScreen(),
    );
  }
}
