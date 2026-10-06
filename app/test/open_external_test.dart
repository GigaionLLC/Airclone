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

  group('the widened media tables have types too', () {
    // Without one, Android's chooser is offered */* and lists every app on
    // the device instead of the video players.
    test('every new video extension maps to a real type', () {
      expect(mimeForName('film.m2ts'), 'video/mp2t');
      expect(mimeForName('clip.flv'), 'video/x-flv');
      expect(mimeForName('a.ogv'), 'video/ogg');
      expect(mimeForName('a.asf'), 'video/x-ms-asf');
    });

    test('and the new audio ones', () {
      expect(mimeForName('a.mka'), 'audio/x-matroska');
      expect(mimeForName('book.m4b'), 'audio/mp4');
      expect(mimeForName('a.dts'), 'audio/vnd.dts');
    });
  });
}
