import 'package:airclone/src/state/media_tracks.dart';
import 'package:airclone/src/state/sidecar_subs.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'package:flutter_test/flutter_test.dart';

/// `movie.srt` next to `movie.mkv` was ignored: libmpv only looks for sidecars
/// in a local folder, and the player only ever opens a loopback URL. These pin
/// which files Airclone now adds for it (player format plan, 4.C), and the
/// limits on a file anyone with access to the folder could have put there.
void main() {
  RcloneFile f(String name, {int size = 1000, bool isDir = false}) =>
      RcloneFile(name: name, path: 'films/$name', isDir: isDir, size: size);

  final video = f('Movie.mkv', size: 4000000000);

  List<String> names(List<Sidecar> s) => [for (final x in s) x.file.name];

  group('matching', () {
    test('the same stem, any supported text format, any case', () {
      final found = findSidecars(video, [
        video,
        f('Movie.srt'),
        f('movie.ASS'),
        f('MOVIE.ssa'),
        f('Movie.vtt'),
      ]);
      expect(names(found), [
        'MOVIE.ssa',
        'Movie.srt',
        'Movie.vtt',
        'movie.ASS',
      ]);
    });

    test('language, forced and SDH tags are read from the name', () {
      final found = findSidecars(video, [
        f('Movie.en.srt'),
        f('Movie.de.forced.srt'),
        f('Movie.eng.sdh.srt'),
        f('Movie.pt-BR.srt'),
        f('Movie.english.srt'),
      ]);
      final byName = {for (final s in found) s.file.name: s};
      expect(byName['Movie.en.srt']!.language, 'en');
      expect(byName['Movie.de.forced.srt']!.forced, isTrue);
      expect(byName['Movie.de.forced.srt']!.language, 'de');
      expect(byName['Movie.eng.sdh.srt']!.sdh, isTrue);
      expect(byName['Movie.pt-BR.srt']!.language, 'pt-br');
      expect(byName['Movie.english.srt']!.language, 'english');
    });

    test('hi is hearing-impaired beside a language, Hindi on its own', () {
      final found = findSidecars(video, [
        f('Movie.en.hi.srt'),
        f('Movie.hi.srt'),
      ]);
      final byName = {for (final s in found) s.file.name: s};
      expect(byName['Movie.en.hi.srt']!.sdh, isTrue);
      expect(byName['Movie.en.hi.srt']!.language, 'en');
      expect(byName['Movie.hi.srt']!.sdh, isFalse);
      expect(byName['Movie.hi.srt']!.language, 'hi');
    });

    test('a stem may contain dots', () {
      final film = f('My.Film.2020.1080p.mkv');
      final found = findSidecars(film, [
        f('My.Film.2020.1080p.en.srt'),
        f('My.Film.2020.srt'),
      ]);
      expect(names(found), ['My.Film.2020.1080p.en.srt']);
    });

    test("another file's subtitles, and other files, are not this video's", () {
      final found = findSidecars(video, [
        f('Movie.part2.srt'),
        f('Movie2.srt'),
        f('Other.srt'),
        f('Movie.nfo'),
        f('Movie.jpg'),
        f('Movie.idx'),
        f('Movie.sub'),
        f('Movie.sup'),
        f('Movie.m3u8'),
      ]);
      expect(found, isEmpty);
    });

    test('folders, oversize files and unknown sizes are skipped', () {
      final found = findSidecars(video, [
        f('Movie.srt', isDir: true),
        f('Movie.en.srt', size: kSidecarMaxBytes + 1),
        f('Movie.de.srt', size: -1),
        f('Movie.fr.srt', size: kSidecarMaxBytes),
      ]);
      expect(names(found), ['Movie.fr.srt']);
    });

    test('the caller can refuse a file (an online-only placeholder)', () {
      final found = findSidecars(video, [
        f('Movie.en.srt'),
        f('Movie.de.srt'),
      ], skip: (x) => x.name == 'Movie.de.srt');
      expect(names(found), ['Movie.en.srt']);
    });
  });

  group('which one to select', () {
    final en = Sidecar(file: f('Movie.en.srt'), language: 'en');
    final deForced = Sidecar(
      file: f('Movie.de.forced.srt'),
      language: 'de',
      forced: true,
    );
    final de = Sidecar(file: f('Movie.de.srt'), language: 'de');

    test('never when the file has subtitles of its own', () {
      expect(
        sidecarToSelect([en], fileHasSubtitles: true, preferred: 'eng'),
        isNull,
      );
    });

    test('the preferred language, an unforced one first', () {
      expect(
        sidecarToSelect(
          [deForced, de, en],
          fileHasSubtitles: false,
          preferred: 'ger',
        ),
        1,
      );
      expect(
        sidecarToSelect(
          [deForced, en],
          fileHasSubtitles: false,
          preferred: 'ger',
        ),
        0,
      );
    });

    test('the only one, with no matching preference', () {
      expect(
        sidecarToSelect([en], fileHasSubtitles: false, preferred: null),
        0,
      );
      expect(
        sidecarToSelect([en], fileHasSubtitles: false, preferred: 'ger'),
        0,
      );
      expect(
        sidecarToSelect([en, de], fileHasSubtitles: false, preferred: null),
        isNull,
        reason: 'two to choose from and nothing to choose by',
      );
    });

    test('never when the person switched subtitles off', () {
      expect(
        sidecarToSelect([en], fileHasSubtitles: false, preferred: kLanguageOff),
        isNull,
      );
    });
  });

  group('the URL mpv is given', () {
    const basic = {'Authorization': 'Basic dXNlcjpzZWNyZXQ='}; // user:secret

    test('the engine object URL, with its credential in the userinfo', () {
      final url = sidecarUrl(
        const ObjectRef(
          'http://127.0.0.1:5572/[gdrive:]/films/Movie.en.srt',
          basic,
        ),
      );
      expect(url, startsWith('http://user:secret@127.0.0.1:5572/'));
    });

    test('a bearer-token engine passes its URL through unchanged', () {
      const url = 'http://127.0.0.1:41000/obj?fs=x&remote=Movie.srt';
      expect(
        sidecarUrl(const ObjectRef(url, {'Authorization': 'Bearer t'})),
        url,
      );
    });

    test('nothing that is not http(s) to this machine', () {
      expect(sidecarUrl(const ObjectRef('file:///etc/passwd', {})), isNull);
      expect(
        sidecarUrl(const ObjectRef('https://example.com/Movie.srt', basic)),
        isNull,
      );
      expect(sidecarUrl(const ObjectRef('ftp://127.0.0.1/x.srt', {})), isNull);
    });

    test('the title shown is the file name, never the URL', () {
      final s = Sidecar(file: f('Movie.en.srt'), language: 'en');
      expect(s.title, 'Movie.en.srt');
    });
  });
}
