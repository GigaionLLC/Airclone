import 'package:airclone/src/state/photo_backup.dart';
import 'package:airclone/src/state/task_kind.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// A photo backup is a `TaskKind.photos` task whose source folders are rclone
/// filter rules. These pin the parts that would fail silently on a phone at
/// 3am: rule ORDER (videos must be excluded before a folder is included, or
/// the include wins and the toggle does nothing), the trailing `- **` (without
/// it a `--filter` list copies the whole phone), and the copy-only shape.
void main() {
  group('buildPhotoFilterRules', () {
    test(
      'video excludes come BEFORE folder includes, then everything else out',
      () {
        final rules = buildPhotoFilterRules(
          folders: ['DCIM', 'Pictures/Screenshots'],
          includeVideos: false,
        );
        final firstInclude = rules.indexWhere((r) => r.startsWith('+ '));
        final lastVideoExclude = rules.lastIndexOf('- *.MP4');
        expect(lastVideoExclude, greaterThanOrEqualTo(0));
        expect(
          lastVideoExclude,
          lessThan(firstInclude),
          reason:
              'rclone takes the first matching rule; an include ahead of the '
              'video exclude would carry every .mp4 along regardless of the '
              'toggle',
        );
        expect(rules.last, '- **', reason: 'no implicit exclude for --filter');
        expect(rules, contains('+ /DCIM/**'));
        expect(rules, contains('+ /Pictures/Screenshots/**'));
      },
    );

    test('with videos on there are no video rules at all', () {
      final rules = buildPhotoFilterRules(
        folders: ['DCIM'],
        includeVideos: true,
      );
      expect(rules, ['+ /DCIM/**', '- **']);
    });

    test('video rules cover both cases, because cameras disagree', () {
      final rules = videoExcludeRules();
      expect(rules, contains('- *.mp4'));
      expect(rules, contains('- *.MP4'));
      expect(rules, contains('- *.mov'));
      expect(rules, contains('- *.MOV'));
    });

    test('glob-special characters in a folder name are escaped', () {
      expect(photoFolderRule('My [old] photos'), r'+ /My \[old\] photos/**');
      expect(photoFolderRule('a*b'), r'+ /a\*b/**');
    });

    test('folder rules round-trip through the parser, escapes included', () {
      for (final f in ['DCIM', 'Pictures/Screenshots', 'My [old] photos*']) {
        expect(photoFolderOfRule(photoFolderRule(f)), f);
      }
      expect(photoFolderOfRule('- *.mp4'), isNull);
      expect(photoFolderOfRule('- **'), isNull);
    });
  });

  group('relativePhotoFolder', () {
    const root = '/storage/emulated/0';
    test('a folder inside the root is made relative', () {
      expect(relativePhotoFolder('$root/DCIM', root), 'DCIM');
      expect(relativePhotoFolder('$root/DCIM/', root), 'DCIM');
      expect(
        relativePhotoFolder('$root/Pictures/Screenshots/', '$root/'),
        'Pictures/Screenshots',
      );
    });

    test('the root itself, another volume, or a climbing path is refused', () {
      expect(relativePhotoFolder(root, root), isNull);
      expect(relativePhotoFolder('$root/', root), isNull);
      expect(relativePhotoFolder('/storage/1234-5678/DCIM', root), isNull);
      expect(relativePhotoFolder('$root/DCIM/../Download', root), isNull);
      // A sibling whose name merely starts with the root is not inside it.
      // (A long suffix on purpose: a one-character sibling would slip past a
      // missing slash check by landing exactly on the substring boundary.)
      expect(relativePhotoFolder('/storage/emulated/0-old/DCIM', root), isNull);
    });
  });

  group('photoBackupDestination', () {
    test(
      'is remote:<path>/Airclone/Photos/<device> with the device sanitised',
      () {
        expect(
          photoBackupDestination(
            remoteFs: 'gdrive:',
            path: '',
            deviceName: 'Pixel 7',
          ),
          'gdrive:Airclone/Photos/Pixel 7',
        );
        expect(
          photoBackupDestination(
            remoteFs: 'gdrive:',
            path: '/Backups/',
            deviceName: 'Jake\'s: phone/2',
          ),
          'gdrive:Backups/Airclone/Photos/${deviceFolderName('Jake\'s: phone/2')}',
        );
        expect(
          photoBackupDestination(
            remoteFs: 'gdrive:',
            path: '',
            deviceName: '///',
          ),
          'gdrive:Airclone/Photos/device',
        );
      },
    );
  });

  group('buildPhotoBackupTask', () {
    final task = buildPhotoBackupTask(
      storageRoot: '/storage/emulated/0',
      spec: const PhotoBackupSpec(
        folders: ['DCIM', 'Pictures/Screenshots'],
        includeVideos: false,
      ),
      dstFs: 'gdrive:Airclone/Photos/Pixel 7',
    );

    test('is a photos task, copy-only, versions kept, background-enabled', () {
      expect(task.kind, TaskKind.photos);
      expect(task.options.mode, TransferMode.copy);
      expect(isBackupShaped(task.options), isTrue);
      expect(task.runWhileClosed, isTrue);
      expect(task.schedule, kPhotoBackupDefaultSchedule);
      expect(task.srcFs, '/storage/emulated/0/');
      expect(task.dstFs, 'gdrive:Airclone/Photos/Pixel 7');
    });

    test('the spec reads back out of the task', () {
      final spec = photoBackupSpecOf(task)!;
      expect(spec.folders, ['DCIM', 'Pictures/Screenshots']);
      expect(spec.includeVideos, isFalse);
      final withVideos = buildPhotoBackupTask(
        storageRoot: '/storage/emulated/0',
        spec: const PhotoBackupSpec(folders: ['DCIM'], includeVideos: true),
        dstFs: 'gdrive:Airclone/Photos/x',
      );
      expect(photoBackupSpecOf(withVideos)!.includeVideos, isTrue);
    });

    test('re-saving keeps the id, lastRun and history', () {
      final when = DateTime(2026, 9, 9, 3);
      final again = buildPhotoBackupTask(
        id: task.id,
        storageRoot: '/storage/emulated/0',
        spec: const PhotoBackupSpec(folders: ['DCIM'], includeVideos: true),
        dstFs: task.dstFs,
        schedule: const TaskSchedule(
          kind: ScheduleKind.interval,
          intervalMinutes: 60,
        ),
        lastRun: when,
        history: [TaskRunRecord(at: when, ok: true)],
      );
      expect(again.id, task.id);
      expect(again.lastRun, when);
      expect(again.history, hasLength(1));
      expect(again.schedule!.intervalMinutes, 60);
    });

    test('a non-photos task has no spec', () {
      expect(photoBackupSpecOf(task.copyWith(kind: TaskKind.backup)), isNull);
    });

    test('survives a JSON round-trip byte-for-byte', () {
      final back = TransferTask.fromJson(task.toJson());
      expect(back.kind, TaskKind.photos);
      expect(back.options.filters, task.options.filters);
      expect(photoBackupSpecOf(back), photoBackupSpecOf(task));
    });
  });

  test('describePhotoSources', () {
    expect(describePhotoSources(['DCIM']), 'Camera roll');
    expect(
      describePhotoSources(['DCIM', 'Pictures/Screenshots']),
      'Camera roll + 1 folder',
    );
    expect(describePhotoSources(['DCIM', 'a', 'b']), 'Camera roll + 2 folders');
    expect(describePhotoSources(['a']), '1 folder');
    expect(describePhotoSources([]), 'No folders');
  });
}
