/// Interface size: Airclone's own zoom, on top of whatever the OS reports.
///
/// Flutter sizes everything from the window's device pixel ratio, and on Linux
/// that is GTK 3's INTEGER scale factor. On a 4K Wayland desktop where that
/// reaches the app as 1, everything is drawn 1:1 and is tiny, and the known
/// workaround (`GDK_BACKEND=x11 GDK_SCALE=2`) only works through XWayland and
/// doubles the cursor too (issue #32). This multiplies the ratio inside the
/// app instead: native on Wayland, X11, Windows and macOS, and the cursor and
/// every other app are untouched.
///
/// Two places have to agree, and both read [ScaledFlutterBinding.scale]:
///   * the binding, which lays the window out at `physical / (ratio * scale)`
///     and converts pointer positions with the same ratio, so a click lands on
///     what is drawn under it;
///   * `MaterialApp.builder`, which rescales [MediaQuery], because
///     `MediaQuery.fromView` reads the raw window and would report the
///     unscaled size.
library;

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'host_platform.dart';

/// The sizes offered in Settings.
const List<double> kInterfaceScales = [
  0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, //
];

/// Environment variable that sets the size and wins over the saved setting.
const String kInterfaceScaleEnv = 'AIRCLONE_SCALE';

const String _prefsKey = 'interface_scale';
const double _minScale = 0.5;
const double _maxScale = 3.0;

/// Parses `AIRCLONE_SCALE`: a number (`1.5`) or a percentage (`150%`).
/// Anything else, or anything outside 0.5-3.0, is ignored rather than clamped:
/// a typo should not turn into a usable-looking but wrong size.
double? parseInterfaceScale(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  var percent = false;
  if (s.endsWith('%')) {
    percent = true;
    s = s.substring(0, s.length - 1).trim();
  }
  final v = double.tryParse(s);
  if (v == null || v.isNaN || v.isInfinite) return null;
  final scale = percent ? v / 100 : v;
  if (scale < _minScale || scale > _maxScale) return null;
  return scale;
}

/// The view configuration for a window at [scale]: physical size unchanged,
/// logical size and pixel ratio adjusted together so the picture fills the
/// window exactly.
ViewConfiguration scaledViewConfiguration({
  required BoxConstraints physicalConstraints,
  required double devicePixelRatio,
  required double scale,
}) {
  final ratio = devicePixelRatio * scale;
  return ViewConfiguration(
    physicalConstraints: physicalConstraints,
    logicalConstraints: physicalConstraints / ratio,
    devicePixelRatio: ratio,
  );
}

/// [data] as the app should see it at [scale].
MediaQueryData scaleMediaQuery(MediaQueryData data, double scale) {
  if (scale == 1.0) return data;
  EdgeInsets s(EdgeInsets e) => e / scale;
  return data.copyWith(
    size: data.size / scale,
    devicePixelRatio: data.devicePixelRatio * scale,
    padding: s(data.padding),
    viewPadding: s(data.viewPadding),
    viewInsets: s(data.viewInsets),
    systemGestureInsets: s(data.systemGestureInsets),
  );
}

/// The app's binding on desktop: [WidgetsFlutterBinding] plus [scale].
class ScaledFlutterBinding extends WidgetsFlutterBinding {
  ScaledFlutterBinding._();

  static ScaledFlutterBinding? _instance;

  /// Installs this binding (once) and returns it. Must be the FIRST binding
  /// initialisation in the process, which is why main() calls it where it
  /// used to call [WidgetsFlutterBinding.ensureInitialized].
  static ScaledFlutterBinding ensureInitialized() =>
      _instance ??= ScaledFlutterBinding._();

  /// The active scale, or 1.0 when this binding is not the one installed
  /// (tests, the web build, phones).
  static double get currentScale => _instance?._scale ?? 1.0;

  double _scale = 1.0;
  double get scale => _scale;

  /// Applies a new size to every window, at the next frame.
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    handleMetricsChanged();
  }

  final Queue<PointerEvent> _pending = Queue<PointerEvent>();

  @override
  void initInstances() {
    super.initInstances();
    // Replaces GestureBinding's packet handler with one that converts using
    // the SCALED ratio. Without this, layout is scaled but clicks are not, and
    // every tap lands on whatever would be there at 100%.
    platformDispatcher.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    final view = renderView.flutterView;
    return scaledViewConfiguration(
      physicalConstraints: BoxConstraints.fromViewConstraints(
        view.physicalConstraints,
      ),
      devicePixelRatio: view.devicePixelRatio,
      scale: _scale,
    );
  }

  double? _ratioForView(int viewId) {
    final ratio = platformDispatcher.view(id: viewId)?.devicePixelRatio;
    return ratio == null ? null : ratio * _scale;
  }

  void _handlePointerDataPacket(ui.PointerDataPacket packet) {
    try {
      _pending.addAll(PointerEventConverter.expand(packet.data, _ratioForView));
      if (!locked) _flush();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'gestures library',
          context: ErrorDescription('while handling a scaled pointer packet'),
        ),
      );
    }
  }

  // Same contract as GestureBinding: events that arrive while the framework is
  // locked wait, in order, and go out as soon as it unlocks.
  @override
  void unlocked() {
    super.unlocked();
    _flush();
  }

  void _flush() {
    while (_pending.isNotEmpty) {
      handlePointerEvent(_pending.removeFirst());
    }
  }
}

/// Reads the size to start with: `AIRCLONE_SCALE` if valid, else the saved
/// setting, else 1.0. Called in main() before the first frame, so the window
/// never paints at the wrong size first.
Future<double> loadInitialInterfaceScale({
  Map<String, String>? environment,
}) async {
  final env = parseInterfaceScale(
    (environment ?? HostPlatform.environment)[kInterfaceScaleEnv],
  );
  if (env != null) return env;
  try {
    final p = await SharedPreferences.getInstance();
    final saved = p.getDouble(_prefsKey);
    if (saved != null && saved >= _minScale && saved <= _maxScale) return saved;
  } catch (_) {
    // No preferences: the default.
  }
  return 1.0;
}

/// Whether `AIRCLONE_SCALE` is set (validly) for this process. Settings says so
/// next to the control, since changing it then lasts only until the next
/// launch.
bool interfaceScaleFromEnvironment({Map<String, String>? environment}) =>
    parseInterfaceScale(
      (environment ?? HostPlatform.environment)[kInterfaceScaleEnv],
    ) !=
    null;

/// The Interface size setting.
class InterfaceScaleController extends Notifier<double> {
  @override
  double build() => ScaledFlutterBinding.currentScale;

  Future<void> set(double value) async {
    if (value < _minScale || value > _maxScale) return;
    ScaledFlutterBinding._instance?.scale = value;
    state = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_prefsKey, value);
    } catch (_) {
      // best-effort, like every other appearance preference
    }
  }
}

final interfaceScaleProvider =
    NotifierProvider<InterfaceScaleController, double>(
      InterfaceScaleController.new,
    );
