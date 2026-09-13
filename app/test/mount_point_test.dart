import 'dart:io';

import 'package:airclone/src/state/mount_point.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mounting never worked on Linux or macOS through the app: the dialog offered
/// only "*" and drive letters, which rclone honours on Windows alone. Proven on
/// real Linux with the pinned rclone, through the same RC call the app makes -
/// "*" and "D:" both fail with "cannot open", an empty folder mounts. See the
/// mount-probe job in linux-runner.yml, which keeps proving it.
///
/// These pin the folder rules the fix depends on. The rules themselves come
/// from rclone's non-Windows getMountpoint: the path must exist, be a directory,
/// and be empty.
void main() {
  group('which kind of mount point', () {
    test('Windows mounts onto drive letters', () {
      expect(mountsOntoDriveLetters(windows: true), isTrue);
    });

    test('everything else mounts onto a folder', () {
      expect(mountsOntoDriveLetters(windows: false), isFalse);
    });

    /// The Web UI runs this dialog in a browser, which cannot know the host's
    /// OS or create a folder on it - prepareMountFolder would throw there. The
    /// first version of the folder fix missed this and gave the Web UI a folder
    /// field whose Mount button could only fail, breaking Web UI mounting from a
    /// Windows host that had worked before.
    test('the Web UI keeps drive letters, whatever the browser runs on', () {
      expect(mountsOntoDriveLetters(windows: false, web: true), isTrue);
      expect(mountsOntoDriveLetters(windows: true, web: true), isTrue);
    });
  });

  group('the default folder', () {
    test('lives under Airclone in the home directory', () {
      expect(
        defaultMountFolder(home: '/home/someone', fs: 'gdrive:'),
        '/home/someone/Airclone/gdrive',
      );
    });

    test('a trailing slash on home does not double up', () {
      expect(
        defaultMountFolder(home: '/home/someone/', fs: 'gdrive:'),
        '/home/someone/Airclone/gdrive',
      );
    });

    test('a remote subfolder becomes part of the name, not a nested path', () {
      expect(
        defaultMountFolder(home: '/Users/someone', fs: 'gdrive:work/2026'),
        '/Users/someone/Airclone/gdrive-work-2026',
      );
    });

    /// A default that lands somewhere the folder rules would refuse is a trap:
    /// the user clicks Mount without touching anything and gets an error.
    test('the default always passes the folder rules', () {
      for (final fs in ['gdrive:', 'my remote:', 'a:b/c', ':memory:', '---:']) {
        final path = defaultMountFolder(home: '/home/someone', fs: fs);
        expect(mountFolderProblem(path), isNull, reason: 'fs=$fs -> $path');
      }
    });
  });

  group('a folder-safe name', () {
    test('ordinary remotes keep their name', () {
      expect(mountFolderName('gdrive:'), 'gdrive');
      expect(mountFolderName('s3-backup:'), 's3-backup');
    });

    test('awkward characters become single dashes', () {
      expect(mountFolderName('my remote:'), 'my-remote');
      expect(mountFolderName('a:b/c'), 'a-b-c');
      expect(mountFolderName('x::y'), 'x-y');
    });

    test('never empty, never only punctuation', () {
      expect(mountFolderName(':'), 'remote');
      expect(mountFolderName('---:'), 'remote');
      expect(mountFolderName(''), 'remote');
    });

    test('never escapes its parent', () {
      for (final fs in ['..:', '../../etc:', 'a/../../b:']) {
        final name = mountFolderName(fs);
        expect(name, isNot(contains('/')), reason: fs);
        expect(name, isNot(startsWith('.')), reason: fs);
      }
    });
  });

  group('what cannot be a mount folder', () {
    test('an empty path, or a relative one', () {
      expect(mountFolderProblem(''), isNotNull);
      expect(mountFolderProblem('   '), isNotNull);
      expect(mountFolderProblem('Airclone/gdrive'), isNotNull);
      expect(mountFolderProblem('~/Airclone/gdrive'), isNotNull);
    });

    /// What the dialog used to send. Must never be accepted as a folder.
    test('the old Windows-only values', () {
      expect(mountFolderProblem('*'), isNotNull);
      expect(mountFolderProblem('D:'), isNotNull);
    });

    test('a path that climbs', () {
      expect(mountFolderProblem('/home/someone/../../etc'), isNotNull);
    });

    test('the root, and system or sandbox-private directories', () {
      expect(mountFolderProblem('/'), isNotNull);
      for (final p in [
        '/tmp/x',
        '/var/tmp/x',
        '/run/user/1000/doc/x',
        '/app/x',
        '/usr/local',
        '/etc',
        '/proc/1',
      ]) {
        expect(mountFolderProblem(p), isNotNull, reason: p);
      }
    });

    /// A prefix match must not catch a sibling that merely starts the same way.
    test('/tmp is refused, /tmpfiles-archive is not', () {
      expect(mountFolderProblem('/tmp'), isNotNull);
      expect(mountFolderProblem('/tmpfiles-archive/x'), isNull);
      expect(mountFolderProblem('/runner/x'), isNull);
    });

    test('ordinary places are fine', () {
      expect(mountFolderProblem('/home/someone/Airclone/gdrive'), isNull);
      expect(mountFolderProblem('/Users/someone/Drives/work'), isNull);
      expect(mountFolderProblem('/mnt/gdrive'), isNull);
      expect(mountFolderProblem('/Volumes/gdrive'), isNull);
    });
  });

  group('getting a folder ready', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('acl_mp'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// These call the filesystem half directly. An earlier version went through
    /// prepareMountFolder and skipped itself whenever the path rules refused the
    /// temp directory - which they do on every platform - so all four reported a
    /// pass having checked nothing.
    String inTmp(String rel) => '${tmp.path}${Platform.pathSeparator}$rel';

    /// rclone does not create the folder; the app has to, or every first mount
    /// fails with "failed to retrieve mount path information".
    test('a missing folder is created', () async {
      final p = inTmp('new${Platform.pathSeparator}nested');
      expect(Directory(p).existsSync(), isFalse);
      expect(await prepareMountFolderOnDisk(p), isNull);
      expect(Directory(p).existsSync(), isTrue);
    });

    test('an existing empty folder is accepted as it is', () async {
      final p = inTmp('empty');
      Directory(p).createSync();
      expect(await prepareMountFolderOnDisk(p), isNull);
    });

    test('a folder with something in it is refused, and left alone', () async {
      final p = inTmp('full');
      Directory(p).createSync();
      final keep = File('$p${Platform.pathSeparator}keep.txt')
        ..writeAsStringSync('mine');
      expect(await prepareMountFolderOnDisk(p), contains('not empty'));
      expect(keep.readAsStringSync(), 'mine');
    });

    test('a file where the folder should be is refused', () async {
      final p = inTmp('a-file');
      File(p).writeAsStringSync('x');
      expect(await prepareMountFolderOnDisk(p), contains('not a folder'));
    });

    /// The public entry point must apply the path rules BEFORE the disk half,
    /// or a refused path could still be created.
    test(
      'prepareMountFolder refuses by the rules before touching the disk',
      () async {
        expect(await prepareMountFolder('*'), isNotNull);
        expect(await prepareMountFolder('relative/path'), isNotNull);
        expect(Directory('relative/path').existsSync(), isFalse);
      },
    );
  });

  group('rclone errors, in words', () {
    test('missing FUSE on Linux says what to install', () {
      final msg = friendlyMountError(
        'failed to mount FUSE fs: fusermount: exec: "fusermount3": '
        'executable file not found in \$PATH',
        windows: false,
      );
      expect(msg, contains('FUSE is not installed'));
      expect(msg, contains('fuse3'));
    });

    test('a non-empty folder', () {
      expect(
        friendlyMountError(
          'failed to mount FUSE fs: directory not empty',
          windows: false,
        ),
        contains('not empty'),
      );
    });

    test('anything unrecognised is passed through, not guessed at', () {
      const raw = 'failed to mount FUSE fs: some brand new failure';
      expect(friendlyMountError(raw, windows: false), raw);
    });

    test('the FUSE hint is never shown on Windows', () {
      final msg = friendlyMountError('fusermount not found', windows: true);
      expect(msg, isNot(contains('apt install')));
    });
  });
}
