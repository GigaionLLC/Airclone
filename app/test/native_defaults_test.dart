import 'package:airclone/src/ui/touch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// alpha.85 "native by default" — shell shortcuts must yield to text fields.
void main() {
  testWidgets('shell key handling yields to text fields (Backspace)', (
    tester,
  ) async {
    // Regression (found by adversarial review): a matched CallbackShortcuts
    // binding consumes the event even if its callback no-ops, making the key
    // DEAD in text fields. The shell therefore handles colliding keys in a
    // Focus.onKeyEvent that returns `ignored` while a field has focus — the
    // pattern replicated here. The assertions check both sides: the action
    // must not fire AND the field must actually receive the key.
    var fired = 0;
    final controller = TextEditingController(text: 'abc');
    final bystander = FocusNode();
    addTearDown(bystander.dispose);
    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (textEditingHasFocus()) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        fired++;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            onKeyEvent: onKey,
            child: Column(
              children: [
                TextField(controller: controller),
                Focus(
                  focusNode: bystander,
                  child: const SizedBox(width: 50, height: 50),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // While typing: the shortcut must not fire AND backspace must still
    // delete a character in the field.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 3);
    expect(textEditingHasFocus(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(fired, 0);
    expect(controller.text, 'ab', reason: 'the field must receive the key');

    // Focus on a non-text widget: the shell shortcut fires.
    bystander.requestFocus();
    await tester.pump();
    expect(textEditingHasFocus(), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(fired, 1);
    expect(controller.text, 'ab');
  });
}
