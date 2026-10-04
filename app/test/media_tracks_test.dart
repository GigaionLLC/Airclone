import 'package:airclone/src/state/media_tracks.dart';
import 'package:airclone/src/ui/tv_player_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'tv_playback_fake.dart';

/// A film MKV with three languages used to play whatever libmpv picked, and a
/// Blu-ray rip whose default subtitle was a PGS image track showed nothing at
/// all. These are the rules the pickers are built on (player format plan, A1).
void main() {
  const filmTracks = Tracks(
    audio: [
      AudioTrack('auto', null, null),
      AudioTrack('no', null, null),
      AudioTrack(
        '1',
        null,
        'eng',
        codec: 'ac3',
        channels: '5.1(side)',
        isDefault: true,
      ),
      AudioTrack('2', 'Commentary', 'de', codec: 'aac', channelscount: 2),
    ],
    subtitle: [
      SubtitleTrack('auto', null, null),
      SubtitleTrack('no', null, null),
      SubtitleTrack('3', null, 'eng', codec: 'subrip'),
      SubtitleTrack('4', 'Forced', 'ger', codec: 'ass'),
      SubtitleTrack(
        '5',
        null,
        'jpn',
        codec: 'hdmv_pgs_subtitle',
        isDefault: true,
      ),
    ],
  );

  group('languages', () {
    test('every spelling of a language reads the same', () {
      expect(languageName('en'), 'English');
      expect(languageName('eng'), 'English');
      expect(languageName('de'), 'German');
      expect(languageName('ger'), 'German');
      expect(languageName('deu'), 'German');
      expect(languageName('english'), 'English');
      expect(languageName('pt-BR'), 'Portuguese (BR)');
      expect(languageName('pt_br'), 'Portuguese (BR)');
    });

    test('no language is no label, and an unknown code is shown as itself', () {
      expect(languageName(null), isNull);
      expect(languageName(''), isNull);
      expect(languageName('und'), isNull);
      expect(languageName('xyz'), 'xyz');
    });

    test('a preference is stored in one canonical form', () {
      expect(canonicalLanguage('de'), 'ger');
      expect(canonicalLanguage('deu'), 'ger');
      expect(canonicalLanguage('GER'), 'ger');
      expect(canonicalLanguage('und'), isNull);
      expect(canonicalLanguage('XyZ'), 'xyz');
    });

    test('mpv is given every alias, so a file tagged de matches ger', () {
      expect(
        mpvLanguageList('ger').split(','),
        containsAll(['ger', 'deu', 'de']),
      );
      expect(mpvLanguageList('eng'), 'eng,en');
      expect(mpvLanguageList('xyz'), 'xyz');
    });
  });

  group('labels', () {
    test('audio rows carry language, channels, codec and default', () {
      final rows = audioChoices(filmTracks);
      expect(rows.map((r) => r.label), [
        'English · 5.1 · AC-3 (default)',
        'German · Commentary · stereo · AAC',
      ]);
    });

    test('a track with nothing to go on is named by position', () {
      final rows = audioChoices(
        const Tracks(
          audio: [
            AudioTrack('auto', null, null),
            AudioTrack('no', null, null),
            AudioTrack('7', null, null),
          ],
        ),
      );
      expect(rows.single.label, 'Track 1');
    });

    test('forced and external are said once', () {
      expect(
        trackLabel(language: 'ger', title: 'Forced', isForced: true),
        'German · Forced',
      );
      expect(trackLabel(language: 'ger', isForced: true), 'German · forced');
      expect(
        trackLabel(language: 'en', title: 'movie.en.srt', external: true),
        'English · movie.en.srt · external',
      );
    });

    test('a label never shows the track id, even a URL one', () {
      // media_kit's SubtitleTrack.uri stores the URL as the id, and an engine
      // object URL carries the engine password in its userinfo.
      const secret = 'http://user:hunter2@127.0.0.1:5572/[gdrive:]/x.srt';
      final rows = subtitleChoices(
        const Tracks(
          subtitle: [
            SubtitleTrack('auto', null, null),
            SubtitleTrack('no', null, null),
            SubtitleTrack(secret, null, null, uri: true),
          ],
        ),
        imageSubsRenderable: false,
      );
      for (final r in rows) {
        expect(r.label, isNot(contains('hunter2')));
        expect(r.label, isNot(contains('127.0.0.1')));
      }
    });
  });

  group('choices', () {
    test('auto and no are never listed as tracks', () {
      expect(audioChoices(filmTracks).map((r) => r.id), ['1', '2']);
      expect(
        subtitleChoices(filmTracks, imageSubsRenderable: true).map((r) => r.id),
        ['no', '3', '4', '5'],
        reason: 'Off is the only placeholder shown, and it is first',
      );
    });

    test('image subtitles are listed but disabled without libass', () {
      final rows = subtitleChoices(filmTracks, imageSubsRenderable: false);
      final pgs = rows.firstWhere((r) => r.id == '5');
      expect(pgs.enabled, isFalse);
      expect(pgs.label, "Japanese (default) · image · can't be shown here");
      expect(rows.where((r) => !r.enabled), [pgs]);
    });

    test('and selectable once they can be drawn', () {
      final rows = subtitleChoices(filmTracks, imageSubsRenderable: true);
      expect(rows.firstWhere((r) => r.id == '5').enabled, isTrue);
    });

    test('a sidecar is labelled external by the title Airclone gave it', () {
      final rows = subtitleChoices(
        const Tracks(
          subtitle: [
            SubtitleTrack('auto', null, null),
            SubtitleTrack('no', null, null),
            SubtitleTrack('1', 'movie.en.srt', 'en', codec: 'subrip'),
          ],
        ),
        imageSubsRenderable: false,
        externalTitles: {'movie.en.srt'},
      );
      expect(rows.last.label, 'English · movie.en.srt · external');
    });

    test('image detection is by codec', () {
      expect(
        subKindOf(const SubtitleTrack('1', null, null, codec: 'dvd_subtitle')),
        SubKind.image,
      );
      expect(
        subKindOf(const SubtitleTrack('1', null, null, codec: 'subrip')),
        SubKind.text,
      );
      expect(subKindOf(const SubtitleTrack('1', null, null)), SubKind.unknown);
    });
  });

  group('when the buttons show', () {
    test('one audio track is no choice', () {
      expect(hasAudioChoice(filmTracks), isTrue);
      expect(
        hasAudioChoice(
          const Tracks(
            audio: [
              AudioTrack('auto', null, null),
              AudioTrack('no', null, null),
              AudioTrack('1', null, 'eng'),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('no subtitle tracks hides subtitles, unless sidecars are coming', () {
      expect(hasSubtitleChoice(const Tracks()), isFalse);
      expect(hasSubtitleChoice(const Tracks(), sidecarsExpected: true), isTrue);
      expect(hasSubtitleChoice(filmTracks), isTrue);
    });
  });

  group('the auto-picked image subtitle (plan Q3)', () {
    test('is switched off when it cannot be drawn', () {
      expect(
        shouldDropAutoSubtitle(
          tracks: filmTracks,
          selectedId: '5',
          imageSubsRenderable: false,
        ),
        isTrue,
      );
    });

    test(
      'a text pick, no pick, or a renderer that can draw it is left alone',
      () {
        for (final id in ['3', 'no', 'auto', null]) {
          expect(
            shouldDropAutoSubtitle(
              tracks: filmTracks,
              selectedId: id,
              imageSubsRenderable: false,
            ),
            isFalse,
            reason: '$id',
          );
        }
        expect(
          shouldDropAutoSubtitle(
            tracks: filmTracks,
            selectedId: '5',
            imageSubsRenderable: true,
          ),
          isFalse,
        );
      },
    );
  });

  group('preferences', () {
    test('Off remembers off, a language remembers its canonical code', () {
      final subs = subtitleChoices(filmTracks, imageSubsRenderable: false);
      expect(preferenceFor(subs.first), kLanguageOff);
      expect(preferenceFor(subs[2]), 'ger');
      expect(
        preferenceFor(
          const TrackChoice(kind: TrackKind.audio, id: '9', label: 'Track 1'),
        ),
        isNull,
        reason: 'an untagged track says nothing about the language wanted',
      );
    });
  });

  group('the controller applies a pick through the seam', () {
    late FakeTarget target;
    late TvPlaybackController controller;
    setUp(() {
      target = FakeTarget();
      controller = TvPlaybackController(target: target);
    });
    tearDown(() {
      controller.dispose();
      target.dispose();
    });

    test('audio and subtitle picks reach the player and the host', () async {
      final picked = <TrackChoice>[];
      controller.onTrackPicked = picked.add;
      final audio = audioChoices(filmTracks)[1];
      final off = subtitleChoices(filmTracks, imageSubsRenderable: false).first;
      await controller.selectTrack(audio);
      await controller.selectTrack(off);
      expect(target.audioSets.single.id, '2');
      expect(target.subtitleSets.single.id, 'no');
      expect(picked, [audio, off]);
    });

    test('a disabled row does nothing', () async {
      final pgs = subtitleChoices(
        filmTracks,
        imageSubsRenderable: false,
      ).firstWhere((r) => !r.enabled);
      await controller.selectTrack(pgs);
      expect(target.subtitleSets, isEmpty);
    });
  });
}
