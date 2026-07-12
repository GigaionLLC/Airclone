import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/ui/file_icon.dart';
import 'package:flutter_test/flutter_test.dart';

/// `isGalleryMedia` is the single source of truth for what the media Gallery view
/// displays AND for what `selectAll` picks in that view. The load-bearing
/// property is data-safety: "Select all" in gallery view must NEVER select a
/// folder (which a later bulk Delete would recursively purge) or a hidden
/// non-media file the user can't see.
void main() {
  RcloneFile file(String name, {bool isDir = false, String mime = ''}) =>
      RcloneFile(name: name, path: name, isDir: isDir, mimeType: mime);

  group('isGalleryMedia', () {
    test('true for images and videos', () {
      for (final n in ['a.jpg', 'b.png', 'c.gif', 'd.webp', 'e.mp4', 'f.mov']) {
        expect(isGalleryMedia(file(n)), isTrue, reason: n);
      }
      // mime-type fallback when the extension is unknown.
      expect(isGalleryMedia(file('clip', mime: 'video/mp4')), isTrue);
    });

    test('FALSE for folders — the Select-all data-safety guarantee', () {
      expect(isGalleryMedia(file('Photos', isDir: true)), isFalse);
      // Even a folder whose name looks like an image is excluded.
      expect(isGalleryMedia(file('holiday.jpg', isDir: true)), isFalse);
    });

    test('false for documents and other non-media files', () {
      for (final n in ['report.pdf', 'data.csv', 'notes.txt', 'song.mp3']) {
        expect(isGalleryMedia(file(n)), isFalse, reason: n);
      }
    });
  });
}
