import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A dialog body that is [width] wide when there is room, and shrinks to fit
/// when there isn't.
///
/// Airclone's dialogs were written desktop-first as `SizedBox(width: 520, …)`
/// inside a [Dialog]. A `SizedBox` is a HARD constraint: on a phone — where the
/// dialog itself is only ~330dp wide after Material's inset padding — the body
/// is still laid out at 520, so its action Row overflows and the primary button
/// is drawn past the screen edge. That is how "Import File Config" appeared
/// broken on Android: the flow worked, but the **Merge** button was clipped, so
/// there was nothing to tap.
///
/// Sized from [MediaQuery] rather than a [LayoutBuilder], deliberately:
/// `AlertDialog` measures its content's INTRINSIC width, and a LayoutBuilder
/// cannot answer an intrinsic query ("LayoutBuilder does not support returning
/// intrinsic dimensions"), which would crash every AlertDialog that adopted it.
/// The screen-minus-inset figure is an approximation of the dialog's own
/// constraint — always a lower bound in practice, so it can only ever make the
/// body fit, never overflow. On desktop [width] is the smaller value, so
/// behaviour there is unchanged.
class DialogBody extends StatelessWidget {
  const DialogBody({
    super.key,
    required this.width,
    this.height,
    required this.child,
  });

  /// The preferred (desktop) width.
  final double width;

  /// Optional fixed height, clamped the same way — a tall dialog on a short
  /// phone screen overflows vertically for exactly the same reason.
  final double? height;

  final Widget child;

  /// Material's default dialog inset padding is 40 horizontal / 24 vertical.
  static const double _hInset = 40 * 2;

  /// The vertical inset plus a modest allowance for the dialog's own chrome
  /// (title and action rows sit outside the content on an [AlertDialog]).
  static const double _vInset = 24 * 2 + 72;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return SizedBox(
      width: math.min(width, math.max(0, screen.width - _hInset)),
      height: height == null
          ? null
          : math.min(height!, math.max(0, screen.height - _vInset)),
      child: child,
    );
  }
}
