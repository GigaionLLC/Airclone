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
class ResizeHandle extends StatelessWidget {
  const ResizeHandle({super.key, required this.axis, required this.onDelta});

  final Axis axis;

  /// Pixel movement along [axis] (positive = right / down).
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final horizontal = axis == Axis.horizontal;

    // A ~8px grab band (comfortable for touch) with a 1px centred divider line.
    final line = horizontal
        ? SizedBox(
            width: 8,
            child: Center(child: Container(width: 1, color: c.border)),
          )
        : SizedBox(
            height: 8,
            child: Center(child: Container(height: 1, color: c.border)),
          );

    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: horizontal ? (d) => onDelta(d.delta.dx) : null,
        onVerticalDragUpdate: horizontal ? null : (d) => onDelta(d.delta.dy),
        child: line,
      ),
    );
  }
}
