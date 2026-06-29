import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/ui/file_icon.dart';
import 'package:flutter_test/flutter_test.dart';

RcloneFile _f(String name, {bool isDir = false, String mime = ''}) =>
    RcloneFile(name: name, path: name, isDir: isDir, mimeType: mime);

void main() {
  group('kindOf', () {
    test('directories are folders', () {
      expect(kindOf(_f('Photos', isDir: true)), FileKind.folder);
    });

    test('classifies by extension', () {
      expect(kindOf(_f('a.JPG')), FileKind.image);
      expect(kindOf(_f('clip.mp4')), FileKind.video);
      expect(kindOf(_f('song.flac')), FileKind.audio);
      expect(kindOf(_f('doc.pdf')), FileKind.pdf);
      expect(kindOf(_f('bundle.tar.gz')), FileKind.archive);
      expect(kindOf(_f('main.dart')), FileKind.code);
      expect(kindOf(_f('sheet.xlsx')), FileKind.document);
    });

    test('falls back to mime type when extension is unknown', () {
      expect(kindOf(_f('blob', mime: 'image/png')), FileKind.image);
      expect(kindOf(_f('blob', mime: 'application/pdf')), FileKind.pdf);
    });

    test('dotfiles and no-dot names are generic', () {
      expect(kindOf(_f('.env')), FileKind.generic);
      expect(kindOf(_f('README')), FileKind.generic);
    });
  });

  test('isImageThumbnailable only for images', () {
    expect(isImageThumbnailable(_f('a.png')), isTrue);
    expect(isImageThumbnailable(_f('a.mp4')), isFalse);
    expect(isImageThumbnailable(_f('folder', isDir: true)), isFalse);
  });
}
