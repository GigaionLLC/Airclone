import 'package:airclone/src/rclone/models/transfer_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransferItem.listFrom', () {
    test('parses a core/stats transferring array', () {
      final items = TransferItem.listFrom([
        {'name': 'a.bin', 'percentage': 40, 'speed': 1000.0, 'bytes': 40, 'size': 100},
        {'name': 'b.bin', 'percentage': 10, 'size': 50},
      ]);
      expect(items.length, 2);
      expect(items[0].name, 'a.bin');
      expect(items[0].percentage, 40);
      expect(items[0].speed, 1000.0);
      expect(items[0].bytes, 40);
      expect(items[0].size, 100);
      // Missing fields default to 0.
      expect(items[1].percentage, 10);
      expect(items[1].speed, 0);
      expect(items[1].bytes, 0);
    });

    test('null / non-list input yields an empty list', () {
      expect(TransferItem.listFrom(null), isEmpty);
      expect(TransferItem.listFrom('nope'), isEmpty);
      expect(TransferItem.listFrom(const {}), isEmpty);
    });

    test('non-map entries in the list are skipped', () {
      final items = TransferItem.listFrom([
        'garbage',
        {'name': 'ok.bin', 'percentage': 5},
        42,
      ]);
      expect(items.map((t) => t.name), ['ok.bin']);
    });

    test('missing name becomes empty string, not a throw', () {
      final items = TransferItem.listFrom([
        {'percentage': 1},
      ]);
      expect(items.single.name, '');
    });
  });
}
