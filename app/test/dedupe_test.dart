import 'package:airclone/src/state/dedupe.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _item(
  String path,
  String name,
  int size, {
  Map<String, String>? hashes,
  bool isDir = false,
}) {
  final m = <String, dynamic>{
    'Path': path,
    'Name': name,
    'Size': size,
    'IsDir': isDir,
  };
  if (hashes != null) m['Hashes'] = hashes;
  return m;
}

void main() {
  group('DupFile.fromJson', () {
    test('directories are not candidates', () {
      expect(DupFile.fromJson(_item('d', 'd', 0, isDir: true)), isNull);
    });

    test('a file with no hashes is not a candidate', () {
      expect(DupFile.fromJson(_item('a.txt', 'a.txt', 10)), isNull);
      expect(
        DupFile.fromJson(_item('a.txt', 'a.txt', 10, hashes: {})),
        isNull,
      );
      // empty hash strings don't count
      expect(
        DupFile.fromJson(_item('a.txt', 'a.txt', 10, hashes: {'MD5': ''})),
        isNull,
      );
    });

    test('signature folds in size + all non-empty hashes, sorted', () {
      final f = DupFile.fromJson(
        _item('a.txt', 'a.txt', 10, hashes: {'SHA-1': 'bbb', 'MD5': 'aaa'}),
      )!;
      expect(f.signature, '10|MD5:aaa|SHA-1:bbb');
    });

    test('same content but different declared size → different signature', () {
      final a = DupFile.fromJson(
        _item('a', 'a', 10, hashes: {'MD5': 'x'}),
      )!;
      final b = DupFile.fromJson(
        _item('b', 'b', 11, hashes: {'MD5': 'x'}),
      )!;
      expect(a.signature == b.signature, isFalse);
    });
  });

  group('findDuplicateGroups', () {
    DupFile f(String path, int size, Map<String, String> h) =>
        DupFile.fromJson(_item(path, path.split('/').last, size, hashes: h))!;

    test('identical content at distinct paths forms a group', () {
      final groups = findDuplicateGroups([
        f('a/x.txt', 10, {'MD5': 'h1'}),
        f('b/y.txt', 10, {'MD5': 'h1'}),
        f('c/lonely.txt', 20, {'MD5': 'h2'}),
      ]);
      expect(groups.length, 1);
      expect(groups.first.files.length, 2);
      expect(groups.first.size, 10);
      expect(groups.first.reclaimable, 10); // size * (2 - 1)
    });

    test('different hashes are never grouped (no false merge)', () {
      final groups = findDuplicateGroups([
        f('a.txt', 10, {'MD5': 'h1'}),
        f('b.txt', 10, {'MD5': 'h2'}), // same size, different content
      ]);
      expect(groups, isEmpty);
    });

    test('the same path appearing twice does NOT count as a duplicate', () {
      final groups = findDuplicateGroups([
        f('same.txt', 10, {'MD5': 'h1'}),
        f('same.txt', 10, {'MD5': 'h1'}),
      ]);
      expect(groups, isEmpty); // would be unsafe to "dedupe" one path
    });

    test('groups sort by reclaimable desc; files sort by path', () {
      final groups = findDuplicateGroups([
        // small group: 2 copies of a 5-byte file → 5 reclaimable
        f('z/small1', 5, {'MD5': 's'}),
        f('z/small2', 5, {'MD5': 's'}),
        // big group: 3 copies of a 100-byte file → 200 reclaimable
        f('m/big2', 100, {'MD5': 'b'}),
        f('a/big1', 100, {'MD5': 'b'}),
        f('q/big3', 100, {'MD5': 'b'}),
      ]);
      expect(groups.length, 2);
      expect(groups.first.reclaimable, 200); // big group first
      expect(groups.first.files.map((e) => e.path), [
        'a/big1',
        'm/big2',
        'q/big3',
      ]);
      expect(groups.last.reclaimable, 5);
    });
  });
}
