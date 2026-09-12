import 'package:airclone/src/ui/network_stream_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a user may point the player at is a security decision, so the rule is a
/// pure function with its own tests rather than a check buried in a widget.
void main() {
  group('accepted', () {
    for (final url in [
      'https://example.com/live.m3u8',
      'http://example.com/stream.mpd',
      'rtsp://camera.local:554/stream1',
      'rtmps://live.example.com/app/key',
      'srt://example.com:9000',
      'udp://239.0.0.1:1234',
    ]) {
      test(url, () => expect(validateStreamUrl(url), isNull));
    }

    test('surrounding whitespace is tolerated', () {
      expect(validateStreamUrl('  https://example.com/a.m3u8  '), isNull);
    });
  });

  group('refused', () {
    test('empty', () => expect(validateStreamUrl(''), isNotNull));

    test('file:// would make this a local-file reader', () {
      final msg = validateStreamUrl('file:///etc/passwd');
      expect(msg, isNotNull);
      expect(msg, contains('Local files'));
    });

    test('a scheme we do not support says which one', () {
      expect(validateStreamUrl('gopher://example.com/x'), contains('gopher'));
    });

    test('a bare hostname is asked for its protocol', () {
      expect(validateStreamUrl('example.com/live.m3u8'), contains('protocol'));
    });

    test('a URL with no server in it', () {
      expect(validateStreamUrl('http:///nohost'), isNotNull);
    });
  });

  test('the scheme allowlist holds no local-access schemes', () {
    // The point of an allowlist is that widening it is deliberate. These are the
    // ones that would reach the host rather than the network.
    for (final bad in ['file', 'avdevice', 'cdda', 'bd', 'dvd', 'pipe']) {
      expect(kStreamSchemes.contains(bad), isFalse, reason: bad);
    }
  });
}
