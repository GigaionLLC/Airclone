import 'package:airclone/src/state/backup_task.dart';
import 'package:airclone/src/state/task_kind.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where a backup lands, and what it is once created.
///
/// The destination path is worth this much attention because getting it wrong
/// is not a cosmetic bug: two devices sharing a folder means a restore can put
/// a laptop's files on a phone, and a leading or doubled slash makes rclone
/// address a path the user never chose.
void main() {
  group('backupFolderLeaf', () {
    test('a folder backs up under its own name, not its whole path', () {
      expect(
        backupFolderLeaf(remoteName: 'local', path: 'Projects/Airclone'),
        'Airclone',
      );
      expect(
        backupFolderLeaf(remoteName: 'local', path: r'D:\Projects\Airclone'),
        'Airclone',
      );
    });

    test('a trailing separator does not produce an empty leaf', () {
      expect(
        backupFolderLeaf(remoteName: 'local', path: 'Projects/Airclone/'),
        'Airclone',
      );
    });

    test('a remote root falls back to the remote name', () {
      // There is no folder name to use, and an empty segment would put this
      // backup in the parent alongside every other one.
      expect(backupFolderLeaf(remoteName: 'gdrive', path: ''), 'gdrive');
    });

    test('a leaf a path cannot carry is sanitised', () {
      expect(backupFolderLeaf(remoteName: 'local', path: 'a/b:c*d'), 'b-c-d');
    });
  });

  group('backupDestinationPath', () {
    test('lands under a recognisable root, per device, per folder', () {
      expect(
        backupDestinationPath(
          destPath: 'Archive',
          deviceName: 'Jakes-Laptop',
          sourceRemoteName: 'local',
          sourcePath: 'Projects/Airclone',
        ),
        'Archive/Airclone/Backups/Jakes-Laptop/Airclone',
      );
    });

    test('at a remote root there is no leading slash', () {
      // An empty destPath must not produce '/Airclone/Backups/...', which
      // addresses a different path than the user picked.
      final p = backupDestinationPath(
        destPath: '',
        deviceName: 'phone',
        sourceRemoteName: 'local',
        sourcePath: 'DCIM',
      );
      expect(p, 'Airclone/Backups/phone/DCIM');
      expect(p.startsWith('/'), isFalse);
    });

    test('slashes never double up', () {
      final p = backupDestinationPath(
        destPath: '/Archive/',
        deviceName: 'pc',
        sourceRemoteName: 'local',
        sourcePath: 'Docs',
      );
      expect(p, 'Archive/Airclone/Backups/pc/Docs');
      expect(p.contains('//'), isFalse);
    });

    test('two devices never share a folder', () {
      // The failure this prevents: a restore putting a laptop's files on a
      // phone, discovered long after the fact.
      String forDevice(String d) => backupDestinationPath(
        destPath: 'Archive',
        deviceName: d,
        sourceRemoteName: 'local',
        sourcePath: 'Docs',
      );
      expect(forDevice('laptop'), isNot(forDevice('phone')));
    });

    test('a photo backup is per-device, not per-folder', () {
      // Several source folders all mirror into one Photos tree — that is what
      // "mirror the source structure" means when the source is a SET.
      final dcim = backupDestinationPath(
        destPath: '',
        deviceName: 'phone',
        sourceRemoteName: 'local',
        sourcePath: 'DCIM',
        photos: true,
      );
      final other = backupDestinationPath(
        destPath: '',
        deviceName: 'phone',
        sourceRemoteName: 'local',
        sourcePath: 'Pictures/Screenshots',
        photos: true,
      );
      expect(dcim, 'Airclone/Photos/phone');
      expect(other, dcim, reason: 'one tree per device, not one per folder');
    });
  });

  group('buildBackupTask', () {
    const daily = TaskSchedule(kind: ScheduleKind.daily, hour: 2, minute: 0);

    test('is a backup, and carries the backup constraints', () {
      final t = buildBackupTask(
        id: '1',
        name: 'Projects',
        srcFs: 'local:',
        srcLabel: 'local:Projects',
        dstFs: 'gdrive:',
        dstLabel: 'gdrive:Archive',
        schedule: daily,
      );
      expect(t.kind, TaskKind.backup);
      expect(isBackupShaped(t.options), isTrue);
      expect(t.options.mode, TransferMode.copy);
      expect(t.options.keepReplaced, isTrue);
    });

    test('a hostile base cannot smuggle a sync through the wizard', () {
      // The wizard is not the advanced dialog and must not become a way to
      // reach one.
      final t = buildBackupTask(
        id: '1',
        name: 'x',
        srcFs: 'a:',
        srcLabel: 'a:',
        dstFs: 'b:',
        dstLabel: 'b:',
        schedule: null,
        base: const TransferOptions(
          mode: TransferMode.sync,
          keepReplaced: false,
          dryRun: true,
        ),
      );
      expect(t.options.mode, TransferMode.copy);
      expect(t.options.keepReplaced, isTrue);
      expect(t.options.dryRun, isFalse);
    });

    test('photos gets its own kind', () {
      final t = buildBackupTask(
        id: '1',
        name: 'Camera roll',
        srcFs: 'local:',
        srcLabel: 'DCIM',
        dstFs: 'gdrive:',
        dstLabel: 'gdrive:',
        schedule: daily,
        photos: true,
      );
      expect(t.kind, TaskKind.photos);
      expect(isBackupShaped(t.options), isTrue);
    });

    test('a new backup has never run, so its first slot fires', () {
      // Stamping lastRun at creation would silently skip the first scheduled
      // run and read as "already up to date" before anything was copied.
      final t = buildBackupTask(
        id: '1',
        name: 'x',
        srcFs: 'a:',
        srcLabel: 'a:',
        dstFs: 'b:',
        dstLabel: 'b:',
        schedule: daily,
      );
      expect(t.lastRun, isNull);
      expect(isDue(daily, now: DateTime.now(), lastRun: t.lastRun), isTrue);
    });

    test('it survives a JSON round trip as a backup', () {
      final t = buildBackupTask(
        id: '1',
        name: 'x',
        srcFs: 'a:',
        srcLabel: 'a:',
        dstFs: 'b:',
        dstLabel: 'b:',
        schedule: daily,
      );
      final back = TransferTask.fromJson(t.toJson());
      expect(back.kind, TaskKind.backup);
      expect(isBackupShaped(back.options), isTrue);
    });
  });
}
