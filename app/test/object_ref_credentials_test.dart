import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// The engine's authorization — the rcd file server's Basic auth, or the
/// in-process bridge's bearer token — protects a loopback port on this machine.
/// It used to be handed to the player verbatim next to whatever URL it was
/// given, which was harmless only because every URL came from `objectRef` and
/// therefore pointed at 127.0.0.1.
///
/// "Open a network stream" breaks that assumption: the user names a host we know
/// nothing about. These tests pin the boundary so the credentials cannot follow
/// them there.
void main() {
  const creds = {'Authorization': 'Basic c2VjcmV0'};

  group('credentials travel to loopback', () {
    for (final url in [
      'http://127.0.0.1:5572/[gdrive:]/a.mp4',
      'http://127.0.0.1:9999/obj?fs=x&remote=y',
      'http://127.13.9.2:1/x',
      'http://localhost:5572/x',
      'http://[::1]:5572/x',
    ]) {
      test('kept for $url', () {
        expect(ObjectRef(url, creds).sendableHeaders, creds);
        expect(isLoopbackUrl(url), isTrue);
      });
    }
  });

  group('credentials never leave the machine', () {
    for (final url in [
      'https://cdn.example.com/live/stream.m3u8',
      'http://192.168.1.50:8080/stream.m3u8',
      'http://10.0.0.1/x',
      'http://127.0.0.1.evil.com/x', // the prefix trick
      'http://evil.com/?x=127.0.0.1',
      'rtsp://camera.local/stream',
    ]) {
      test('stripped for $url', () {
        expect(ObjectRef(url, creds).sendableHeaders, isEmpty);
        expect(isLoopbackUrl(url), isFalse);
      });
    }
  });

  test('an unparseable URL is not trusted', () {
    expect(isLoopbackUrl('::::'), isFalse);
    expect(ObjectRef('::::', creds).sendableHeaders, isEmpty);
  });

  test('a network ObjectRef carries nothing to begin with', () {
    const ref = ObjectRef.network('https://cdn.example.com/live.m3u8');
    expect(ref.headers, isEmpty);
    expect(ref.sendableHeaders, isEmpty);
  });
}
