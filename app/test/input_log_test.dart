import 'package:airclone/src/ui/input_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `--log-input`, the flag that answers "why can this machine not type?".
///
/// A tester on WSL could click anything and type nothing, in two packages that
/// share no libraries, while xterm on the same display typed fine. From outside
/// the app, "no key events arrive", "they arrive but no field is focused" and
/// "a field is focused but the text never lands" all look identical. These pin
/// the line that tells them apart.
void main() {
  group('asking for it', () {
    test('the flag turns it on', () {
      expect(inputLoggingRequested(const ['--log-input']), isTrue);
      expect(inputLoggingRequested(const ['--webui', '--log-input']), isTrue);
    });

    test('it is off by default', () {
      expect(inputLoggingRequested(const []), isFalse);
      expect(inputLoggingRequested(const ['--webui']), isFalse);
    });

    /// A flag that merely STARTS the same way is a different flag; turning
    /// logging on by accident would put keystrokes in someone's terminal.
    test('a longer flag that shares the prefix does not turn it on', () {
      expect(inputLoggingRequested(const ['--log-input-verbose']), isFalse);
      expect(inputLoggingRequested(const ['--log-inputs']), isFalse);
    });
  });

  group('the line a key event prints', () {
    KeyDownEvent down(LogicalKeyboardKey key, String? character) =>
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyZ,
          logicalKey: key,
          character: character,
          timeStamp: Duration.zero,
        );

    test('names the key, the character and where focus was', () {
      final line = describeKeyEvent(
        down(LogicalKeyboardKey.keyZ, 'z'),
        textField: true,
      );
      expect(line, contains('input:'));
      expect(line, contains('down'));
      expect(line, contains('char="z"'));
      expect(line, contains('textField=true'));
    });

    /// This is the whole diagnosis: the same keystroke, printed with
    /// textField=false, means the shell's type-to-navigate ate it instead of a
    /// field receiving it (home_screen.dart gates on exactly that).
    test('an unfocused field is stated, not implied', () {
      expect(
        describeKeyEvent(down(LogicalKeyboardKey.keyZ, 'z'), textField: false),
        contains('textField=false'),
      );
    });

    test('a key with no character says so rather than printing nothing', () {
      final line = describeKeyEvent(
        down(LogicalKeyboardKey.shiftLeft, null),
        textField: false,
      );
      expect(line, contains('char=none'));
    });

    /// A raw control character would garble the log it is meant to explain.
    test('control characters are named, not printed', () {
      final line = describeKeyEvent(
        down(LogicalKeyboardKey.enter, '\r'),
        textField: false,
      );
      expect(line, contains('char=control'));
      expect(line, isNot(contains('\r')));
    });

    test('key up is distinguished from key down', () {
      final up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyZ,
        logicalKey: LogicalKeyboardKey.keyZ,
        timeStamp: Duration.zero,
      );
      expect(describeKeyEvent(up, textField: false), contains('up'));
    });
  });
}
