/// A reap marker only says "this PID was our engine once".
///
/// After a crash the PID can be recycled by anything the user runs next
/// (Windows does not clear %TEMP% on reboot), and on Linux the markers used to
/// sit in the shared /tmp, where any other account could plant one naming one
/// of this user's processes. So before killing, the reaper asks whether the
/// process is still an `rclone rcd` of ours. These pin that question.
library;

import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

void main() {
  group('argvLooksLikeOurRcd', () {
    test('the argv this package spawns is ours', () {
      expect(
        argvLooksLikeOurRcd([
          '/opt/airclone/rclone',
          'rcd',
          '--rc-addr',
          '127.0.0.1:43123',
          '--rc-user',
          'airclone',
          '--rc-serve',
        ], tag: 'airclone'),
        isTrue,
      );
    });

    test('with user engine flags before our own', () {
      expect(
        argvLooksLikeOurRcd([
          r'C:\Program Files\Airclone\rclone.exe',
          'rcd',
          '--transfers',
          '8',
          '--rc-user=airclone',
        ], tag: 'airclone'),
        isTrue,
      );
    });

    test('a binary path with spaces, as ps splits it, still matches', () {
      expect(
        argvLooksLikeOurRcd(
          '/Users/me/My Apps/Airclone.app/Contents/MacOS/rclone rcd --rc-user airclone'
              .split(' '),
          tag: 'airclone',
        ),
        isTrue,
      );
    });

    test('an editor, an agent or a shell is never ours', () {
      for (final argv in [
        ['/usr/bin/vim', 'notes.txt'],
        ['gpg-agent', '--daemon'],
        ['/bin/bash'],
        <String>[],
      ]) {
        expect(
          argvLooksLikeOurRcd(argv, tag: 'airclone'),
          isFalse,
          reason: argv.join(' '),
        );
      }
    });

    test('rclone doing something other than rcd is not ours', () {
      expect(
        argvLooksLikeOurRcd([
          'rclone',
          'mount',
          'gd:',
          '/mnt',
        ], tag: 'airclone'),
        isFalse,
      );
    });

    test("another app's rcd, by its --rc-user, is not ours", () {
      expect(
        argvLooksLikeOurRcd([
          'rclone',
          'rcd',
          '--rc-user',
          'someone-else',
        ], tag: 'airclone'),
        isFalse,
      );
    });
  });

  group('windowsTasklistLooksLikeRclone', () {
    test('an rclone image with that PID is', () {
      expect(
        windowsTasklistLooksLikeRclone(
          '"rclone.exe","9001","Console","1","52,000 K"\r\n',
          9001,
        ),
        isTrue,
      );
    });

    test('a recycled PID now held by something else is not', () {
      expect(
        windowsTasklistLooksLikeRclone(
          '"notepad.exe","9001","Console","1","12,000 K"\r\n',
          9001,
        ),
        isFalse,
      );
    });

    test('no such process is not', () {
      expect(
        windowsTasklistLooksLikeRclone(
          'INFO: No tasks are running which match the specified criteria.\r\n',
          9001,
        ),
        isFalse,
      );
    });
  });

  group('looksLikeOurRcd, live', () {
    test('this test process is not an rclone rcd', () async {
      expect(await looksLikeOurRcd(pid, tag: 'airclone'), isFalse);
    });

    test('a PID that cannot exist is not ours', () async {
      expect(await looksLikeOurRcd(0, tag: 'airclone'), isFalse);
      expect(await looksLikeOurRcd(-1, tag: 'airclone'), isFalse);
    });
  });

  group('reapMarkerDir', () {
    test('Linux uses the per-user runtime dir when there is one', () {
      final tmp = Directory.systemTemp.createTempSync('xdg');
      addTearDown(() => tmp.deleteSync(recursive: true));
      expect(
        reapMarkerDir(
          environment: {'XDG_RUNTIME_DIR': tmp.path},
          isLinux: true,
        ).path,
        tmp.path,
      );
    });

    test('and falls back to the temp dir when it has none', () {
      expect(
        reapMarkerDir(environment: const {}, isLinux: true).path,
        Directory.systemTemp.path,
      );
      expect(
        reapMarkerDir(
          environment: const {'XDG_RUNTIME_DIR': '/nonexistent/airclone'},
          isLinux: true,
        ).path,
        Directory.systemTemp.path,
      );
    });

    test('other systems keep their (already per-user) temp dir', () {
      expect(
        reapMarkerDir(
          environment: const {'XDG_RUNTIME_DIR': '/run/user/1000'},
          isLinux: false,
        ).path,
        Directory.systemTemp.path,
      );
    });
  });

  /// The reaper hands each marker's PID to `kill`; production wraps the real
  /// kill in looksLikeOurRcd. A marker naming something else is cleared and
  /// its process left alone, and a genuine orphan in the same run still dies.
  test(
    'a verifying kill spares a stranger and still reaps an orphan',
    () async {
      final tmp = await Directory.systemTemp.createTemp('airclone_reap_id');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } on FileSystemException {
          // Windows keeps a handle on a still-locked file.
        }
      });
      final sep = Platform.pathSeparator;
      File('${tmp.path}${sep}airclone_rcd_1111.pid').writeAsStringSync('9001');
      File('${tmp.path}${sep}airclone_rcd_2222.pid').writeAsStringSync('9002');
      const ours = {9002};
      final killed = <int>[];

      final lock = await reapOrphanedRcd(
        tag: 'airclone',
        tempDir: tmp,
        lockFile: File('${tmp.path}${sep}airclone_rcd.lock'),
        ownPid: 4242,
        kill: (p) async {
          if (ours.contains(p)) killed.add(p);
        },
      );

      expect(killed, [9002]);
      expect(
        tmp.listSync().whereType<File>().where((f) => f.path.endsWith('.pid')),
        isEmpty,
        reason: 'both markers are stale either way, so both are cleared',
      );
      lock!
        ..unlockSync()
        ..closeSync();
    },
  );
}
