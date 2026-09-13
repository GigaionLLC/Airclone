import 'package:airclone/src/state/diagnostics.dart';
import 'package:airclone/src/ui/media_preview.dart';
import 'package:flutter_test/flutter_test.dart';

/// A user sent a screenshot of a playback failure. The error card was showing:
///
/// ```
/// Failed to open http://airclone:<the engine's live password>@127.0.0.1:56587/...
/// ```
///
/// libmpv reports the URL it could not open, and an object served by the local
/// engine carries that engine's credential in the URL's userinfo — which
/// [loopbackUrlWithCredentials] puts there deliberately, because mpv's
/// `http-header-fields` is global and a header would be replayed to any host a
/// manifest names. Scoping the secret to the request was right; printing the
/// result verbatim was not.
///
/// The exposure is bounded — the password is regenerated on every engine start
/// and only ever authenticates to 127.0.0.1 — but the first instinct on seeing a
/// playback error is to screenshot it and send it to someone, so this is a
/// credential on a path that is *designed* to be shared.
void main() {
  group('a player error never carries a credential to the screen', () {
    /// The real message, with the password replaced.
    const leak =
        'Failed to open http://airclone:CkIAy4IiOCQnGIX0yibznDn9ZYDgEI5u'
        '@127.0.0.1:56587/%5BC:/Users/someone/%5D/tracks-v1a1/mono.m3u8.';

    test('the userinfo is gone', () {
      final out = redactSensitive(leak);
      expect(out, isNot(contains('CkIAy4IiOCQnGIX0yibznDn9ZYDgEI5u')));
      expect(out, isNot(contains('airclone:')));
    });

    test('and so is the account name in the path', () {
      expect(redactSensitive(leak), isNot(contains('someone')));
    });

    /// Redaction must not eat the message. A user reading the card still has to
    /// be able to tell WHICH file failed and roughly why.
    test('what failed is still legible', () {
      final out = redactSensitive(leak);
      expect(out, contains('Failed to open'));
      expect(out, contains('mono.m3u8'));
      expect(out, contains('127.0.0.1:56587'));
    });

    test('an error with nothing sensitive in it is passed through', () {
      const plain = 'Could not open codec: unsupported pixel format.';
      expect(redactSensitive(plain), plain);
    });
  });

  group('a local playlist gets an explanation, not just a failure', () {
    String? hint(String url, {bool stream = false}) =>
        playlistHintFor(url: url, isNetworkStream: stream);

    test('an m3u8 served by the engine is explained', () {
      final h = hint('http://127.0.0.1:56587/%5BC:/x/%5D/index.m3u8');
      expect(h, isNotNull);
      expect(h, contains('does not contain any media'));
      expect(h, contains('Open network stream'));
    });

    test('m3u and mpd too, and case does not matter', () {
      expect(hint('http://127.0.0.1:1/a/list.m3u'), isNotNull);
      expect(hint('http://127.0.0.1:1/a/manifest.mpd'), isNotNull);
      expect(hint('http://127.0.0.1:1/a/INDEX.M3U8'), isNotNull);
    });

    /// The hint would be a LIE for a network stream: a remote playlist resolves
    /// its children against their own origin, where they really are, so a
    /// failure there means something else and pointing the user at the network
    /// stream dialog they are already using would be worse than saying nothing.
    test('a network stream is not given it', () {
      expect(
        hint('https://cdn.example.com/live/index.m3u8', stream: true),
        isNull,
      );
    });

    test('ordinary media is not given it', () {
      expect(hint('http://127.0.0.1:1/a/clip.mp4'), isNull);
      expect(hint('http://127.0.0.1:1/a/song.flac'), isNull);
    });

    test('a name with no extension does not crash or claim anything', () {
      expect(hint('http://127.0.0.1:1/a/README'), isNull);
      expect(hint('http://127.0.0.1:1/a/trailing.'), isNull);
      expect(hint(''), isNull);
    });
  });
}
