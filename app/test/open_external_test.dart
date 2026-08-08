import 'package:airclone/src/state/open_external.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mimeForName', () {
    test('resolves the types the preview surface itself renders', () {
      expect(mimeForName('holiday.MP4'), 'video/mp4');
      expect(mimeForName('clip.mkv'), 'video/x-matroska');
      expect(mimeForName('photo.jpeg'), 'image/jpeg');
      expect(mimeForName('song.flac'), 'audio/flac');
      expect(mimeForName('manual.pdf'), 'application/pdf');
    });

    test('a known extension beats a useless backend type', () {
      // rclone often reports application/octet-stream for cloud objects, which
      // would make Android's chooser offer every app on the device.
      expect(
        mimeForName('holiday.mp4', fallback: 'application/octet-stream'),
        'video/mp4',
      );
    });

    test("falls back to rclone's type when the extension is unknown", () {
      expect(mimeForName('blob', fallback: 'image/png'), 'image/png');
      expect(mimeForName('README', fallback: 'text/plain'), 'text/plain');
    });

    test('falls back to octet-stream when nothing is known', () {
      expect(mimeForName('blob'), 'application/octet-stream');
      expect(mimeForName('archive.'), 'application/octet-stream');
      expect(mimeForName('weird.zzz'), 'application/octet-stream');
      expect(mimeForName('blob', fallback: '   '), 'application/octet-stream');
    });
  });

  group('ExternalOpenTask', () {
    test('starts live and latches once cancelled', () {
      final task = ExternalOpenTask();
      expect(task.cancelled, isFalse);
      task.cancel();
      expect(task.cancelled, isTrue);
      task.cancel();
      expect(task.cancelled, isTrue);
    });
  });
}
