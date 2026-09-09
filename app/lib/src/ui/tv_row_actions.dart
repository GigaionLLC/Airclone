/// The two things a list row needs so a D-pad can move through it cleanly.
///
/// This belongs conceptually beside `tv.dart` — everything television-specific
/// in one place — and should be folded in there when that file is next touched.
/// It is separate today only to keep two concurrent changes from colliding.
///
/// The problem, reported by a Google TV user on 2026-09-09: *"when we navigate
/// on files or folder, sometimes the navigation goes on the 'three dots' on the
/// right of the screen. Not very straightforward at all."*
///
/// Directional traversal picks the next focus by geometry. A file row is one
/// focusable thing, but its trailing ⋯ button is a second one sitting in a
/// right-hand column — so pressing DOWN repeatedly can drift sideways onto that
/// column and stay there. Nothing is broken; it is simply two targets where the
/// user is aiming at one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/android_native.dart';

/// A focus node for a control that must not be a **traversal** stop on a
/// television.
///
/// `skipTraversal` leaves the node focusable and clickable — it only stops the
/// arrow keys from choosing it, which is exactly the reported problem. Off a
/// television this returns an ordinary node and nothing changes, which is why
/// every other platform is unaffected by the fix.
FocusNode tvSkippableFocusNode(String debugLabel) =>
    FocusNode(debugLabel: debugLabel, skipTraversal: androidIsTelevision);

/// Makes RIGHT open a row's action menu, on a television only.
///
/// Taking the ⋯ out of traversal would leave a television with no way to reach
/// it, so the row answers for it instead.
///
/// RIGHT specifically, because RIGHT *already* went there: the ⋯ is the nearest
/// focusable to the right of a focused row, so a right-press landed on it
/// before this existed. This does not claim a key that meant something else —
/// it makes the same destination deliberate instead of accidental, and skips
/// the intermediate state where focus sits on a 15px glyph the user did not aim
/// at. (The tab rail is to the LEFT, so nothing on that side is affected.)
///
/// Wraps rather than replaces the row's own focus: [canRequestFocus] is false,
/// so this never becomes a focus stop of its own and a key the row does not
/// consume still bubbles up to it.
class TvRowMenuKey extends StatelessWidget {
  const TvRowMenuKey({super.key, required this.onMenu, required this.child});

  /// Opens the row's actions. Given the row's own centre in global coordinates,
  /// so the menu appears over the row rather than at the pointer's last
  /// position — a television has no pointer.
  final void Function(Offset globalCentre) onMenu;

  final Widget child;

  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    if (!androidIsTelevision) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return KeyEventResult.ignored;
    onMenu(box.localToGlobal(box.size.center(Offset.zero)));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (inner) => Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => _onKey(inner, event),
      child: child,
    ),
  );
}
