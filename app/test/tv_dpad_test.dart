import 'package:airclone/src/ui/tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two reasons a Google TV remote could not finish "Import config" or
/// "Add remote", both reported by a user as "I cannot navigate to click on the
/// button Unlock":
///
///  1. a focused text field SWALLOWS ArrowUp/ArrowDown to move its caret, so
///     the D-pad can never leave it ([TvDpadEscape]);
///  2. a freshly pushed dialog route has only its FocusScopeNode focused, and
///     directional traversal with no focused widget has no origin to move from,
///     so every arrow press is a no-op ([TvFocusSeed]).
///
/// Each is paired with the un-wrapped control that demonstrates the trap, so a
/// future refactor that drops the wrapper fails here rather than in the field.
void main() {
  // The text-editing shortcut map is per-platform, and Android's is the one a
  // television runs — hence the variant on every key test below. Without it the
  // host platform's map applies and the trap under test may not even exist.
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  Widget form({
    required bool tv,
    required FocusNode field,
    required FocusNode button,
  }) {
    final body = Column(
      children: [
        TextField(focusNode: field, autofocus: true),
        ElevatedButton(
          focusNode: button,
          onPressed: () {},
          child: const Text('Unlock'),
        ),
      ],
    );
    return MaterialApp(
      home: Scaffold(body: tv ? TvDpadEscape(child: body) : body),
    );
  }

  testWidgets('without the TV wrapper, ArrowDown is trapped in the field', (
    tester,
  ) async {
    final field = FocusNode();
    final button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);

    await tester.pumpWidget(form(tv: false, field: field, button: button));
    await tester.pump();
    expect(field.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // The key moved the caret instead of the focus — the dead end.
    expect(field.hasFocus, isTrue);
    expect(button.hasFocus, isFalse);
  }, variant: android);

  testWidgets('TvDpadEscape lets ArrowDown reach the button below', (
    tester,
  ) async {
    final field = FocusNode();
    final button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);

    await tester.pumpWidget(form(tv: true, field: field, button: button));
    await tester.pump();
    expect(field.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(button.hasFocus, isTrue);
  }, variant: android);

  testWidgets('TvDpadEscape leaves LEFT/RIGHT to the caret', (tester) async {
    final field = FocusNode();
    final button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);

    await tester.pumpWidget(form(tv: true, field: field, button: button));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    // Fixing a typo in a passphrase must still be possible.
    expect(field.hasFocus, isTrue);
  }, variant: android);

  testWidgets('a widget that handles ArrowDown itself still wins', (
    tester,
  ) async {
    // The console's input wraps its TextField in a Focus that maps arrows to
    // command-history recall. Key events bubble from the focused node OUTWARDS,
    // so that handler must still get first refusal ahead of the app-level
    // escape binding — otherwise the TV shell would silently break the console.
    final field = FocusNode();
    final button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);
    var handled = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvDpadEscape(
            child: Column(
              children: [
                Focus(
                  onKeyEvent: (_, e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.arrowDown) {
                      handled++;
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(focusNode: field, autofocus: true),
                ),
                ElevatedButton(
                  focusNode: button,
                  onPressed: () {},
                  child: const Text('Run'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(handled, 1);
    expect(button.hasFocus, isFalse);
  }, variant: android);

  Widget dialogHost({required bool tv, required FocusNode action}) {
    Widget wrap(BuildContext context, Widget? child) {
      final app = child ?? const SizedBox.shrink();
      return tv ? TvFocusSeed(child: app) : app;
    }

    return MaterialApp(
      builder: wrap,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  content: const Text('This export is encrypted.'),
                  actions: [
                    TextButton(
                      focusNode: action,
                      onPressed: () {},
                      child: const Text('Unlock'),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('without a seed, a dialog leaves focus on a bare scope', (
    tester,
  ) async {
    final action = FocusNode();
    addTearDown(action.dispose);

    await tester.pumpWidget(dialogHost(tv: false, action: action));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(action.hasFocus, isFalse);
    // A scope, not a widget: nothing for an arrow key to move away FROM.
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
  });

  testWidgets('TvFocusSeed puts focus on the dialog\'s first control', (
    tester,
  ) async {
    final action = FocusNode();
    addTearDown(action.dispose);

    await tester.pumpWidget(dialogHost(tv: true, action: action));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(action.hasFocus, isTrue);
  });
}
