import 'package:airclone/src/ui/media_preview.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// From a Google TV user, 2026-09-09: *"when we listen music on the player we
/// cannot navigate to the previous or next song."* A remote has no swipe and no
/// click target, so an audio player with only play/pause is one you cannot get
/// out of without leaving the screen.
///
/// [MediaPreviewBody] itself needs a real libmpv player, so the decision these
/// buttons make lives in a widget that does not.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onPrevious,
    VoidCallback? onNext,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AudioSkipButton(
              direction: SkipDirection.previous,
              onPrevious: onPrevious,
              onNext: onNext,
            ),
            AudioSkipButton(
              direction: SkipDirection.next,
              onPrevious: onPrevious,
              onNext: onNext,
            ),
          ],
        ),
      ),
    ),
  );

  bool enabled(WidgetTester tester, IconData icon) =>
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
          .onPressed !=
      null;

  testWidgets('a lone file gets no skip controls at all', (tester) async {
    // Both callbacks null means the host passed no sibling list. Two
    // permanently dead buttons would be worse than none, and every caller that
    // has not opted in keeps the row it had.
    await pump(tester);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('in the middle of a list, both directions work', (tester) async {
    var back = 0;
    var forward = 0;
    await pump(tester, onPrevious: () => back++, onNext: () => forward++);

    expect(enabled(tester, Icons.skip_previous_rounded), isTrue);
    expect(enabled(tester, Icons.skip_next_rounded), isTrue);

    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(back, 1);
    expect(forward, 1);
  });

  testWidgets('at the first track, Previous is disabled but still there', (
    tester,
  ) async {
    // Disabled rather than hidden: a control row that changes shape as you move
    // through an album is harder to aim at with a D-pad than one that stays put.
    await pump(tester, onNext: () {});
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(enabled(tester, Icons.skip_previous_rounded), isFalse);
    expect(enabled(tester, Icons.skip_next_rounded), isTrue);
  });

  testWidgets('at the last track, Next is disabled but still there', (
    tester,
  ) async {
    await pump(tester, onPrevious: () {});
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(enabled(tester, Icons.skip_next_rounded), isFalse);
    expect(enabled(tester, Icons.skip_previous_rounded), isTrue);
  });

  testWidgets('both buttons are reachable by a D-pad', (tester) async {
    // The whole point is a remote, so they must be focusable — an IconButton
    // with a null onPressed is not, which is why the END states keep the other
    // button live rather than disabling the pair.
    await pump(tester, onPrevious: () {}, onNext: () {});
    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(buttons.length, 2);
    expect(buttons.every((b) => b.onPressed != null), isTrue);
  });
}
