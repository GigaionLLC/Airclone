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
}
