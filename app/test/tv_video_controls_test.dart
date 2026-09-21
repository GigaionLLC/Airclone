import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/tv.dart';
import 'package:airclone/src/ui/tv_player_keys.dart';
import 'package:airclone/src/ui/tv_video_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_playback_fake.dart';

/// From a Google TV user, 2026-09-21: *"If we watch video we cannot skip forward
/// or backward in the video while it's playing."*
///
/// Correct, and total: `AdaptiveVideoControls` sends Android to media_kit's
/// TOUCH controls, which contain no key handling and appear only from `onTap` —
/// an input a D-pad cannot produce. A film played and the remote could only
/// leave. [TvVideoControls] is the replacement, and these are the rules that a
/// television would otherwise take a release cycle to reveal:
///
///  * nothing on screen while a film plays, so the picture is the picture;
///  * any key brings the overlay back;
///  * it auto-hides — but NEVER while paused, because a paused film with no
///    controls is a dead end with no way to resume;
///  * hiding it HANDS FOCUS BACK to the surface. `TvFocusSeed` exists to make
///    focus impossible to lose and will re-seed into a control that has just
///    been hidden, at which point `TvFocusOverlay` rings something invisible
///    and the D-pad appears dead — the same class of bug as the blue rectangle,
///    reached by a different road.
///
/// None of it needs libmpv: the overlay reads a [TvPlaybackTarget].
void main() {
  late FakeTarget target;
  late TvPlaybackController controller;

  setUp(() {
    target = FakeTarget();
    controller = TvPlaybackController(target: target, onNext: () {});
  });

  tearDown(() {
    controller.dispose();
    target.dispose();
  });

  /// A 1080p television reports 960x540dp at xhdpi — the real metric, because
  /// a control row that fits at desktop width and overflows on a TV is exactly
  /// the failure a test at the wrong size cannot see. Overflow throws here, so
  /// merely pumping at this size is itself an assertion.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          // TvFocusOverlay is present because it is present in the real app,
          // and because its covers-the-shell rule is what keeps a playing film
          // free of a focus ring around the whole screen.
          body: TvFocusOverlay(child: TvVideoControls(controller: controller)),
        ),
      ),
    );
    await tester.pump();
  }

  double opacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  /// Lets the auto-hide timer fire before the tree goes away.
  ///
  /// Not housekeeping: the test binding fails any test that leaves a Timer
  /// pending, which is a useful rule here — an overlay that arms a hide and is
  /// then torn down is exactly how a stale timer would reach a disposed
  /// controller in the app.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(
      TvPlaybackController.autoHideDelay + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a playing film shows no controls at all', (tester) async {
    await pump(tester);
    expect(controller.mode, TvControlsMode.hidden);
    expect(opacity(tester), 0);
  });

  testWidgets('any key brings the overlay back', (tester) async {
    await pump(tester);
    controller.handleKey(down(LogicalKeyboardKey.arrowUp));
    await tester.pump();
    expect(opacity(tester), 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await drain(tester);
  });

  testWidgets('it auto-hides while playing', (tester) async {
    await pump(tester);
    controller.showControls();
    await tester.pump();
    expect(opacity(tester), 1);
    await tester.pump(
      TvPlaybackController.autoHideDelay + const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
  });

  testWidgets('it never auto-hides while paused', (tester) async {
    await pump(tester);
    target.playing = false;
    controller.showControls();
    await tester.pump();
    await tester.pump(TvPlaybackController.autoHideDelay * 3);
    await tester.pump();
    expect(
      opacity(tester),
      1,
      reason: 'a paused film with no controls cannot be resumed',
    );
  });

  testWidgets('the row takes focus when it appears', (tester) async {
    await pump(tester);
    controller.showControls();
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv play/pause',
      reason: 'OK must be play/pause the moment the row is up',
    );
    await drain(tester);
  });

  testWidgets('hiding the overlay hands focus back to the surface', (
    tester,
  ) async {
    await pump(tester);
    controller.showControls();
    await tester.pumpAndSettle();
    controller.hideControls();
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv video surface',
      reason: 'focus left on a hidden control is a ring around nothing',
    );
  });

  testWidgets('the surface covers the shell, so a film plays ring-free', (
    tester,
  ) async {
    // TvFocusOverlay deliberately draws nothing for a target that spans the
    // whole shell: a ring there is four stray arcs in the corners that say
    // nothing about where the D-pad is. The surface being full-size is what
    // earns that, so it is asserted rather than assumed.
    await pump(tester);
    final surface = tester.getSize(
      find.descendant(
        of: find.byType(TvVideoControls),
        matching: find.byType(SizedBox).first,
      ),
    );
    expect(surface.width, 960);
    expect(surface.height, 540);
  });

  testWidgets('at the end of a list the dead control stays put', (
    tester,
  ) async {
    // onNext is set and onPrevious is not: a row that changes shape as you move
    // through an album is harder to aim at with a D-pad than one that does not.
    await pump(tester);
    controller.showControls();
    await tester.pump();
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.skip_previous_rounded),
          )
          .onPressed,
      isNull,
      reason: 'visible, but disabled',
    );
    await drain(tester);
  });

  testWidgets('a pending scrub is shown before it commits', (tester) async {
    // The commit is deliberately delayed so a run of presses is one ranged
    // request instead of ten; without a readout that delay looks like the
    // remote doing nothing.
    await pump(tester);
    controller.handleKey(down(LogicalKeyboardKey.arrowRight));
    await tester.pump();
    expect(find.textContaining('+10s'), findsOneWidget);
    expect(target.seeks, isEmpty);
    await tester.pump(TvPlaybackController.commitDelay * 2);
    await tester.pumpAndSettle();
    expect(target.seeks, hasLength(1));
  });

  testWidgets('a live stream says so instead of offering a dead bar', (
    tester,
  ) async {
    target.duration = Duration.zero;
    await pump(tester);
    controller.showControls();
    await tester.pump();
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    await drain(tester);
  });
}
