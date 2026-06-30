import 'package:airclone/src/state/file_ops.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CompareResult.fromRpc parses buckets + hash usage', () {
    final r = CompareResult.fromRpc({
      'success': false,
      'status': '3 differences found',
      'hashType': 'md5',
      'match': ['a.txt', 'b.txt'],
      'differ': ['c.txt'],
      'missingOnSrc': ['d.txt'],
      'missingOnDst': <String>[],
      'error': <String>[],
    });
    expect(r.success, isFalse);
    expect(r.status, '3 differences found');
    expect(r.match.length, 2);
    expect(r.differ, ['c.txt']);
    expect(r.missingOnSrc, ['d.txt']);
    expect(r.missingOnDst, isEmpty);
    expect(r.usedHash, isTrue);
  });

  test('CompareResult.fromRpc tolerates missing fields + no hash', () {
    final r = CompareResult.fromRpc({'success': true});
    expect(r.success, isTrue);
    expect(r.match, isEmpty);
    expect(r.differ, isEmpty);
    expect(r.usedHash, isFalse); // hashType absent
  });

  test('usedHash is false for an explicit "none" hash', () {
    final r = CompareResult.fromRpc({'success': true, 'hashType': 'none'});
    expect(r.usedHash, isFalse);
  });
}
