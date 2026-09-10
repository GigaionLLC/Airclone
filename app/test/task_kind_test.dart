import 'package:airclone/src/state/task_kind.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// A backup is a transfer task with its dangerous options taken away. These pin
/// the "taken away" part, because a backup that can be turned into a sync from
/// inside itself is not a backup — it is a data-loss incident waiting for the
/// night its source goes missing.
void main() {
  group('backupOptions', () {
    test('forces copy, whatever mode it was given', () {
      for (final m in TransferMode.values) {
        final o = backupOptions(TransferOptions(mode: m));
        expect(
          o.mode,
          TransferMode.copy,
          reason:
              '$m must not survive: sync deletes your history exactly when you '
              'need it, and move deletes the original',
        );
      }
    });

    test('keeps replaced files, which is what makes versions exist', () {
      expect(backupOptions(const TransferOptions()).keepReplaced, isTrue);
      // Even when explicitly turned off.
      expect(
        backupOptions(const TransferOptions(keepReplaced: false)).keepReplaced,
        isTrue,
      );
    });

    test('refuses to be a dry run', () {
      // The worst failure available: it looks like it worked every night.
      expect(
        backupOptions(const TransferOptions(dryRun: true)).dryRun,
        isFalse,
      );
    });

    test('leaves everything else alone', () {
      // It constrains three things; it is not a reset.
      const o = TransferOptions(
        transfers: 8,
        checkers: 16,
        skipExisting: true,
        compare: CompareMode.checksum,
      );
      final b = backupOptions(o);
      expect(b.transfers, 8);
      expect(b.checkers, 16);
      expect(b.skipExisting, isTrue);
      expect(b.compare, CompareMode.checksum);
    });

    test('is idempotent', () {
      final once = backupOptions(
        const TransferOptions(mode: TransferMode.sync),
      );
      expect(backupOptions(once).toJson(), once.toJson());
    });
  });

  group('isBackupShaped', () {
    test('recognises what backupOptions produces', () {
      for (final m in TransferMode.values) {
        expect(isBackupShaped(backupOptions(TransferOptions(mode: m))), isTrue);
      }
    });

    test('rejects each way a backup stops being one', () {
      expect(
        isBackupShaped(
          const TransferOptions(mode: TransferMode.sync, keepReplaced: true),
        ),
        isFalse,
      );
      expect(
        isBackupShaped(
          const TransferOptions(mode: TransferMode.copy, keepReplaced: false),
        ),
        isFalse,
      );
      expect(
        isBackupShaped(
          const TransferOptions(
            mode: TransferMode.copy,
            keepReplaced: true,
            dryRun: true,
          ),
        ),
        isFalse,
      );
    });
  });

  group('deviceFolderName', () {
    test('keeps an ordinary name', () {
      expect(deviceFolderName('Jakes-Laptop'), 'Jakes-Laptop');
    });

    test('strips what a remote path cannot carry', () {
      // A device name is user-controlled and ends up in a path.
      expect(deviceFolderName(r'a/b\c:d*e?f"g<h>i|j'), 'a-b-c-d-e-f-g-h-i-j');
    });

    test('trims leading and trailing dots and spaces', () {
      // Invalid on Windows, invisible everywhere else — a bad combination.
      expect(deviceFolderName('  .hidden.  '), 'hidden');
    });

    test('a name that sanitises to nothing still gets its own folder', () {
      // Falling through to an empty segment would back up into the PARENT,
      // merging this device with every other one.
      for (final n in ['', '   ', '...', '///', ':::']) {
        expect(deviceFolderName(n), 'device', reason: 'input: "$n"');
      }
    });
  });

  group('TaskKind on the model', () {
    TransferTask t({TaskKind kind = TaskKind.transfer}) => TransferTask(
      id: 'x',
      name: 'x',
      srcFs: 'a:',
      srcLabel: 'a:',
      dstFs: 'b:',
      dstLabel: 'b:',
      options: const TransferOptions(),
      kind: kind,
    );

    test('transfer is the default and is omitted from JSON', () {
      // So every task saved before this existed round-trips byte-identical.
      expect(t().kind, TaskKind.transfer);
      expect(t().toJson().containsKey('kind'), isFalse);
    });

    test('backup and photos survive a round trip', () {
      for (final k in [TaskKind.backup, TaskKind.photos]) {
        final back = TransferTask.fromJson(t(kind: k).toJson());
        expect(back.kind, k);
      }
    });

    test('an unknown kind from a newer build degrades to transfer', () {
      // The task still runs; it just loses its special vocabulary. Throwing
      // would lose the whole task list on downgrade.
      final j = t(kind: TaskKind.backup).toJson()..['kind'] = 'quantum';
      expect(TransferTask.fromJson(j).kind, TaskKind.transfer);
    });

    test('copyWith carries the kind', () {
      final b = t(kind: TaskKind.backup);
      expect(b.copyWith(name: 'renamed').kind, TaskKind.backup);
      expect(b.copyWith(kind: TaskKind.transfer).kind, TaskKind.transfer);
    });
  });
}
