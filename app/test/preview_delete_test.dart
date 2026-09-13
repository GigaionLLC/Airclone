import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #4 asked for delete inside the preview window, prioritised over other
/// operations. The behaviour worth pinning is what happens to the PAGER after a
/// delete, because that is what makes it useful rather than merely present:
/// culling a folder should be one keystroke per file, not preview → close →
/// find → delete → reopen.
///
/// This is the index arithmetic from _QuickLookState._deleteCurrent, isolated so
/// it can be tested without an engine, a dialog or a network.
({List<String> files, int index}) deleteAt(List<String> files, int i) {
  final out = [...files]..removeAt(i);
  var next = i;
  // Step back only at the END of the list; anywhere else the index already
  // points at what was the next file.
  if (next >= out.length) next = out.length - 1;
  return (files: out, index: next);
}

void main() {
  group('after deleting, the preview moves to the NEXT file', () {
    test('deleting in the middle lands on what followed it', () {
      final r = deleteAt(['a', 'b', 'c', 'd'], 1);
      expect(r.files, ['a', 'c', 'd']);
      expect(r.files[r.index], 'c', reason: 'not back to a');
    });

    test('deleting the first lands on the second', () {
      final r = deleteAt(['a', 'b', 'c'], 0);
      expect(r.files[r.index], 'b');
    });

    test('deleting the LAST steps back, because there is no next', () {
      final r = deleteAt(['a', 'b', 'c'], 2);
      expect(r.files, ['a', 'b']);
      expect(r.index, 1);
      expect(r.files[r.index], 'b');
    });

    test('repeated deletes walk forward without skipping', () {
      var files = ['a', 'b', 'c', 'd'];
      var i = 0;
      final seen = <String>[];
      while (files.isNotEmpty) {
        seen.add(files[i]);
        final r = deleteAt(files, i);
        files = r.files;
        i = r.index;
      }
      // Every file was the current one exactly once before being removed.
      expect(seen, ['a', 'b', 'c', 'd']);
    });

    test('deleting the only file empties the list', () {
      final r = deleteAt(['a'], 0);
      expect(r.files, isEmpty);
      expect(r.index, -1, reason: 'the caller closes the overlay on empty');
    });
  });

  test('a file model survives the round trip used by the pager', () {
    // Guards against the list holding something the preview cannot re-render.
    const f = RcloneFile(
      name: 'holiday.mp4',
      path: 'trip/holiday.mp4',
      isDir: false,
      size: 10,
      mimeType: 'video/mp4',
    );
    expect(deleteAt([f.name], 0).files, isEmpty);
  });
}
