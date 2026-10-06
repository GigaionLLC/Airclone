import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/state/pane_search.dart';
import 'package:flutter_test/flutter_test.dart';

RcloneFile _f(String rel, {bool dir = false}) =>
    RcloneFile(name: rel.split('/').last, path: rel, isDir: dir, size: 1);

void main() {
  group('matchesName (This folder)', () {
    test('every word must appear in the name, any case, any order', () {
      expect(matchesName('Holiday Video 2024.mp4', 'holiday'), isTrue);
      expect(matchesName('Holiday Video 2024.mp4', '2024 HOLIDAY'), isTrue);
      expect(matchesName('Holiday Video 2024.mp4', 'holiday 2023'), isFalse);
    });

    test('an empty or blank query matches everything', () {
      expect(matchesName('a.txt', ''), isTrue);
      expect(matchesName('a.txt', '   '), isTrue);
    });
  });

  group('hitsFromListing', () {
    test('resolves rclone\'s relative paths against the search root once', () {
      final (hits, truncated) = hitsFromListing([
        _f('a.txt'),
        _f('Photos', dir: true),
        _f('Photos/2024/beach.jpg'),
      ], 'Media');
      expect(truncated, isFalse);
      expect(hits.map((h) => h.absPath), [
        'Media/a.txt',
        'Media/Photos',
        'Media/Photos/2024/beach.jpg',
      ]);
      expect(hits.map((h) => h.relParent), ['', '', 'Photos/2024']);
      expect(hits.last.parentPath, 'Media/Photos/2024');
    });

    test('at the remote root the paths stay as rclone gave them', () {
      final (hits, _) = hitsFromListing([_f('x/y.txt')], '');
      expect(hits.single.absPath, 'x/y.txt');
      expect(hits.single.parentPath, 'x');
    });

    test('stops at the cap and says so', () {
      final (hits, truncated) = hitsFromListing(
        [for (var i = 0; i < 5; i++) _f('f$i.txt')],
        '',
        cap: 3,
      );
      expect(hits, hasLength(3));
      expect(truncated, isTrue);
    });
  });

  group('matchHits (Subfolders)', () {
    final (all, _) = hitsFromListing([
      _f('notes/holiday plan.txt'),
      _f('holiday', dir: true),
      _f('holiday/beach.jpg'),
      _f('archive/old-holiday.zip'),
      _f('2024/holiday/sea.mp4'),
      _f('work/report.pdf'),
    ], '');

    test('an empty query lists nothing', () {
      expect(matchHits(all, ''), isEmpty);
      expect(matchHits(all, '  '), isEmpty);
    });

    test('ranks name-starts-with, then name-contains, then path-only; '
        'folders first within a rank', () {
      expect(matchHits(all, 'holiday').map((h) => h.absPath), [
        'holiday', // folder, name starts with
        'notes/holiday plan.txt', // file, name starts with
        'archive/old-holiday.zip', // name contains
        '2024/holiday/sea.mp4', // only the path matches
        'holiday/beach.jpg',
      ]);
    });

    test('words may match across the folder path and the name', () {
      expect(matchHits(all, '2024 sea').map((h) => h.absPath), [
        '2024/holiday/sea.mp4',
      ]);
      expect(matchHits(all, 'report beach'), isEmpty);
    });

    test('the search root itself is not part of what is matched', () {
      final (hits, _) = hitsFromListing([_f('a.txt')], 'Holiday');
      expect(matchHits(hits, 'holiday'), isEmpty);
    });
  });

  test('siblingsIn returns a folder\'s entries from the scan', () {
    final (all, _) = hitsFromListing([
      _f('A/x.txt'),
      _f('A/y.txt'),
      _f('B/x.txt'),
    ], 'root');
    expect(siblingsIn(all, 'root/A').map((f) => f.name), ['x.txt', 'y.txt']);
    expect(siblingsIn(all, 'root/C'), isEmpty);
  });
}
