import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/tv_now_playing.dart';
import 'package:airclone/src/ui/tv_player_keys.dart';
import 'package:airclone/src/ui/tv_video_controls.dart' show TvTransportRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_playback_fake.dart';

/// From a Google TV user, 2026-09-21: *"If we listen music we cannot go to the
/// next or previous track."*
///
/// The buttons existed. Production shipped them. What did not exist was any way
/// to USE them: a 480px card of 28px glyphs in the middle of a 1080p screen,
/// with the only route to a control being a hunt with the D-pad. This screen is
/// the same actions at a scale a sofa can read, and the two rules worth pinning
/// are the ones that decide whether it works on the first press:
///
///  * play/pause already holds focus, so OK works immediately;
///  * the row FITS at television metrics — the fixed-width-dialog lesson, where
///    a layout that was fine on a desktop clipped its buttons on a phone and
///    made a working feature look broken.
///
/// No libmpv and no `ProviderScope`: the screen reads a [TvPlaybackTarget], and
/// the repeat control is passed in as a widget.
void main() {
  late FakeTarget target;
  late TvPlaybackController controller;

  setUp(() {
    target = FakeTarget();
    controller = TvPlaybackController(
      target: target,
      alwaysVisible: true,
      onPrevious: () {},
      onNext: () {},
    );
  });

  tearDown(() {
    controller.dispose();
    target.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    String title = 'Aphex Twin - Xtal.flac',
    Widget? trailing,
  }) async {
    // 1080p at xhdpi, which is what a television actually reports.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TvNowPlaying(
            controller: controller,
            title: title,
            trailing: trailing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('it names the track and offers the whole transport row', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Aphex Twin - Xtal.flac'), findsOneWidget);
    // Previous and next are the reported gap; rewind/forward and play/pause
    // are what make it a player rather than two arrows.
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fast_rewind_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('play/pause holds focus, so OK works on the first press', (
    tester,
  ) async {
    await pump(tester);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv now playing play',
    );
  });

  testWidgets('the row fits at television metrics', (tester) async {
    // A RenderFlex overflow throws in a test, so this passing IS the assertion
    // — but the row is also measured, because "it rendered" and "it is all on
    // screen" are different claims.
    await pump(tester, trailing: const Icon(Icons.repeat_rounded, size: 40));
    final row = tester.getRect(find.byType(TvTransportRow));
    expect(row.left, greaterThanOrEqualTo(0));
    expect(row.right, lessThanOrEqualTo(960));
  });

  testWidgets('a long file name is clamped rather than pushing the row off', (
    tester,
  ) async {
    await pump(
      tester,
      title: 'A' * 400,
      trailing: const Icon(Icons.repeat_rounded, size: 40),
    );
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    final row = tester.getRect(find.byType(TvTransportRow));
    expect(row.bottom, lessThanOrEqualTo(540));
  });

  testWidgets('an empty name renders no title instead of a placeholder', (
    tester,
  ) async {
    // A blank line reads better from a sofa than "Unknown".
    await pump(tester, title: '');
    expect(find.byType(Text), findsWidgets); // the clocks are still there
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets('the host\'s repeat control is rendered beside the row', (
    tester,
  ) async {
    // Passed in rather than imported: repeat is a preference this screen has no
    // business reading, and taking it as a widget is what keeps this test free
    // of a ProviderScope.
    await pump(tester, trailing: const Icon(Icons.repeat_one_rounded));
    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
  });

  testWidgets('pressing next walks the sibling list', (tester) async {
    var next = 0;
    controller.onNext = () => next++;
    await pump(tester);
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(next, 1);
  });
}
