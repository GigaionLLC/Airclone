import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildRcCall — bisync', () {
    test(
      'uses sync/bisync with path1/path2 + async, no srcFs/dstFs/_config',
      () {
        final call = buildRcCall(
          const TransferOptions(mode: TransferMode.bisync),
          'a:dir',
          'b:dir',
        );
        expect(call.method, 'sync/bisync');
        expect(call.params['path1'], 'a:dir');
        expect(call.params['path2'], 'b:dir');
        expect(call.params['_async'], true);
        expect(call.params.containsKey('srcFs'), isFalse);
        expect(call.params.containsKey('dstFs'), isFalse);
        expect(call.params.containsKey('_config'), isFalse);
      },
    );

    test('resync adds resync + resyncMode; otherwise both absent', () {
      final first = buildRcCall(
        const TransferOptions(mode: TransferMode.bisync, resyncMode: 'newer'),
        'a:',
        'b:',
        resync: true,
      );
      expect(first.params['resync'], true);
      expect(first.params['resyncMode'], 'newer');

      final normal = buildRcCall(
        const TransferOptions(mode: TransferMode.bisync),
        'a:',
        'b:',
      );
      expect(normal.params.containsKey('resync'), isFalse);
      expect(normal.params.containsKey('resyncMode'), isFalse);
    });

    test('conflict + maxDelete defaults are omitted, non-defaults sent', () {
      final dft = buildRcCall(
        const TransferOptions(mode: TransferMode.bisync),
        'a:',
        'b:',
      );
      for (final k in [
        'conflictResolve',
        'conflictLoser',
        'conflictSuffix',
        'maxDelete',
      ]) {
        expect(dft.params.containsKey(k), isFalse, reason: k);
      }
      expect(dft.params.containsKey('force'), isFalse); // never auto-forced

      final custom = buildRcCall(
        const TransferOptions(
          mode: TransferMode.bisync,
          conflictResolve: 'newer',
          maxDeletePercent: 80,
          checkAccess: true,
        ),
        'a:',
        'b:',
      );
      expect(custom.params['conflictResolve'], 'newer');
      expect(
        custom.params['maxDelete'],
        80,
      ); // percent, top-level (not _config)
      expect(custom.params['checkAccess'], true);
    });

    test('filters still apply to bisync', () {
      final call = buildRcCall(
        const TransferOptions(mode: TransferMode.bisync, excludes: ['*.tmp']),
        'a:',
        'b:',
      );
      final filter = call.params['_filter'] as Map<String, dynamic>;
      expect(filter['ExcludeRule'], ['*.tmp']);
    });
  });

  test('preview shows rclone bisync + --resync until baseline established', () {
    const fresh = TransferOptions(mode: TransferMode.bisync);
    final p1 = rcloneCmdPreview(fresh, 'a:', 'b:');
    expect(p1, startsWith('rclone bisync'));
    expect(p1, contains('--resync'));

    const settled = TransferOptions(
      mode: TransferMode.bisync,
      baselineEstablished: true,
      maxDeletePercent: 80,
    );
    final p2 = rcloneCmdPreview(settled, 'a:', 'b:');
    expect(p2, isNot(contains('--resync')));
    expect(p2, contains('--max-delete 80'));
  });

  group('bisync JSON back-compat', () {
    test(
      'legacy sync task (no bisync keys) loads defaults + omits on write',
      () {
        final legacy = {
          'mode': 'sync',
          'includes': <String>[],
          'excludes': <String>[],
          'filters': <String>[],
        };
        final o = TransferOptions.fromJson(legacy);
        expect(o.mode, TransferMode.sync);
        expect(o.resyncMode, 'path1');
        expect(o.conflictResolve, 'none');
        expect(o.maxDeletePercent, 50);
        expect(o.baselineEstablished, isFalse);
        // toJson must not add bisync keys for an all-default options
        final j = o.toJson();
        for (final k in [
          'resyncMode',
          'conflictResolve',
          'maxDeletePercent',
          'baselineEstablished',
        ]) {
          expect(j.containsKey(k), isFalse, reason: k);
        }
      },
    );

    test('a bisync task with non-defaults round-trips', () {
      const o = TransferOptions(
        mode: TransferMode.bisync,
        conflictResolve: 'newer',
        maxDeletePercent: 75,
        baselineEstablished: true,
      );
      final back = TransferOptions.fromJson(o.toJson());
      expect(back.mode, TransferMode.bisync);
      expect(back.conflictResolve, 'newer');
      expect(back.maxDeletePercent, 75);
      expect(back.baselineEstablished, isTrue);
    });
  });
}
