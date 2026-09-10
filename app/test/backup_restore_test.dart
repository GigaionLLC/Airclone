import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/backup_restore.dart';
import 'package:airclone/src/state/task_kind.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// Restore is deliberately thin: a backup destination is an ordinary remote
/// folder, so restoring is opening it and copying out of it, through the same
/// conflict preflight every other transfer already goes through.
///
/// What is left to get right is the addressing and the grouping — pointing a
/// pane at the wrong folder, or hiding the one version someone came for.
TransferTask task({
  String dstFs = 'gdrive:Airclone/Backups/laptop/Docs',
  TaskKind kind = TaskKind.backup,
}) => TransferTask(
  id: '1',
  name: 'Back up Docs',
  srcFs: 'local:Docs',
  srcLabel: 'local:Docs',
  dstFs: dstFs,
  dstLabel: dstFs,
  options: const TransferOptions(),
  kind: kind,
);

void main() {
  group('splitFs', () {
    test('splits on the FIRST colon, not the last', () {
      // A path may legitimately contain a colon; splitting on the last one
      // would address a different folder entirely.
      final s = splitFs('gdrive:Notes/2026:Q1/plan')!;
      expect(s.remoteName, 'gdrive');
      expect(s.path, 'Notes/2026:Q1/plan');
    });

    test('a remote root gives an empty path, not a slash', () {
      expect(splitFs('gdrive:')!.path, '');
    });

    test('leading and trailing slashes are trimmed', () {
      expect(splitFs('gdrive:/Backups/')!.path, 'Backups');
    });

    test('null for something that is not an fs at all', () {
      for (final s in ['', 'nocolon', ':leading']) {
        expect(splitFs(s), isNull, reason: s);
      }
    });
  });

  group('restoreRemoteFor', () {
    const gdrive = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');
    const other = Remote(name: 'other', type: 's3', fs: 'other:');

    test('finds the remote a backup writes to', () {
      expect(restoreRemoteFor(task(), [other, gdrive]), gdrive);
    });

    test('null when the remote has been deleted since', () {
      // The honest answer is "that backup's remote is gone", not a crash or an
      // empty pane with no explanation.
      expect(restoreRemoteFor(task(), [other]), isNull);
    });

    test('null for a malformed destination', () {
      expect(restoreRemoteFor(task(dstFs: 'garbage'), [gdrive]), isNull);
    });
  });

  group('canRestoreFrom', () {
    test('backups and photo backups, yes', () {
      expect(canRestoreFrom(task(kind: TaskKind.backup)), isTrue);
      expect(canRestoreFrom(task(kind: TaskKind.photos)), isTrue);
    });

    test('a plain transfer, no', () {
      // Its destination has no version history and nothing promises the source
      // is recoverable, so offering "restore" would claim something untrue.
      expect(canRestoreFrom(task(kind: TaskKind.transfer)), isFalse);
    });
  });
}
