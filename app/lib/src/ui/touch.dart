import 'dart:io';

import 'package:flutter/widgets.dart';

/// Whether the primary pointer is a finger (phone/tablet) rather than a mouse.
/// Touch-first surfaces open files with a single tap and use long-press where
/// desktop uses right-click; selection happens through the long-press menu.
final bool isTouchPrimary = Platform.isAndroid || Platform.isIOS;

/// Whether a text-editing field currently owns the keyboard. Plain-key
/// shortcuts (Space/Enter/Backspace…) and clipboard chords must not fire while
/// the user is typing — CallbackShortcuts sits closer to the focus leaf than
/// the framework's text-editing shortcuts and would steal the key otherwise.
bool textEditingHasFocus() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorStateOfType<EditableTextState>() != null;
}
