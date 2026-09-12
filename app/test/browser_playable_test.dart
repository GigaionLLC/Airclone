import 'package:airclone/src/state/media_formats.dart';
import 'package:flutter_test/flutter_test.dart';

/// A user reported "I can't play videos" in the Web UI, with a screenshot of an
/// .avi showing the browser's own "Failed to load because no supported source
/// was found" — next to a Try again button that could never work.
///
/// Nothing was broken. media_kit's web backend is an HTMLVideoElement, so in a
/// browser the decoder is the browser's, and no server behaviour changes that.
/// The bug was that Airclone reported a platform limit as a failure.
void main() {
  group('containers a browser cannot decode', () {
    for (final e in ['avi', 'mkv', 'wmv', 'flv', 'mpg', 'mpeg']) {
      test('.$e is flagged so the UI can explain', () {
        expect(isUnplayableInBrowser(e), isTrue);
      });
    }
  });

  group('containers a browser can', () {
    for (final e in ['mp4', 'm4v', 'webm', 'mov', 'mp3', 'm4a', 'flac']) {
      test('.$e is left to the player', () {
        expect(isUnplayableInBrowser(e), isFalse);
      });
    }

    test('HLS is not refused outright', () {
      // Safari plays it natively and media_kit's web backend handles it;
      // refusing would be wrong more often than right.
      expect(isUnplayableInBrowser('m3u8'), isFalse);
    });
  });

  group('the check only speaks about media', () {
    for (final e in ['pdf', 'txt', 'jpg', 'zip', 'dart', '']) {
      test('.$e is not claimed either way', () {
        expect(isUnplayableInBrowser(e), isFalse, reason: e);
      });
    }
  });

  test('every playable video container is one the app calls video', () {
    // Guards a drift where the browser list and the app's own idea of "video"
    // disagree, which is the exact shape of the .flv bug found earlier.
    for (final e in ['mp4', 'm4v', 'webm', 'mov']) {
      expect(isVideoLikeExt(e), isTrue, reason: e);
    }
  });
}
