import 'dart:io';

import 'package:airclone/src/update/install_windows.dart';
import 'package:flutter_test/flutter_test.dart';

/// Handing a verified update to the Windows installer.
///
/// The flags are asserted rather than described because each one is there for a
/// reason a user would feel: a progress window that steals focus, a message box
/// nobody is there to answer, or - worst - a reboot.
void main() {
  group('the flags', () {
    test('are silent, quiet, and never reboot the machine', () {
      final args = innoSilentArgs();
      expect(args, contains('/VERYSILENT'));
      expect(args, contains('/SUPPRESSMSGBOXES'));
      expect(
        args,
        contains('/NORESTART'),
        reason: 'a file manager updating itself must never reboot a machine',
      );
    });

    /// The app exits on its own, but a pop-out window or a stuck process must
    /// not block the install - and the user should end where they started.
    test('close what is running, and start it again afterwards', () {
      final args = innoSilentArgs();
      expect(args, contains('/CLOSEAPPLICATIONS'));
      expect(args, contains('/RESTARTAPPLICATIONS'));
    });

    /// Nothing is on screen during a silent install, so the log is the only
    /// place to look when one goes wrong.
    test('write a log when asked, and not when not', () {
      expect(
        innoSilentArgs(logPath: r'C:\temp\u.log'),
        contains(r'/LOG=C:\temp\u.log'),
      );
      expect(innoSilentArgs().any((a) => a.startsWith('/LOG=')), isFalse);
    });

    /// Inno takes `/FLAG` - a Unix-style flag would be treated as a file name
    /// and the install would go interactive, on a machine nobody is watching.
    test('are all Windows-style switches', () {
      for (final arg in innoSilentArgs(logPath: 'x')) {
        expect(arg.startsWith('/'), isTrue, reason: arg);
      }
    });
  });

  group('what it agrees to run', () {
    /// Verification upstream proves the file came from this project. This
    /// proves it is the INSTALLER and not the zip, the AppImage or the APK -
    /// because the alternative is executing whatever was downloaded.
    test('only the setup executable', () {
      expect(isWindowsInstaller('airclone-setup-x64.exe'), isTrue);
      expect(isWindowsInstaller(r'C:\Users\x\airclone-setup-x64.exe'), isTrue);
      expect(isWindowsInstaller('AIRCLONE-SETUP-X64.EXE'), isTrue);

      expect(isWindowsInstaller('airclone-windows-x64.zip'), isFalse);
      expect(isWindowsInstaller('Airclone-x86_64.AppImage'), isFalse);
      expect(isWindowsInstaller('airclone.msix'), isFalse);
      expect(isWindowsInstaller('setup-x64.exe.txt'), isFalse);
      expect(isWindowsInstaller(''), isFalse);
    });
  });

  group('refusing', () {
    test('a file that is not the installer', () async {
      final dir = Directory.systemTemp.createTempSync('airclone-win-install');
      addTearDown(() => dir.deleteSync(recursive: true));
      final zip = File('${dir.path}/airclone-windows-x64.zip')
        ..writeAsStringSync('not an installer');
      final result = await runWindowsInstaller(verified: zip);
      expect(result.outcome, WindowsInstallOutcome.notAnInstaller);
    });

    test('an installer that is no longer there', () async {
      final dir = Directory.systemTemp.createTempSync('airclone-win-install');
      addTearDown(() => dir.deleteSync(recursive: true));
      final missing = File('${dir.path}/airclone-setup-x64.exe');
      final result = await runWindowsInstaller(verified: missing);
      expect(result.outcome, WindowsInstallOutcome.failed);
      expect(result.detail, contains('not where it was left'));
    });
  });
}
