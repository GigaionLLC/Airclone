import 'package:airclone/src/state/media_tracks.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/track_picker.dart';
import 'package:airclone/src/ui/tv_player_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'tv_playback_fake.dart';

/// The pointer and touch track pickers (player format plan, A2), proved on the
/// same [FakeTarget] the television tests use. `MediaPreviewBody` itself
/// cannot be pumped in a test — it constructs a libmpv player — so the button
/// that lives in its control bars is tested here, where its decisions are made.
void main() {
  late FakeTarget target;
  late TvPlaybackController controller;

  const oneAudioNoSubs = Tracks(
    audio: [
      AudioTrack('auto', null, null),
      AudioTrack('no', null, null),
      AudioTrack('1', null, 'eng'),
    ],
  );
  const film = Tracks(
    audio: [
      AudioTrack('auto', null, null),
      AudioTrack('no', null, null),
      AudioTrack('1', null, 'eng', codec: 'ac3', isDefault: true),
      AudioTrack('2', null, 'ger', codec: 'aac'),
    ],
    subtitle: [
      SubtitleTrack('auto', null, null),
      SubtitleTrack('no', null, null),
      SubtitleTrack('3', null, 'eng', codec: 'subrip'),
      SubtitleTrack('4', null, 'jpn', codec: 'hdmv_pgs_subtitle'),
    ],
  );

  setUp(() {
    target = FakeTarget();
    controller = TvPlaybackController(target: target, tvKeysEnabled: false);
  });

  tearDown(() {
    controller.dispose();
    target.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool desktop = true,
    bool isWeb = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final kind in TrackKind.values)
                  TrackPickerButton(
                    controller: controller,
                    kind: kind,
                    desktop: desktop,
                    isWeb: isWeb,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final audio = find.byIcon(Icons.audiotrack_outlined);
  final subs = find.byIcon(Icons.subtitles_outlined);

  testWidgets('one audio track and no subtitles: no buttons at all', (
    tester,
  ) async {
    target.tracks = oneAudioNoSubs;
    await pump(tester);
    expect(audio, findsNothing);
    expect(subs, findsNothing);
  });

  testWidgets('a film with choices gets both, as tracks arrive', (
    tester,
  ) async {
    await pump(tester);
    expect(audio, findsNothing, reason: 'libmpv has not listed anything yet');
    target.setTracks(film);
    // The stream delivers in a microtask, after the first frame.
    await tester.pump();
    await tester.pump();
    expect(audio, findsOneWidget);
    expect(subs, findsOneWidget);
  });

  testWidgets('sidecars on the way show the subtitle button early', (
    tester,
  ) async {
    target.tracks = oneAudioNoSubs;
    controller.expectedSidecars = 1;
    await pump(tester);
    expect(subs, findsOneWidget);
    expect(audio, findsNothing);
  });

  testWidgets('the web build never shows them', (tester) async {
    target.tracks = film;
    await pump(tester, isWeb: true);
    expect(audio, findsNothing);
    expect(subs, findsNothing);
  });

  testWidgets('desktop: the menu lists the tracks and a pick reaches the '
      'player', (tester) async {
    target.tracks = film;
    target.selectedAudio = '1';
    await pump(tester);
    await tester.tap(audio);
    await tester.pumpAndSettle();
    expect(find.text('English · AC-3 (default)'), findsOneWidget);
    await tester.tap(find.text('German · AAC'));
    await tester.pumpAndSettle();
    expect(target.audioSets.single.id, '2');
  });

  testWidgets('desktop: an image subtitle is listed but cannot be picked', (
    tester,
  ) async {
    target.tracks = film;
    await pump(tester);
    await tester.tap(subs);
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    final pgs = find.text("Japanese · image · can't be shown here");
    expect(pgs, findsOneWidget);
    await tester.tap(pgs, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(target.subtitleSets, isEmpty);
  });

  testWidgets('touch: a bottom sheet, and Off switches subtitles off', (
    tester,
  ) async {
    target.tracks = film;
    target.selectedSubtitle = '3';
    await pump(tester, desktop: false);
    await tester.tap(subs);
    await tester.pumpAndSettle();
    expect(find.text('Subtitles'), findsWidgets);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(target.subtitleSets.single.id, 'no');
  });

  group('subtitle text while libass is off (plan 4.B fallback)', () {
    test('on a television media_kit draws none: the overlay does '
        '(TvSubtitleLine), so the line can clear the controls', () {
      expect(subtitleViewConfigurationFor(tv: true).visible, isFalse);
    });

    test("everything else keeps media_kit's window-relative default", () {
      final other = subtitleViewConfigurationFor(tv: false);
      expect(other.textScaler, isNull);
      expect(other.style.fontSize, 32);
    });
  });
}
