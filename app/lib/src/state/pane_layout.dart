import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dual-pane layout state: the persisted split *ratio* (how the two panes share
/// the work area), the persisted *orientation* choice, and the phone-only
/// opt-in split toggle. The pure helpers below (clamp/resolve/cycle) are kept
/// free of Riverpod/BuildContext so they can be unit-tested in isolation.

/// The split ratio can never let either pane collapse below this fraction of
/// the work area — dragging the divider is clamped to `[kMinSplitRatio,
/// kMaxSplitRatio]` so both panes always stay usable.
const double kMinSplitRatio = 0.2;
const double kMaxSplitRatio = 0.8;

/// The bottom Transfers / Recent-activity dock can never be dragged shorter
/// than this (its tab strip plus a couple of rows stay readable) nor taller
/// than [kMaxJobsDockFraction] of the work area (the file panes must survive).
const double kMinJobsDockHeight = 90;
const double kMaxJobsDockFraction = 0.8;

/// Default dock height — what the dock was fixed at before it became
/// resizable, so an existing install opens looking exactly the same.
const double kDefaultJobsDockHeight = 240;

/// Clamp a dock height against the [available] work-area height. [available]
/// <= 0 (a first layout pass) leaves the height alone bar the floor. Pure —
/// unit-tested.
double clampJobsDockHeight(double height, double available) {
  final max = available > 0
      ? (available * kMaxJobsDockFraction)
      : double.infinity;
  // A viewport too short for even the minimum keeps the dock at that minimum
  // rather than inverting the range (max < min would throw in clamp()).
  if (max <= kMinJobsDockHeight) return kMinJobsDockHeight;
  return height.clamp(kMinJobsDockHeight, max).toDouble();
}

/// Below this main-axis width (dp) an *adaptive* split stacks the panes
/// (Column) instead of placing them side-by-side (Row) — a phone in portrait
/// gets a top/bottom split, a wide tablet/desktop gets left/right.
const double kSideBySideBreakpoint = 600;

/// Clamp a raw split ratio so neither pane collapses. Pure — unit-tested.
double clampSplitRatio(double ratio) =>
    ratio.clamp(kMinSplitRatio, kMaxSplitRatio).toDouble();

/// How the two panes are arranged. [adaptive] picks side-by-side vs stacked
/// from the available width; the other two force one layout regardless.
enum PaneSplitOrientation {
  adaptive,
  sideBySide,
  stacked;

  String get label => switch (this) {
    PaneSplitOrientation.adaptive => 'Adaptive',
    PaneSplitOrientation.sideBySide => 'Side by side',
    PaneSplitOrientation.stacked => 'Stacked',
  };
}

/// Resolve an [orientation] + available [width] to a concrete layout axis:
/// [Axis.horizontal] = side-by-side (Row, drag the divider left/right),
/// [Axis.vertical] = stacked (Column, drag the divider up/down). Pure so the
/// width→axis decision is unit-tested without pumping a widget.
Axis resolveSplitAxis(
  PaneSplitOrientation orientation,
  double width, {
  double breakpoint = kSideBySideBreakpoint,
}) => switch (orientation) {
  PaneSplitOrientation.sideBySide => Axis.horizontal,
  PaneSplitOrientation.stacked => Axis.vertical,
  PaneSplitOrientation.adaptive =>
    width >= breakpoint ? Axis.horizontal : Axis.vertical,
};

/// The next orientation in the manual cycle (adaptive → side-by-side →
/// stacked → adaptive), used by the phone's one-button orientation control.
PaneSplitOrientation nextOrientation(PaneSplitOrientation o) => switch (o) {
  PaneSplitOrientation.adaptive => PaneSplitOrientation.sideBySide,
  PaneSplitOrientation.sideBySide => PaneSplitOrientation.stacked,
  PaneSplitOrientation.stacked => PaneSplitOrientation.adaptive,
};

/// Persisted dual-pane split ratio (fraction of the work area given to the
/// first pane — left when side-by-side, top when stacked). Default 0.5 (the
/// old fixed 50/50). Always stored/served clamped so a corrupt/legacy value
/// can never collapse a pane.
class PaneSplitRatio extends Notifier<double> {
  static const _key = 'pane_split_ratio';

  @override
  double build() {
    _load();
    return 0.5;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getDouble(_key);
      if (v != null) state = clampSplitRatio(v);
    } catch (_) {
      // keep default
    }
  }

  /// Set the ratio (clamped), then persist.
  Future<void> set(double v) async {
    final next = clampSplitRatio(v);
    if (next == state) return; // no change — skip the write/notify
    state = next;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_key, next);
    } catch (_) {
      // best-effort
    }
  }
}

/// The split fraction of the first pane (0.2..0.8), persisted across launches.
final paneSplitRatioProvider = NotifierProvider<PaneSplitRatio, double>(
  PaneSplitRatio.new,
);

/// Persisted height (dp) of the bottom Transfers / Recent-activity dock. Stored
/// unclamped-by-viewport (the work area's height isn't known here) — the widget
/// clamps against the live layout via [clampJobsDockHeight] on every build, so
/// a dock dragged tall on a big monitor doesn't swallow a small one.
class JobsDockHeight extends Notifier<double> {
  static const _key = 'jobs_dock_height';

  @override
  double build() {
    _load();
    return kDefaultJobsDockHeight;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getDouble(_key);
      if (v != null && v.isFinite) {
        state = v < kMinJobsDockHeight ? kMinJobsDockHeight : v;
      }
    } catch (_) {
      // keep default
    }
  }

  /// Set the height (floored at [kMinJobsDockHeight]), then persist.
  Future<void> set(double v) async {
    final next = v.isFinite && v > kMinJobsDockHeight ? v : kMinJobsDockHeight;
    if (next == state) return; // no change — skip the write/notify
    state = next;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_key, next);
    } catch (_) {
      // best-effort
    }
  }
}

/// The bottom dock's height in dp, persisted across launches.
final jobsDockHeightProvider = NotifierProvider<JobsDockHeight, double>(
  JobsDockHeight.new,
);

/// Persisted orientation choice for the dual-pane split (default [adaptive]).
class PaneSplitOrientationController extends Notifier<PaneSplitOrientation> {
  static const _key = 'pane_split_orientation';

  @override
  PaneSplitOrientation build() {
    _load();
    return PaneSplitOrientation.adaptive;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final name = p.getString(_key);
      if (name == null) return;
      state = PaneSplitOrientation.values.firstWhere(
        (o) => o.name == name,
        orElse: () => PaneSplitOrientation.adaptive,
      );
    } catch (_) {
      // keep default
    }
  }

  Future<void> set(PaneSplitOrientation o) async {
    if (o == state) return;
    state = o;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, o.name);
    } catch (_) {
      // best-effort
    }
  }

  /// Advance through the manual cycle (adaptive → side-by-side → stacked).
  Future<void> cycle() => set(nextOrientation(state));
}

/// The active dual-pane orientation choice.
final paneSplitOrientationProvider =
    NotifierProvider<PaneSplitOrientationController, PaneSplitOrientation>(
      PaneSplitOrientationController.new,
    );

/// Phone-only opt-in: whether the mobile browser shows a second pane. Session
/// state (default single-pane) — the desktop shell has its own dual-pane
/// toggle ([singlePaneProvider]).
final mobileSplitProvider = StateProvider<bool>((_) => false);
