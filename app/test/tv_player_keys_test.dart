import 'package:airclone/src/ui/tv_player_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_playback_fake.dart';

/// From a Google TV user, 2026-09-21: *"If we listen music we cannot go to the
/// next or previous track. If we watch video we cannot skip forward or backward
/// in the video while it's playing."*
///
/// Two halves of one missing thing. The skip buttons had shipped and production
/// had them; what was missing on a television was any way to reach them, and for
/// video there was nothing at all — media_kit's Android controls have no key
/// handling and appear only from a tap.
///
/// [TvPlaybackController] is the answer, and the rules worth pinning are the
/// ones a television would only reveal months later: what each key means in
/// each mode, that a run of presses is ONE seek (every commit can be a fresh
/// ranged request to a cloud object), that a burst accelerates, and that an
/// unknown duration disables seeking instead of appearing to drop the press.
///
/// All of it runs on a fake, which is the point of the [TvPlaybackTarget] seam:
/// a real media_kit `Player` would initialise libmpv. See `tv_playback_fake.dart`.
void main() {
  late FakeTarget target;
  late TvPlaybackController c;
  var previous = 0;
  var next = 0;

  setUp(() {
    target = FakeTarget();
    previous = 0;
    next = 0;
    c = TvPlaybackController(
      target: target,
      onPrevious: () => previous++,
      onNext: () => next++,
    );
  });

  tearDown(() => c.dispose());

  group('the keys a remote actually has', () {
    test('play/pause, however the remote spells it', () {
      for (final key in [
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPause,
      ]) {
        final before = target.playPauseCalls;
        expect(c.handleKey(down(key)), KeyEventResult.handled);
        expect(target.playPauseCalls, before + 1, reason: '${key.debugName}');
      }
    });

    test('the track keys walk the sibling list', () {
      expect(
        c.handleKey(down(LogicalKeyboardKey.mediaTrackNext)),
        KeyEventResult.handled,
      );
      expect(
        c.handleKey(down(LogicalKeyboardKey.mediaTrackPrevious)),
        KeyEventResult.handled,
      );
      expect(next, 1);
      expect(previous, 1);
    });

    test('fast-forward and rewind are a fixed 30 seconds', () {
      c.handleKey(down(LogicalKeyboardKey.mediaFastForward));
      expect(c.pendingTarget, const Duration(minutes: 5, seconds: 30));
      c.commitPending();
      expect(target.seeks.single, const Duration(minutes: 5, seconds: 30));
    });

    test('stop pauses rather than closing', () {
      // A stream we cannot cheaply restart is worse to stop than to pause, and
      // BACK already means leave.
      expect(target.playing, isTrue);
      c.handleKey(down(LogicalKeyboardKey.mediaStop));
      expect(target.playing, isFalse);
      // Already paused: a second press must not toggle it back to playing.
      c.handleKey(down(LogicalKeyboardKey.mediaStop));
      expect(target.playing, isFalse);
    });
  });

  group('what the arrows mean depends on what is on screen', () {
    test('hidden: LEFT/RIGHT scrub', () {
      expect(c.mode, TvControlsMode.hidden);
      expect(
        c.handleKey(down(LogicalKeyboardKey.arrowRight)),
        KeyEventResult.handled,
      );
      expect(c.pendingTarget, isNotNull);
      expect(c.mode, TvControlsMode.scrubbing);
    });

    test('scrubbing: LEFT/RIGHT keep scrubbing, not traverse', () {
      // The whole reason [TvControlsMode.scrubbing] exists. If revealing the
      // overlay flipped the arrows to focus traversal, the second press of a
      // run would wander into a button instead of seeking further.
      c.handleKey(down(LogicalKeyboardKey.arrowRight));
      expect(
        c.handleKey(down(LogicalKeyboardKey.arrowRight)),
        KeyEventResult.handled,
      );
      expect(c.mode, TvControlsMode.scrubbing);
      expect(c.pendingTarget, const Duration(minutes: 5, seconds: 20));
    });

    test('browsing: LEFT/RIGHT are handed to focus traversal', () {
      c.showControls();
      expect(c.mode, TvControlsMode.browsing);
      expect(
        c.handleKey(down(LogicalKeyboardKey.arrowLeft)),
        KeyEventResult.ignored,
      );
      expect(c.pendingTarget, isNull);
    });

    test('UP/DOWN summon the row, then belong to traversal', () {
      expect(
        c.handleKey(down(LogicalKeyboardKey.arrowDown)),
        KeyEventResult.handled,
      );
      expect(c.mode, TvControlsMode.browsing);
      // Now that the row is up, the same key must move focus within it.
      expect(
        c.handleKey(down(LogicalKeyboardKey.arrowDown)),
        KeyEventResult.ignored,
      );
    });

    test('OK toggles playback, then belongs to the focused button', () {
      expect(
        c.handleKey(down(LogicalKeyboardKey.select)),
        KeyEventResult.handled,
      );
      expect(target.playPauseCalls, 1);
      expect(c.mode, TvControlsMode.browsing);
      expect(
        c.handleKey(down(LogicalKeyboardKey.select)),
        KeyEventResult.ignored,
      );
      expect(target.playPauseCalls, 1);
    });

    test('BACK hides the overlay, then lets the route close', () {
      c.showControls();
      expect(
        c.handleKey(down(LogicalKeyboardKey.goBack)),
        KeyEventResult.handled,
      );
      expect(c.controlsVisible, isFalse);
      // Nothing left to dismiss: BACK must reach the route, or the player
      // becomes a screen you cannot leave.
      expect(
        c.handleKey(down(LogicalKeyboardKey.goBack)),
        KeyEventResult.ignored,
      );
    });

    test('a key nobody bound is ignored', () {
      // Returning `handled` for these is how a TV fix becomes the next "the
      // D-pad does nothing" report.
      expect(
        c.handleKey(down(LogicalKeyboardKey.keyQ)),
        KeyEventResult.ignored,
      );
      expect(c.handleKey(down(LogicalKeyboardKey.tab)), KeyEventResult.ignored);
    });
  });

  group('coalescing: ten presses are one seek', () {
    testWidgets('a run of presses commits exactly once, at the sum', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 10; i++) {
        c.handleKey(down(LogicalKeyboardKey.arrowLeft));
      }
      // Nothing has reached the player yet: the commit is deliberately
      // delayed so a scrub is one ranged request instead of ten.
      expect(target.seeks, isEmpty);
      await tester.pump(
        TvPlaybackController.commitDelay + const Duration(seconds: 1),
      );
      expect(target.seeks.length, 1);
    });

    testWidgets('presses spread across the window still collapse into one', (
      tester,
    ) async {
      // The stronger version of the test above, and the one that actually
      // pins the mechanism. Ten presses fired back-to-back collapse even if
      // the delay were zero, because each press cancels the pending commit —
      // so "one seek" there can be true for the wrong reason. Pumping
      // BETWEEN presses lets every intermediate deadline come due, and only a
      // real debounce still commits once.
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 6; i++) {
        c.handleKey(down(LogicalKeyboardKey.arrowRight));
        await tester.pump(TvPlaybackController.commitDelay ~/ 2);
        expect(target.seeks, isEmpty, reason: 'press ${i + 1} committed early');
      }
      await tester.pump(
        TvPlaybackController.commitDelay + const Duration(seconds: 1),
      );
      expect(target.seeks, hasLength(1));
    });

    testWidgets('the step accelerates inside a burst', (tester) async {
      await tester.pumpWidget(const SizedBox());
      // Four presses at 10s, then the tier moves on. A two-hour film is
      // unusable at a fixed 10s.
      for (var i = 0; i < 4; i++) {
        c.handleKey(down(LogicalKeyboardKey.arrowRight));
      }
      expect(c.pendingTarget, const Duration(minutes: 5, seconds: 40));
      c.handleKey(down(LogicalKeyboardKey.arrowRight));
      expect(
        c.pendingTarget,
        const Duration(minutes: 6, seconds: 10),
        reason: 'the fifth press should move 30s, not 10s',
      );
      await tester.pump(TvPlaybackController.commitDelay * 2);
    });

    testWidgets(
      'a pause between presses starts a new burst at the small step',
      (tester) async {
        await tester.pumpWidget(const SizedBox());
        for (var i = 0; i < 6; i++) {
          c.handleKey(down(LogicalKeyboardKey.arrowRight));
        }
        await tester.pump(TvPlaybackController.commitDelay * 2);
        target.seeks.clear();
        c.handleKey(down(LogicalKeyboardKey.arrowRight));
        // Back to 10s: a deliberate single press must not inherit the speed of
        // a run that finished a minute ago.
        expect(c.pendingTarget, target.position + const Duration(seconds: 10));
        await tester.pump(TvPlaybackController.commitDelay * 2);
      },
    );

    testWidgets('the step is capped at a tenth of the media', (tester) async {
      await tester.pumpWidget(const SizedBox());
      target.duration = const Duration(seconds: 30);
      target.position = Duration.zero;
      for (var i = 0; i < 12; i++) {
        c.handleKey(down(LogicalKeyboardKey.arrowRight));
      }
      // Without the cap the accelerated step would be 60s — the end of the
      // file, on every press, on a 30-second clip.
      await tester.pump(TvPlaybackController.commitDelay * 2);
      expect(target.seeks.single, lessThanOrEqualTo(target.duration));
    });
  });

  group('clamping', () {
    testWidgets('never seeks before the start', (tester) async {
      await tester.pumpWidget(const SizedBox());
      target.position = const Duration(seconds: 3);
      c.handleKey(down(LogicalKeyboardKey.arrowLeft));
      await tester.pump(TvPlaybackController.commitDelay * 2);
      expect(target.seeks.single, Duration.zero);
    });

    testWidgets('never seeks past the end', (tester) async {
      await tester.pumpWidget(const SizedBox());
      target.position = const Duration(hours: 2) - const Duration(seconds: 2);
      c.handleKey(down(LogicalKeyboardKey.arrowRight));
      await tester.pump(TvPlaybackController.commitDelay * 2);
      expect(target.seeks.single, const Duration(hours: 2));
    });

    test(
      'an unknown duration disables seeking instead of dropping the press',
      () {
        // A live stream. The press still shows the overlay, which is where the
        // reason can be said — a press that appears to do nothing reads as a
        // broken remote.
        target.duration = Duration.zero;
        expect(c.seekable, isFalse);
        c.handleKey(down(LogicalKeyboardKey.arrowRight));
        expect(target.seeks, isEmpty);
        expect(c.pendingTarget, isNull);
        expect(c.controlsVisible, isTrue);
      },
    );
  });

  group('the overlay hides itself, except when it must not', () {
    testWidgets('auto-hides while playing', (tester) async {
      await tester.pumpWidget(const SizedBox());
      c.showControls();
      expect(c.controlsVisible, isTrue);
      await tester.pump(
        TvPlaybackController.autoHideDelay + const Duration(seconds: 1),
      );
      expect(c.controlsVisible, isFalse);
    });

    testWidgets('never auto-hides while paused', (tester) async {
      await tester.pumpWidget(const SizedBox());
      // A paused film with no controls is the dead end this file exists to
      // remove: there would be nothing on screen and no way to resume.
      target.playing = false;
      c.showControls();
      await tester.pump(TvPlaybackController.autoHideDelay * 3);
      expect(c.controlsVisible, isTrue);
    });

    testWidgets('never auto-hides mid-scrub', (tester) async {
      await tester.pumpWidget(const SizedBox());
      c.handleKey(down(LogicalKeyboardKey.arrowRight));
      await tester.pump(
        TvPlaybackController.autoHideDelay - const Duration(seconds: 1),
      );
      expect(c.controlsVisible, isTrue);
      await tester.pump(TvPlaybackController.commitDelay * 2);
    });
  });

  group('platform gating', () {
    test('off a television the media keys still work', () {
      // A keyboard's transport keys, and a Bluetooth remote paired to a phone,
      // are the same keys. Ignoring them would buy nothing.
      final off = TvPlaybackController(target: target, tvKeysEnabled: false);
      addTearDown(off.dispose);
      expect(
        off.handleKey(down(LogicalKeyboardKey.mediaPlayPause)),
        KeyEventResult.handled,
      );
      expect(target.playPauseCalls, 1);
    });

    test('off a television the D-pad keys are left alone', () {
      // On a desktop those arrows already mean something else — Quick Look's
      // own pager, for one.
      final off = TvPlaybackController(target: target, tvKeysEnabled: false);
      addTearDown(off.dispose);
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.select,
      ]) {
        expect(
          off.handleKey(down(key)),
          KeyEventResult.ignored,
          reason: key.debugName,
        );
      }
      expect(target.seeks, isEmpty);
    });
  });

  group('an always-visible surface (the audio screen)', () {
    testWidgets('its arrows are traversal, and its controls never hide', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final audio = TvPlaybackController(target: target, alwaysVisible: true);
      addTearDown(audio.dispose);
      expect(audio.mode, TvControlsMode.browsing);
      // On a screen whose whole content IS the transport row, traversal is
      // what the arrows obviously mean; seeking is the ⏪/⏩ keys' job.
      expect(
        audio.handleKey(down(LogicalKeyboardKey.arrowLeft)),
        KeyEventResult.ignored,
      );
      await tester.pump(TvPlaybackController.autoHideDelay * 3);
      expect(audio.controlsVisible, isTrue);
      // BACK has nothing to dismiss here, so it must reach the route.
      expect(
        audio.handleKey(down(LogicalKeyboardKey.goBack)),
        KeyEventResult.ignored,
      );
    });
  });

  group('media-key ownership when two players exist', () {
    test('the newest controller owns the keys, and disposal hands them back', () {
      // A PageView builds the neighbouring page during a swipe, so two players
      // can be mounted at once. Both acting on one ⏯ press would toggle twice.
      final older = c;
      final newer = TvPlaybackController(target: target);
      expect(older.ownsMediaKeys, isFalse);
      expect(newer.ownsMediaKeys, isTrue);
      expect(
        older.handleMediaKeyGlobally(down(LogicalKeyboardKey.mediaPlayPause)),
        isFalse,
      );
      expect(target.playPauseCalls, 0);
      expect(
        newer.handleMediaKeyGlobally(down(LogicalKeyboardKey.mediaPlayPause)),
        isTrue,
      );
      expect(target.playPauseCalls, 1);

      newer.dispose();
      expect(
        older.ownsMediaKeys,
        isTrue,
        reason: 'disposal must not leave the keys dead',
      );
    });
  });
}
