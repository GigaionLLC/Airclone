import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/state/cloud_placeholder.dart';
import 'package:flutter_test/flutter_test.dart';

/// A user reported that the Web UI showed no cloud badges where the desktop app
/// showed them — and, far worse, that opening the folder made Proton Drive
/// download a few hundred files. Their sync client's activity log was the
/// evidence: every image in the folder, hydrated within seconds of the page
/// load.
///
/// Two causes, both of them "the browser was asked a question only the host can
/// answer":
///
///  1. `isOnlineOnlyPlaceholder` bottoms out in native probes, and the WEB build
///     of those correctly reports "there is no filesystem here". True about the
///     browser, wrong about the file — the file is on the host. The guard read
///     that as "safe to read", so no badge was drawn and a thumbnail was
///     requested for every online-only file in the folder.
///  2. The Web UI server only refused `download=1`. Thumbnails and previews use
///     the same endpoint without it, so every one of those requests was served
///     and every one hydrated a file.
///
/// The fix makes the HOST answer, on the listing the browser already fetches.
void main() {
  group('the host annotates what the browser cannot see', () {
    /// A real local root, so the answer is a CHECKED fact rather than a guess.
    /// These files exist and are ordinary, so the expected answer is `false` —
    /// the point of the test is that an answer arrives at all.
    Map<String, dynamic> listResult(List<String> names) => {
      'list': [
        for (final n in names) {'Path': n, 'Name': n, 'IsDir': false},
      ],
    };

    test('a local fs root gets every entry annotated', () {
      final out = annotatePlaceholders('operations/list', {
        'fs': '/tmp',
        'remote': '',
      }, listResult(['a.png', 'b.png']));

      for (final e in (out['list'] as List)) {
        expect(
          (e as Map).containsKey(kOnlineOnlyField),
          isTrue,
          reason: 'every entry under a local root must carry an answer',
        );
      }
    });

    /// The distinction the whole design turns on. A named remote cannot be
    /// resolved from the fs string alone, so the host says NOTHING rather than
    /// saying "not a placeholder" — silence and a denial are different claims.
    test('a named remote is left entirely unannotated', () {
      final out = annotatePlaceholders('operations/list', {
        'fs': 'gdrive:',
        'remote': 'Photos',
      }, listResult(['a.png']));

      expect(
        (out['list'] as List).first as Map,
        isNot(contains(kOnlineOnlyField)),
      );
    });

    test('a method that is not a listing is untouched', () {
      final result = {'list': <dynamic>[]};
      expect(
        annotatePlaceholders('config/dump', {'fs': '/tmp'}, result),
        same(result),
      );
    });

    test('a malformed or empty result does not throw', () {
      expect(
        () => annotatePlaceholders('operations/list', {'fs': '/tmp'}, {}),
        returnsNormally,
      );
      expect(
        () => annotatePlaceholders(
          'operations/list',
          {'fs': '/tmp'},
          {
            'list': [
              'not a map',
              {'no': 'path'},
            ],
          },
        ),
        returnsNormally,
      );
    });
  });

  group('isLocalFsRoot tells a path from a remote name', () {
    test('absolute paths are local roots', () {
      expect(isLocalFsRoot('/'), isTrue);
      expect(isLocalFsRoot('/home/someone'), isTrue);
      expect(isLocalFsRoot('C:/'), isTrue);
      expect(isLocalFsRoot(r'C:\Users'), isTrue);
    });

    test('named remotes are not', () {
      expect(isLocalFsRoot('gdrive:'), isFalse);
      expect(isLocalFsRoot('crypt:Photos'), isFalse);
      expect(isLocalFsRoot(''), isFalse);
      // A single-letter remote is written exactly like a drive letter, minus
      // the separator. The separator is the whole distinction.
      expect(isLocalFsRoot('c:'), isFalse);
    });
  });

  group('the client trusts the host over its own blind probes', () {
    test('an entry the host marked online-only reads as online-only', () {
      const f = RcloneFile(
        name: 'a.png',
        path: 'a.png',
        isDir: false,
        onlineOnly: true,
      );
      expect(f.onlineOnly, isTrue);
    });

    /// Three-valued on purpose: `false` is "the host checked and it is here",
    /// null is "nobody checked". Collapsing them is precisely the bug — the web
    /// probes returning nothing were being read as a definite "not online-only".
    test('null and false are different states', () {
      final unanswered = RcloneFile.fromJson({
        'Name': 'a.png',
        'Path': 'a.png',
        'IsDir': false,
      });
      final answered = RcloneFile.fromJson({
        'Name': 'a.png',
        'Path': 'a.png',
        'IsDir': false,
        kOnlineOnlyField: false,
      });
      expect(unanswered.onlineOnly, isNull);
      expect(answered.onlineOnly, isFalse);
    });

    test('a non-boolean annotation is ignored rather than trusted', () {
      final f = RcloneFile.fromJson({
        'Name': 'a.png',
        'Path': 'a.png',
        'IsDir': false,
        kOnlineOnlyField: 'yes',
      });
      expect(f.onlineOnly, isNull);
    });
  });

  group(
    'the deliberate opt-in is recorded where the web client can read it',
    () {
      setUp(clearHydrationOptIns);

      test('an un-consented file is not allowed', () {
        expect(hydrationAllowedFor('C:/', 'a/b.png'), isFalse);
      });

      /// Without this, consenting to "Download 3.7 KB & preview" in the Web UI
      /// would click straight into the refusal it exists to lift: the server
      /// declines the bytes unless the URL says a human asked.
      test('consent is visible without a Riverpod ref', () {
        allowHydration('C:/', 'a/b.png');
        expect(hydrationAllowedFor('C:/', 'a/b.png'), isTrue);
        expect(hydrationAllowedFor('C:/', 'a/other.png'), isFalse);
        expect(hydrationAllowedFor('D:/', 'a/b.png'), isFalse);
      });
    },
  );
}
