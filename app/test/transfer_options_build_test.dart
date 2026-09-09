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

  group('the preview describes the run', () {
    // The `rclone cmd` tab is the thing people copy out and run by hand, so a
    // flag it shows that the dispatcher does not send is worse than showing no
    // flags at all. `extraFlags` was exactly that: rendered into the preview,
    // dropped by buildRcCall. Nothing ever wrote to it, so it never lied in
    // practice — it was a trap for whoever wired up the next input. It is gone,
    // and a saved task carrying the old key must not bring it back.
    test('a dropped key in a saved task is ignored, not resurrected', () {
      final o = TransferOptions.fromJson({
        'mode': 'sync',
        'extraFlags': ['--transfers 99', '--delete-during'],
      });
      final cmd = rcloneCmdPreview(o, 'a:', 'b:');
      expect(cmd, isNot(contains('99')));
      expect(cmd, isNot(contains('--delete-during')));
      expect(o.toJson().containsKey('extraFlags'), isFalse);
    });

    test('and the run it describes is the one that is dispatched', () {
      // Spot-check both directions on the flags that do exist: each one the
      // preview prints has a _config counterpart, and vice versa.
      const o = TransferOptions(
        mode: TransferMode.sync,
        transfers: 8,
        maxDeleteFiles: 5,
        compare: CompareMode.checksum,
      );
      final cmd = rcloneCmdPreview(o, 'a:', 'b:');
      final config =
          buildRcCall(o, 'a:', 'b:').params['_config']! as Map<String, dynamic>;
      expect(cmd, contains('--transfers 8'));
      expect(config['Transfers'], 8);
      expect(cmd, contains('--max-delete 5'));
      expect(config['MaxDelete'], 5);
      expect(cmd, contains('--checksum'));
      expect(config['Checksum'], true);
    });
  });
}
