import 'package:airclone/src/state/android_native.dart';
import 'package:airclone/src/ui/tv_row_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// From a Google TV user, 2026-09-09: *"when we navigate on files or folder,
/// sometimes the navigation goes on the 'three dots' on the right of the
/// screen. Not very straightforward at all."*
///
/// A row is one thing the user is aiming at, but it holds two focusable things,
/// and directional traversal picks by geometry. These pin both halves of the
/// fix: the ⋯ leaves traversal on a television, and RIGHT reaches it instead.
void main() {
  // `androidIsTelevision` is a mutable global resolved once in main(); every
  // test that touches it must put it back or it leaks into the next one.
  setUp(() => androidIsTelevision = false);
  tearDown(() => androidIsTelevision = false);

  group('tvSkippableFocusNode', () {
    test('is an ordinary node off a television', () {
      final n = tvSkippableFocusNode('actions');
      addTearDown(n.dispose);
      expect(
        n.skipTraversal,
        isFalse,
        reason: 'desktop and phone behaviour must not change',
      );
    });

    test('leaves traversal on a television, but stays focusable', () {
      androidIsTelevision = true;
      final n = tvSkippableFocusNode('actions');
      addTearDown(n.dispose);
      expect(n.skipTraversal, isTrue);
      // Focusable and clickable still — skipTraversal only stops arrow keys
      // from CHOOSING it. A TV with a pointer remote can still press it.
      expect(n.canRequestFocus, isTrue);
    });
  });

  group('TvRowMenuKey', () {
    /// A row shaped like the real one: something focusable, wrapped.
    Future<FocusNode> pumpRow(
      WidgetTester tester,
      void Function(Offset) onMenu,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvRowMenuKey(
              onMenu: onMenu,
              child: SizedBox(
                width: 400,
                height: 40,
                child: Focus(focusNode: node, child: const Text('a file')),
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      return node;
    }

    testWidgets('RIGHT opens the row actions on a television', (tester) async {
      androidIsTelevision = true;
      Offset? at;
      await pumpRow(tester, (o) => at = o);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(at, isNotNull, reason: 'RIGHT is the replacement route to the ⋯');
      // The row's own centre, so the menu lands over the row — a television has
      // no pointer position to fall back on.
      expect(at!.dx, 200);
      expect(at!.dy, 20);
    });

    testWidgets('RIGHT does nothing off a television', (tester) async {
      // Desktop and phone still reach the ⋯ by Tab or by clicking it, and a
      // right-arrow there belongs to whatever else wants it.
      Offset? at;
      await pumpRow(tester, (o) => at = o);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(at, isNull);
    });

    testWidgets('other keys are left alone, even on a television', (
      tester,
    ) async {
      androidIsTelevision = true;
      Offset? at;
      await pumpRow(tester, (o) => at = o);
      for (final k in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.enter,
      ]) {
        await tester.sendKeyEvent(k);
      }
      await tester.pump();
      expect(
        at,
        isNull,
        reason: 'UP/DOWN must still traverse and ENTER must still open',
      );
    });

    testWidgets('the wrapper never becomes a focus stop of its own', (
      tester,
    ) async {
      androidIsTelevision = true;
      final node = await pumpRow(tester, (_) {});
      // If this widget could take focus it would be a third target in a row
      // that already had one too many.
      expect(node.hasPrimaryFocus, isTrue);
      final wrapper = tester.widget<Focus>(
        find
            .descendant(
              of: find.byType(TvRowMenuKey),
              matching: find.byType(Focus),
            )
            .first,
      );
      expect(wrapper.canRequestFocus, isFalse);
    });
  });
}
