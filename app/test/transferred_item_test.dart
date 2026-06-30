import 'package:airclone/src/rclone/models/transferred_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a successful transferred entry', () {
    final list = TransferredItem.listFromResponse({
      'transferred': [
        {
          'name': 'a.txt',
          'size': 1024,
          'bytes': 1024,
          'checked': false,
          'what': 'transferring',
          'group': 'airclone/3',
          'srcFs': 'gdrive:',
          'dstFs': 's3:',
          'error': '',
          'started_at': '2026-06-28T10:00:00.000Z',
          'completed_at': '2026-06-28T10:00:05.000Z',
        },
      ],
    });
    expect(list, hasLength(1));
    final it = list.first;
    expect(it.name, 'a.txt');
    expect(it.size, 1024);
    expect(it.succeeded, isTrue);
    expect(it.failed, isFalse);
    expect(it.error, isNull);
    expect(it.srcFs, 'gdrive:');
    expect(it.startedAt, isNotNull);
    expect(it.completedAt, isNotNull);
  });

  test('a non-empty error means failed', () {
    final list = TransferredItem.listFromResponse({
      'transferred': [
        {'name': 'x', 'size': 1, 'bytes': 0, 'error': 'permission denied'},
      ],
    });
    expect(list.first.failed, isTrue);
    expect(list.first.error, 'permission denied');
  });

  test('tolerates omitted srcFs/dstFs/timestamps', () {
    final list = TransferredItem.listFromResponse({
      'transferred': [
        {
          'name': 'b.txt',
          'size': 10,
          'bytes': 10,
          'checked': true,
          'what': 'checking',
          'group': '',
          'error': '',
        },
      ],
    });
    final it = list.first;
    expect(it.srcFs, isNull);
    expect(it.dstFs, isNull);
    expect(it.startedAt, isNull);
    expect(it.checked, isTrue);
    expect(it.succeeded, isTrue);
    expect(it.what, 'checking'); // opaque string, not validated
  });

  test('Go zero-time parses to null (not year 0001)', () {
    final list = TransferredItem.listFromResponse({
      'transferred': [
        {
          'name': 'z',
          'error': '',
          'started_at': '0001-01-01T00:00:00Z',
          'completed_at': '0001-01-01T00:00:00Z',
        },
      ],
    });
    expect(list.first.startedAt, isNull);
    expect(list.first.completedAt, isNull);
  });

  test('a nanosecond/offset RFC3339 timestamp still parses', () {
    final list = TransferredItem.listFromResponse({
      'transferred': [
        {
          'name': 'n',
          'error': '',
          'completed_at': '2026-06-28T10:00:00.123456789+01:00',
        },
      ],
    });
    expect(list.first.completedAt, isNotNull);
  });

  test('missing / non-list transferred key yields an empty list', () {
    expect(TransferredItem.listFromResponse({}), isEmpty);
    expect(TransferredItem.listFromResponse({'transferred': null}), isEmpty);
  });

  test('newest-first ordering (rclone returns oldest-first)', () {
    final list = TransferredItem.listFromResponse({
      'transferred': [
        {'name': 'old', 'error': '', 'started_at': '2026-06-28T10:00:00Z'},
        {'name': 'new', 'error': '', 'started_at': '2026-06-28T11:00:00Z'},
      ],
    });
    expect(list.first.name, 'new');
    expect(list.last.name, 'old');
  });
}
