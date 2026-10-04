import 'package:airclone/src/state/open_external.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Open in another app" used to download the whole file first, even when the
/// remote was already mounted and the file sat at a real path on this machine.
/// [mountedOsPath] finds that path (player format plan, 4.E). The second half
/// of these tests matters more than the first: the path is built from names a
/// remote supplies, and it must never be able to leave the mount.
void main() {
  MountInfo m(String point, String fs) => MountInfo(mountPoint: point, fs: fs);

  group('Windows drive letters', () {
    test('X: and X:\\ both join with a backslash', () {
      for (final point in ['X:', r'X:\']) {
        expect(
          mountedOsPath(
            mounts: [m(point, 'gdrive:')],
            fs: 'gdrive:',
            path: 'Films/Big Film.mkv',
            windows: true,
          ),
          r'X:\Films\Big Film.mkv',
          reason: point,
        );
      }
    });

    test('a backslash or a colon in a name refuses the path', () {
      for (final path in [r'Films\..\..\secret.txt', 'Films/C:evil.mkv']) {
        expect(
          mountedOsPath(
            mounts: [m('X:', 'gdrive:')],
            fs: 'gdrive:',
            path: path,
            windows: true,
          ),
          isNull,
          reason: path,
        );
      }
    });
  });

  group('Linux and macOS folders', () {
    test('a folder mount point, with or without a trailing slash', () {
      for (final point in [
        '/home/me/Airclone/gdrive',
        '/home/me/Airclone/gdrive/',
      ]) {
        expect(
          mountedOsPath(
            mounts: [m(point, 'gdrive:')],
            fs: 'gdrive:',
            path: 'Films/a.mkv',
            windows: false,
          ),
          '/home/me/Airclone/gdrive/Films/a.mkv',
        );
      }
    });

    test('a backslash is an ordinary character there', () {
      expect(
        mountedOsPath(
          mounts: [m('/mnt/g', 'gdrive:')],
          fs: 'gdrive:',
          path: r'odd\name.mkv',
          windows: false,
        ),
        r'/mnt/g/odd\name.mkv',
      );
    });
  });

  group('which mount', () {
    test('a sub-root mount serves the files under its root', () {
      expect(
        mountedOsPath(
          mounts: [m('/mnt/work', 'gdrive:work')],
          fs: 'gdrive:',
          path: 'work/reports/a.mkv',
          windows: false,
        ),
        '/mnt/work/reports/a.mkv',
      );
      expect(
        mountedOsPath(
          mounts: [m('/mnt/work', 'gdrive:work/')],
          fs: 'gdrive:',
          path: 'home/a.mkv',
          windows: false,
        ),
        isNull,
        reason: 'outside that root',
      );
    });

    test(
      'a remote rooted at a folder still matches the whole-remote mount',
      () {
        expect(
          mountedOsPath(
            mounts: [m('/mnt/g', 'gdrive:')],
            fs: 'gdrive:Films',
            path: 'a.mkv',
            windows: false,
          ),
          '/mnt/g/Films/a.mkv',
        );
      },
    );

    test('the deepest matching mount wins', () {
      expect(
        mountedOsPath(
          mounts: [m('/mnt/g', 'gdrive:'), m('/mnt/films', 'gdrive:Films')],
          fs: 'gdrive:',
          path: 'Films/a.mkv',
          windows: false,
        ),
        '/mnt/films/a.mkv',
      );
    });

    test('another remote, or no mounts, is no match', () {
      expect(
        mountedOsPath(
          mounts: [m('/mnt/o', 'onedrive:')],
          fs: 'gdrive:',
          path: 'a.mkv',
          windows: false,
        ),
        isNull,
      );
      expect(
        mountedOsPath(
          mounts: const [],
          fs: 'gdrive:',
          path: 'a.mkv',
          windows: false,
        ),
        isNull,
      );
    });

    test('a mount reported without a mount point or fs is ignored', () {
      expect(
        mountedOsPath(
          mounts: [m('', 'gdrive:'), m('/mnt/x', '')],
          fs: 'gdrive:',
          path: 'a.mkv',
          windows: false,
        ),
        isNull,
      );
    });
  });

  group('the path cannot leave the mount', () {
    for (final path in [
      '../etc/passwd',
      'Films/../../x',
      'a//b.mkv',
      './a.mkv',
      '',
    ]) {
      test('"$path" is refused, not cleaned up', () {
        expect(
          mountedOsPath(
            mounts: [m('/mnt/g', 'gdrive:')],
            fs: 'gdrive:',
            path: path,
            windows: false,
          ),
          isNull,
        );
      });
    }
  });
}
