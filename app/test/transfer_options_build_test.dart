import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildRcCall', () {
    test('plain copy carries srcFs/dstFs + async, no _config', () {
      final call = buildRcCall(const TransferOptions(), 'a:', 'b:');
      expect(call.method, 'sync/copy');
      expect(call.params['srcFs'], 'a:');
      expect(call.params['dstFs'], 'b:');
      expect(call.params['_async'], true);
      expect(call.params.containsKey('_config'), isFalse);
    });

    test('keepReplaced adds Suffix + SuffixKeepExtension to _config', () {
      final call = buildRcCall(
        const TransferOptions(mode: TransferMode.sync, keepReplaced: true),
        'a:',
        'b:',
      );
      expect(call.method, 'sync/sync');
      final config = call.params['_config'] as Map<String, dynamic>;
      expect(config['Suffix'], '.replaced');
      expect(config['SuffixKeepExtension'], true);
    });

    test('keepReplaced off leaves Suffix unset', () {
      final call = buildRcCall(const TransferOptions(), 'a:', 'b:');
      expect(call.params.containsKey('_config'), isFalse);
    });

    test('preview shows the suffix flags when keepReplaced', () {
      const o = TransferOptions(mode: TransferMode.move, keepReplaced: true);
      final cmd = rcloneCmdPreview(o, 'a:', 'b:');
      expect(cmd, contains('--suffix .replaced --suffix-keep-extension'));
    });
  });

  test('keepReplaced round-trips through JSON', () {
    const o = TransferOptions(keepReplaced: true);
    expect(TransferOptions.fromJson(o.toJson()).keepReplaced, isTrue);
    expect(const TransferOptions().toJson()['keepReplaced'], isFalse);
  });

  group('performance controls', () {
    test('map to the right _config keys (omitted at default)', () {
      final dflt = buildRcCall(const TransferOptions(), 'a:', 'b:');
      expect(dflt.params.containsKey('_config'), isFalse);

      final call = buildRcCall(
        const TransferOptions(
          transfers: 8,
          checkers: 16,
          orderBy: 'size,descending',
          trackRenames: true,
          immutable: true,
        ),
        'a:',
        'b:',
      );
      final cfg = call.params['_config'] as Map<String, dynamic>;
      expect(cfg['Transfers'], 8);
      expect(cfg['Checkers'], 16);
      expect(cfg['OrderBy'], 'size,descending');
      expect(cfg['TrackRenames'], true);
      expect(cfg['Immutable'], true);
    });

    test('preview shows the flags', () {
      const o = TransferOptions(
        transfers: 8,
        orderBy: 'size',
        trackRenames: true,
      );
      final cmd = rcloneCmdPreview(o, 'a:', 'b:');
      expect(cmd, contains('--transfers 8'));
      expect(cmd, contains('--order-by size'));
      expect(cmd, contains('--track-renames'));
    });

    test('JSON round-trips + omits defaults', () {
      const o = TransferOptions(transfers: 4, orderBy: 'name');
      final j = o.toJson();
      expect(j['transfers'], 4);
      expect(j.containsKey('checkers'), isFalse); // default 0 omitted
      final back = TransferOptions.fromJson(j);
      expect(back.transfers, 4);
      expect(back.orderBy, 'name');
      expect(back.checkers, 0);
    });
  });
}
