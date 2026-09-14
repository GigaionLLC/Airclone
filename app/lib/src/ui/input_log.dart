/// `--log-input`: say what the app receives from the keyboard, and where it
/// goes.
///
/// WHY THIS EXISTS. A tester on WSL could click anything and type nothing - not
/// in a filter, not anywhere - in the AppImage and the Flatpak both, while xterm
/// on the same display typed fine. From outside the app every explanation looks
/// the same, and there are three very different ones:
///
///   * no key events arrive at all (the window never has keyboard focus, or the
///     embedder is not delivering them);
///   * they arrive, but no text field holds Flutter's focus, so the shell's
///     type-to-navigate eats them (home_screen.dart gates on
///     [textEditingHasFocus]);
///   * they arrive and a field is focused, but the text never reaches it, which
///     is the input-method path.
///
/// One line per key event separates those in seconds, on the reporter's own
/// machine, without a debug build. It is off unless asked for, never consumes an
/// event, and prints no key CONTENT beyond the character itself - which is the
/// point of the exercise, so a user should treat the output like a screenshot of
/// what they typed and not paste a password into it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'touch.dart';

/// The flag, as typed on the command line.
const String kLogInputFlag = '--log-input';

/// True when this invocation asked for keyboard logging.
bool inputLoggingRequested(List<String> args) => args.contains(kLogInputFlag);

/// Installs a handler that reports every key event and where focus is.
///
/// Returns false always, so the event carries on to the app untouched: this
/// watches, it never intercepts. Safe to call more than once - the handler is
/// added once.
void startInputLogging({@visibleForTesting IOSink? out}) {
  if (_started) return;
  _started = true;
  final sink = out ?? stderr;
  sink.writeln(
    'input logging on. One line per key event: what arrived, and whether a '
    'text field was focused to receive it.',
  );
  HardwareKeyboard.instance.addHandler((KeyEvent event) {
    sink.writeln(describeKeyEvent(event, textField: textEditingHasFocus()));
    return false;
  });
}

bool _started = false;

/// The one line a key event prints. Pure, so its shape is tested.
///
/// [textField] is whether an editable widget holds focus - the single most
/// useful fact next to the key itself, because it decides whether the shell
/// treats the key as a shortcut or leaves it to the field.
String describeKeyEvent(KeyEvent event, {required bool textField}) {
  final kind = switch (event) {
    KeyDownEvent() => 'down',
    KeyUpEvent() => 'up',
    KeyRepeatEvent() => 'repeat',
    _ => 'other',
  };
  final ch = event.character;
  // A control character would garble the log; name it instead of printing it.
  final shown = (ch == null)
      ? 'none'
      : (ch.isEmpty || ch.codeUnitAt(0) < 0x20)
      ? 'control'
      : '"$ch"';
  return 'input: $kind key=${event.logicalKey.keyLabel} char=$shown '
      'textField=$textField';
}
