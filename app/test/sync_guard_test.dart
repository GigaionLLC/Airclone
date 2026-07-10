import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('one-way Sync --max-delete guard (maxDeleteFiles)', () {
    Map<String, dynamic> configOf(TransferOptions o) {
      final call = buildRcCall(o, 'a:dir', 'b:dir');
      return (call.params['_config'] as Map<String, dynamic>?) ?? const {};
    }

    test('sync with a cap adds MaxDelete (a count) to _config', () {
      final cfg = configOf(
        const TransferOptions(mode: TransferMode.sync, maxDeleteFiles: 100),
      );
      expect(cfg['MaxDelete'], 100);
    });

    test('sync without a cap omits MaxDelete entirely', () {
      // No cap and no other config ⇒ no _config map at all.
      final call = buildRcCall(
        const TransferOptions(mode: TransferMode.sync),
        'a:dir',
        'b:dir',
      );
      expect(call.params.containsKey('_config'), isFalse);
      // With another option set, _config exists but has no MaxDelete key.
      final cfg = configOf(
        const TransferOptions(mode: TransferMode.sync, immutable: true),
      );
      expect(cfg.containsKey('MaxDelete'), isFalse);
    });

    test('copy/move never get MaxDelete even when a cap is set', () {
      for (final mode in [TransferMode.copy, TransferMode.move]) {
        final cfg = configOf(TransferOptions(mode: mode, maxDeleteFiles: 5));
        expect(cfg.containsKey('MaxDelete'), isFalse, reason: mode.name);
      }
    });

    test('a NEGATIVE cap is never emitted — it means unlimited to rclone', () {
      // Fail-open guard: -1 would DISABLE the delete cap, the opposite of what
      // a safety field promises. The input rejects negatives; this covers the
      // belt in the builder for values arriving via hand-edited JSON.
      final o = const TransferOptions(
        mode: TransferMode.sync,
        maxDeleteFiles: -1,
      );
      expect(configOf(o).containsKey('MaxDelete'), isFalse);
      expect(
        rcloneCmdPreview(o, 'a:dir', 'b:dir').contains('--max-delete'),
        isFalse,
      );
      // Zero is a legitimate cap (abort on any delete) and IS emitted.
      final zero = const TransferOptions(
        mode: TransferMode.sync,
        maxDeleteFiles: 0,
      );
      expect(configOf(zero)['MaxDelete'], 0);
    });

    test(
      'CLI preview shows --max-delete N for a capped sync, else nothing',
      () {
        const capped = TransferOptions(
          mode: TransferMode.sync,
          maxDeleteFiles: 100,
        );
        expect(
          rcloneCmdPreview(capped, 'a:', 'b:'),
          contains('--max-delete 100'),
        );

        const uncapped = TransferOptions(mode: TransferMode.sync);
        expect(
          rcloneCmdPreview(uncapped, 'a:', 'b:'),
          isNot(contains('--max-delete')),
        );

        // A cap on a copy is inert — it must not surface in the preview.
        const copyCapped = TransferOptions(
          mode: TransferMode.copy,
          maxDeleteFiles: 100,
        );
        expect(
          rcloneCmdPreview(copyCapped, 'a:', 'b:'),
          isNot(contains('--max-delete')),
        );
      },
    );
  });

  group('maxDeleteFiles JSON back-compat', () {
    test('omitted when null so legacy sync task JSON is unchanged', () {
      final legacy = {
        'mode': 'sync',
        'includes': <String>[],
        'excludes': <String>[],
        'filters': <String>[],
      };
      final o = TransferOptions.fromJson(legacy);
      expect(o.maxDeleteFiles, isNull);
      expect(o.toJson().containsKey('maxDeleteFiles'), isFalse);
    });

    test('a capped sync round-trips', () {
      const o = TransferOptions(mode: TransferMode.sync, maxDeleteFiles: 250);
      final back = TransferOptions.fromJson(o.toJson());
      expect(back.maxDeleteFiles, 250);
    });
  });

  group('copyWith clears vs. keeps the cap', () {
    test('explicit null clears the cap; omitting the arg keeps it', () {
      const base = TransferOptions(mode: TransferMode.sync, maxDeleteFiles: 42);
      // Omitting the argument leaves the cap in place.
      expect(base.copyWith(dryRun: true).maxDeleteFiles, 42);
      // Passing null clears it (the field's "no cap" state).
      expect(base.copyWith(maxDeleteFiles: null).maxDeleteFiles, isNull);
      // Passing a new number replaces it.
      expect(base.copyWith(maxDeleteFiles: 7).maxDeleteFiles, 7);
    });
  });
}
