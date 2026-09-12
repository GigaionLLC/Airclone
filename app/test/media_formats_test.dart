import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/state/media_formats.dart';
import 'package:airclone/src/ui/file_icon.dart';
import 'package:flutter_test/flutter_test.dart';

/// A customer asked for HLS and network streaming. The decoding was never the
/// problem — the shipped libmpv carries the `hls` demuxer on every platform we
/// build for — so all of this is about how Airclone CLASSIFIES a manifest, and
/// about the things that must not happen to one.
RcloneFile _file(String name, {String mime = ''}) =>
    RcloneFile(name: name, path: name, isDir: false, size: 10, mimeType: mime);

void main() {
  group('a streaming manifest plays as video', () {
    for (final name in ['stream.m3u8', 'playlist.m3u', 'manifest.mpd']) {
      test('$name is video, not "generic"', () {
        expect(kindOf(_file(name)), FileKind.video);
      });
    }

    test('the case of the extension does not matter', () {
      expect(kindOf(_file('STREAM.M3U8')), FileKind.video);
    });
  });

  group('a manifest is never thumbnailed', () {
    // It holds no frame to capture. A live one reports no duration, so the
    // blank-frame retry is skipped and the first black slate is cached as
    // permanently undecodable. And every attempt pins a libmpv instance against
    // a network origin for the full timeout, which is the starvation the video
    // thumbnail semaphore exists to prevent.
    for (final name in ['stream.m3u8', 'playlist.m3u', 'manifest.mpd']) {
      test('$name is video but NOT video-thumbnailable', () {
        final f = _file(name);
        expect(kindOf(f), FileKind.video, reason: 'still previews as video');
        expect(isVideoThumbnailable(f), isFalse);
        expect(isThumbnailable(f), isFalse);
      });
    }

    test('a real video still IS thumbnailable', () {
      expect(isVideoThumbnailable(_file('holiday.mp4')), isTrue);
    });
  });

  group('.ts stays TypeScript', () {
    // It is both an MPEG transport-stream segment and the TypeScript extension.
    // In a file manager the second is overwhelmingly more likely, and libmpv
    // still fetches .ts segments itself when a manifest names them — which is
    // the case that actually matters.
    test('app.ts is code, not video', () {
      expect(kindOf(_file('app.ts')), FileKind.code);
    });
  });

  group('the tables no longer disagree with each other', () {
    // file_icon.dart and preview_dialog.dart each kept their own video/audio
    // lists, and they had drifted: .flv was in one and not the other, so an
    // .flv showed a film-strip icon and then "No preview available".
    test('flv is video', () {
      expect(kindOf(_file('clip.flv')), FileKind.video);
      expect(isVideoLikeExt('flv'), isTrue);
    });

    test('every video extension is video-like', () {
      for (final e in kVideoExts) {
        expect(isVideoLikeExt(e), isTrue, reason: e);
      }
    });

    test('video and audio sets do not overlap', () {
      expect(kVideoExts.intersection(kAudioExts), isEmpty);
    });

    test('a manifest is not also claimed by the audio pipeline', () {
      // rclone reports .m3u8 as audio/x-mpegurl on some backends. Before this
      // was classified by extension, that mime fallback handed the PLAYLIST
      // FILE to the audio player, which is a confusing half-working path.
      for (final e in kPlaylistExts) {
        expect(isAudioExt(e), isFalse, reason: e);
        expect(isVideoLikeExt(e), isTrue, reason: e);
      }
    });

    test('extension wins over a misleading mime type', () {
      expect(
        kindOf(_file('stream.m3u8', mime: 'audio/x-mpegurl')),
        FileKind.video,
      );
    });
  });
}
