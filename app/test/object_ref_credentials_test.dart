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
  credentialScoping();
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

/// media_kit maps Media.httpHeaders onto mpv's `http-header-fields`, which is
/// GLOBAL: every header is replayed on every request mpv makes for that stream,
/// including the segments an HLS manifest names. sendableHeaders only ever saw
/// the top-level URL, so a manifest on the user's own remote could name a
/// segment on someone else's host and be handed the engine's credential.
///
/// Credentials in the URL are scoped by whoever makes the request: a relative
/// segment inherits the userinfo, an absolute URL to another host does not.
void credentialScoping() {
  group('loopbackUrlWithCredentials', () {
    const basic = {
      'Authorization': 'Basic YWlyY2xvbmU6czNjcjN0',
    }; // airclone:s3cr3t

    test('a loopback URL carries its credential in the URL', () {
      final out = loopbackUrlWithCredentials(
        'http://127.0.0.1:5572/[gdrive:]/a/v.m3u8',
        basic,
      );
      expect(out, isNotNull);
      final uri = Uri.parse(out!);
      expect(uri.userInfo, 'airclone:s3cr3t');
      expect(uri.host, '127.0.0.1');
    });

    test('a relative segment INHERITS it — the point of the change', () {
      final out = loopbackUrlWithCredentials(
        'http://127.0.0.1:5572/[gdrive:]/a/v.m3u8',
        basic,
      )!;
      final seg = Uri.parse(out).resolve('seg1.ts');
      expect(seg.userInfo, 'airclone:s3cr3t');
    });

    test('a segment on ANOTHER host does not', () {
      final out = loopbackUrlWithCredentials(
        'http://127.0.0.1:5572/[gdrive:]/a/v.m3u8',
        basic,
      )!;
      final seg = Uri.parse(out).resolve('http://attacker.example/seg.ts');
      expect(seg.userInfo, isEmpty);
      expect(seg.host, 'attacker.example');
    });

    test('a non-loopback URL is refused outright', () {
      expect(
        loopbackUrlWithCredentials('https://cdn.example.com/live.m3u8', basic),
        isNull,
      );
    });

    test('no credential, nothing to embed', () {
      expect(
        loopbackUrlWithCredentials('http://127.0.0.1:5572/x', const {}),
        isNull,
      );
    });

    test('a Bearer token is not smuggled into userinfo', () {
      // Only Basic maps onto userinfo. Anything else falls back to the header
      // path rather than being mangled into a shape that means something else.
      expect(
        loopbackUrlWithCredentials('http://127.0.0.1:9/x', const {
          'Authorization': 'Bearer abc',
        }),
        isNull,
      );
    });
  });
}
