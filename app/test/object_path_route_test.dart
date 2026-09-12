import 'package:airclone/src/rclone/librclone_object_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// A streaming manifest lists its segments by RELATIVE name, resolved against
/// the URL the manifest itself came from. The in-process engine's object URL is
/// query-shaped (`/obj?fs=X&remote=dir/v.m3u8`), and a relative `seg1.ts`
/// resolved against that becomes `/seg1.ts` — the remote and the directory both
/// gone, every segment a 404, and the symptom just "the stream never starts".
///
/// Hence a path-shaped route. These tests pin the round trip and the relative
/// resolution that is the entire reason it exists.
void main() {
  group('round trip', () {
    for (final c in [
      ('gdrive:', 'movies/holiday.m3u8'),
      ('s3:bucket', 'a/b/c/stream.m3u8'),
      ('local:', 'file with spaces.m3u8'),
      ('crypt:', 'dir/naïve/ünicode.m3u8'),
      ('gdrive:', 'has#hash/and?question.m3u8'),
    ]) {
      test('${c.$1} ${c.$2}', () {
        final segments = c.$2.split('/').map(Uri.encodeComponent).join('/');
        final path = '/o/${Uri.encodeComponent('[${c.$1}]')}/$segments';
        expect(parseObjectPath(path), (c.$1, c.$2));
      });
    }
  });

  test('a relative segment resolves back to the same remote and directory', () {
    // The property the whole route exists for.
    final manifest = Uri.parse(
      'http://127.0.0.1:5000/o/${Uri.encodeComponent('[gdrive:]')}/movies/v.m3u8',
    );
    final segment = manifest.resolve('seg1.ts');
    final parsed = parseObjectPath(segment.path);
    expect(parsed, isNotNull);
    expect(parsed!.$1, 'gdrive:');
    expect(parsed.$2, 'movies/seg1.ts');
  });

  group('refused', () {
    for (final bad in [
      '/obj?fs=x&remote=y',
      '/o/',
      '/o/nofs',
      '/o/[]/file.m3u8',
      '/o/[gdrive:]/',
      '/other/[gdrive:]/x',
    ]) {
      test(bad, () => expect(parseObjectPath(bad), isNull));
    }

    test('a climbing segment is refused', () {
      final path = '/o/${Uri.encodeComponent('[gdrive:]')}/a/..%2F../etc';
      expect(parseObjectPath(path), isNull);
    });
  });
}
