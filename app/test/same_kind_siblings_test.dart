import 'package:airclone/src/ui/quick_look.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Next track" must mean the next TRACK.
///
/// Quick Look's previous/next used to move one page, which is right for a swipe
/// and wrong for the two keys a television remote has. A folder of songs almost
/// always holds a `cover.jpg`, and often a `.cue` or a `.log` as well; on a
/// phone landing on one is a shrug, because another swipe moves on. On a TV
/// those keys are the only way through the folder, so an album with a cover
/// image became an album you could not play through.
///
/// The pop-out image viewer already filtered siblings this way. These are the
/// same idea for the two media kinds, and the rule that keeps everything else
/// untouched: a non-media page still moves exactly one page.
void main() {
  RcloneFile f(String name) =>
      RcloneFile(name: name, path: 'Album/$name', isDir: false);

  // A real album folder, in the order rclone lists it.
  final album = [
    f('01 - Xtal.flac'),
    f('02 - Tha.flac'),
    f('cover.jpg'),
    f('03 - Green Calx.flac'),
    f('album.cue'),
    f('04 - Heliosphan.flac'),
  ];

  group('audio walks audio', () {
    test('forward steps over the cover image', () {
      expect(sameKindNeighbour(album, 1, 1), 3);
    });

    test('backward steps over the cover image', () {
      expect(sameKindNeighbour(album, 3, -1), 1);
    });

    test('forward steps over a cue sheet', () {
      expect(sameKindNeighbour(album, 3, 1), 5);
    });

    test('the ends report no neighbour, so the control disables', () {
      // Null is what makes a button DISABLED rather than absent, which is the
      // rule that keeps the row from reflowing under someone's aim.
      expect(sameKindNeighbour(album, 0, -1), isNull);
      expect(sameKindNeighbour(album, 5, 1), isNull);
    });

    test('a lone track in a folder of images has no neighbour either way', () {
      final one = [f('art.png'), f('only.mp3'), f('back.jpg')];
      expect(sameKindNeighbour(one, 1, -1), isNull);
      expect(sameKindNeighbour(one, 1, 1), isNull);
    });
  });

  group('video walks video', () {
    final season = [
      f('S01E01.mkv'),
      f('S01E01.srt'),
      f('poster.jpg'),
      f('S01E02.mkv'),
    ];

    test('the next episode, not the subtitle file beside it', () {
      expect(sameKindNeighbour(season, 0, 1), 3);
    });

    test('audio and video are different kinds', () {
      // A folder holding both must not treat one as the other's neighbour.
      final mixed = [f('theme.mp3'), f('movie.mp4')];
      expect(sameKindNeighbour(mixed, 0, 1), isNull);
      expect(sameKindNeighbour(mixed, 1, -1), isNull);
    });
  });

  group('everything else is unchanged', () {
    test('a non-media page still moves exactly one page', () {
      // Images, text, PDFs: a swipe and the arrow keys have always moved one
      // page, and nothing here should change that.
      final docs = [f('a.jpg'), f('notes.txt'), f('b.png')];
      expect(sameKindNeighbour(docs, 0, 1), 1);
      expect(sameKindNeighbour(docs, 1, 1), 2);
      expect(sameKindNeighbour(docs, 2, -1), 1);
      expect(sameKindNeighbour(docs, 2, 1), isNull);
    });

    test('an out-of-range index answers null rather than throwing', () {
      // The list can SHRINK under the pager: Quick Look can delete the file it
      // is showing, which is exactly when an index goes stale.
      expect(sameKindNeighbour(album, 99, 1), isNull);
      expect(sameKindNeighbour(album, -1, 1), isNull);
      expect(sameKindNeighbour(const [], 0, 1), isNull);
    });
  });
}
