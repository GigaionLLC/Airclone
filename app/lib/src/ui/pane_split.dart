import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/pane_layout.dart';
import 'theme/tokens.dart';

/// A resizable two-pane split with a draggable divider between [first] and
/// [second]. [axis] == [Axis.horizontal] lays them out side-by-side (Row, drag
/// the divider left/right); [Axis.vertical] stacks them (Column, drag up/down).
///
/// The split fraction is the shared, persisted [paneSplitRatioProvider] (the
/// fraction given to [first]) — the desktop dual-pane and the phone split both
/// read/write it, so a resize in one shell is remembered everywhere. The
/// divider drag is clamped by [clampSplitRatio] so neither pane can collapse.
class PaneSplit extends ConsumerWidget {
  const PaneSplit({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
  });

  final Axis axis;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horizontal = axis == Axis.horizontal;
    // Always render the ratio clamped so a legacy/out-of-range value can't
    // collapse a pane even before the next drag re-clamps it.
    final ratio = clampSplitRatio(ref.watch(paneSplitRatioProvider));
    return LayoutBuilder(
      builder: (context, cons) {
        final extent = horizontal ? cons.maxWidth : cons.maxHeight;
        // Integer flex weights from the ratio keep the Expanded layout crisp
        // (the ~1px handle in between is a negligible slice of the extent).
        final firstFlex = (ratio * 1000).round().clamp(1, 999);
        final secondFlex = 1000 - firstFlex;
        final children = <Widget>[
          Expanded(flex: firstFlex, child: first),
          PaneResizeHandle(axis: axis, extent: extent),
          Expanded(flex: secondFlex, child: second),
        ];
        return horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
      },
    );
  }
}

/// The draggable divider between two split panes — a generalization of the
/// sidebar's resize handle (MouseRegion resize cursor + a drag that clamps and
/// persists). [axis] picks the drag direction + cursor; [extent] is the split
/// container's main-axis length, used to convert a pixel drag into a ratio
/// delta. It sits in its own thin band (no overlap with pane content), so its
/// drag never fights the panes' scroll/drag gestures in the arena.
class PaneResizeHandle extends ConsumerWidget {
  const PaneResizeHandle({super.key, required this.axis, required this.extent});

  final Axis axis;
  final double extent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResizeHandle(
      axis: axis,
      onDelta: (dPx) {
        if (extent <= 0) return;
        final current = ref.read(paneSplitRatioProvider);
        // set() clamps to [kMinSplitRatio, kMaxSplitRatio] and persists.
        ref.read(paneSplitRatioProvider.notifier).set(current + dPx / extent);
      },
    );
  }
}

/// The bare draggable divider: a resize cursor over an ~8px grab band with a
/// 1px centred line, reporting each drag as a pixel delta along [axis].
/// [PaneResizeHandle] turns that delta into a split ratio; the bottom dock
/// turns it into a height — the visuals and the hit-target stay identical.
///
/// The band LIGHTS UP under the pointer (and while being dragged). A 1px hair
/// line is indistinguishable from the borders either side of it, and a divider
/// nobody can see is a divider nobody drags: the transfers dock was reported as
/// "compacted, and I couldn't resize it" while it had been resizable all along.
/// The grab area is unchanged — only its visibility is.
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.axis,
    required this.onDelta,
    this.onDoubleTap,
    this.tooltip,
  });

  final Axis axis;

  /// Pixel movement along [axis] (positive = right / down).
  final ValueChanged<double> onDelta;

  /// Optional shortcut for "give me all of it / put it back" — the dock uses it
  /// to toggle between its default height and the tallest the shell allows.
  final VoidCallback? onDoubleTap;

  /// Optional hover hint naming what the handle resizes.
  final String? tooltip;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final horizontal = widget.axis == Axis.horizontal;
    final active = _hover || _dragging;
    // Thicker AND accent-coloured when live, so the affordance reads at a
    // glance instead of only through the cursor change (which touch never has).
    final thickness = active ? 3.0 : 1.0;
    final color = active ? c.primary : c.border;

    final line = horizontal
        ? SizedBox(
            width: 8,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: thickness,
                color: color,
              ),
            ),
          )
        : SizedBox(
            height: 8,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                height: thickness,
                color: color,
              ),
            ),
          );

    final Widget band = MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragStart: horizontal
            ? (_) => setState(() => _dragging = true)
            : null,
        onHorizontalDragEnd: horizontal
            ? (_) => setState(() => _dragging = false)
            : null,
        onHorizontalDragUpdate: horizontal
            ? (d) => widget.onDelta(d.delta.dx)
            : null,
        onVerticalDragStart: horizontal
            ? null
            : (_) => setState(() => _dragging = true),
        onVerticalDragEnd: horizontal
            ? null
            : (_) => setState(() => _dragging = false),
        onVerticalDragUpdate: horizontal
            ? null
            : (d) => widget.onDelta(d.delta.dy),
        child: line,
      ),
    );
    final tip = widget.tooltip;
    return tip == null ? band : Tooltip(message: tip, child: band);
  }
}
