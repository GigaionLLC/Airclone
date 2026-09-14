@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:airclone/src/update/install_appimage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replacing a running AppImage with a verified one.
///
/// These write real files and rename them, because that is the entire subject:
/// a test that mocked the filesystem would be testing its own mock. Skipped on
/// Windows, where there are no AppImages and no POSIX modes - the CI job that
/// matters for this file runs on Linux.
void main() {
  late Directory home;
  late File image;
  late File verified;

  setUp(() {
    home = Directory.systemTemp.createTempSync('airclone-appimage');
    image = File('${home.path}/Airclone-x86_64.AppImage')
      ..writeAsStringSync('the OLD image');
    verified = File('${home.path}/downloaded')
      ..writeAsStringSync('the NEW image');
  });

  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  // `?appimage` omits the entry when it is null - which is how a test says
  // "this process is not running from an AppImage".
  Map<String, String> env({String? appimage}) => {
    'HOME': home.path,
    'APPIMAGE': ?appimage,
  };

  group('finding the image', () {
    /// Inside an AppImage, Platform.resolvedExecutable points into an ephemeral
    /// /tmp/.mount_XXXX FUSE mount that vanishes on exit. APPIMAGE is the only
    /// path that means anything afterwards.
    test('is the APPIMAGE variable, and nothing else', () {
      expect(
        runningAppImagePath({'APPIMAGE': '/opt/a.AppImage'}),
        '/opt/a.AppImage',
      );
      expect(runningAppImagePath(const {}), isNull);
      expect(runningAppImagePath(const {'APPIMAGE': ''}), isNull);
    });
  });

  group('replacing it', () {
    test('the new image takes the old one\'s exact path', () async {
      final result = await installAppImage(
        verified: verified,
        environment: env(appimage: image.path),
      );
      expect(result.ok, isTrue, reason: result.detail);
      expect(image.readAsStringSync(), 'the NEW image');
      expect(result.imagePath, image.path);
    });

    /// Desktop integration writes an absolute Exec= into a .desktop file, so a
    /// renamed image strands the menu entry, the dock pin and every file
    /// association. The name is part of the contract.
    test('nothing else appears beside it but the backup', () async {
      await installAppImage(
        verified: verified,
        environment: env(appimage: image.path),
      );
      final names = home
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toSet();
      expect(names, contains('Airclone-x86_64.AppImage'));
      expect(names, contains('Airclone-x86_64.AppImage.old'));
      expect(names, isNot(contains('Airclone-x86_64.AppImage.new')));
    });

    /// Until the new image has started, the old one is the only way back.
    test('the previous version is kept, not deleted', () async {
      final result = await installAppImage(
        verified: verified,
        environment: env(appimage: image.path),
      );
      expect(File(result.backupPath!).readAsStringSync(), 'the OLD image');
    });

    test('an executable image stays executable', () async {
      await Process.run('chmod', ['755', image.path]);
      await installAppImage(
        verified: verified,
        environment: env(appimage: image.path),
      );
      final mode = image.statSync().mode & 0x1FF;
      expect(
        mode & 0x40,
        isNonZero,
        reason: 'the owner execute bit must survive the swap',
      );
    });

    /// A second update must not trip over the backup the first one left.
    test('a later update replaces the previous backup', () async {
      expect(
        (await installAppImage(
          verified: verified,
          environment: env(appimage: image.path),
        )).ok,
        isTrue,
      );
      verified.writeAsStringSync('the NEWEST image');
      expect(
        (await installAppImage(
          verified: verified,
          environment: env(appimage: image.path),
        )).ok,
        isTrue,
      );
      expect(image.readAsStringSync(), 'the NEWEST image');
      expect(
        File('${image.path}.old').readAsStringSync(),
        'the NEW image',
        reason: 'the backup should be the version just replaced',
      );
    });
  });

  group('refusing to', () {
    test('when this is not an AppImage at all', () async {
      final result = await installAppImage(
        verified: verified,
        environment: env(),
      );
      expect(result.outcome, AppImageInstall.notAnAppImage);
      expect(image.readAsStringSync(), 'the OLD image');
    });

    /// A package manager install, or an image on a read-only mount. The check
    /// is a real write, not a look at the permission bits: those say nothing
    /// about a read-only filesystem or a full disk.
    test('when the directory cannot be written to', () async {
      final locked = Directory('${home.path}/locked')..createSync();
      final lockedImage = File('${locked.path}/Airclone-x86_64.AppImage')
        ..writeAsStringSync('the OLD image');
      await Process.run('chmod', ['555', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['755', locked.path]));

      final result = await installAppImage(
        verified: verified,
        environment: env(appimage: lockedImage.path),
      );
      // Running as root defeats the permission, and CI sometimes does; the
      // point is that it never half-installs, whichever way it goes.
      if (result.outcome == AppImageInstall.notWritable) {
        expect(lockedImage.readAsStringSync(), 'the OLD image');
      } else {
        expect(result.ok, isTrue);
      }
    });
  });

  group('sweeping up', () {
    test('the backup goes on the next launch', () async {
      await installAppImage(
        verified: verified,
        environment: env(appimage: image.path),
      );
      expect(File('${image.path}.old').existsSync(), isTrue);
      sweepAppImageBackup(env(appimage: image.path));
      expect(File('${image.path}.old').existsSync(), isFalse);
      // And the image it swept around is untouched.
      expect(image.readAsStringSync(), 'the NEW image');
    });

    test('does nothing when there is no backup, or no AppImage', () {
      expect(
        () => sweepAppImageBackup(env(appimage: image.path)),
        returnsNormally,
      );
      expect(() => sweepAppImageBackup(env()), returnsNormally);
    });
  });
}
