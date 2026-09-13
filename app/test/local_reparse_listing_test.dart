import 'package:airclone/src/rclone/models/remote.dart';
import 'package:flutter_test/flutter_test.dart';

/// A user on Windows reported that Airclone did not show their OneDrive folder,
/// while Explorer showed it in the same directory.
///
/// It was not Airclone filtering it. rclone's local backend treats a reparse
/// point as a symlink and skips it, so the folder never arrived in the listing
/// at all — no error, no warning, nothing to click. Checking the reporter's own
/// machine against rclone 1.75.1 directly:
///
/// ```
/// rclone lsjson C:/Users/<user> --dirs-only        ->  83 entries, no OneDrive
/// rclone lsjson C:/Users/<user> --dirs-only -L     ->  97 entries, OneDrive present
/// ```
///
/// The four that were missing were `OneDrive`, `iCloudDrive`, and — because
/// OneDrive's Known Folder Move redirects them — `Desktop` and `Music`. A file
/// manager that cannot show you your own Desktop is the severe version of this
/// bug, and it is the DEFAULT state of a stock Windows install with OneDrive on.
///
/// [listFsFor] is the fix: `copy_links` on the listing call. These tests pin the
/// fs strings it builds, because the shapes are fiddly and one of them is a trap
/// (see the drive-letter case).
void main() {
  group('a local location is listed with copy_links', () {
    test('a synthetic drive peer uses the anonymous-backend form', () {
      expect(
        listFsFor(fs: 'C:/', type: 'local', isLocal: true),
        ':local,copy_links=true:C:/',
      );
    });

    test('a POSIX root too', () {
      expect(
        listFsFor(fs: '/', type: 'local', isLocal: true),
        ':local,copy_links=true:/',
      );
    });

    test('a CONFIGURED local remote takes the parameter before its colon', () {
      expect(
        listFsFor(fs: 'localdisk:', type: 'local', isLocal: false),
        'localdisk,copy_links=true:',
      );
    });

    test('a configured local remote rooted at a path keeps the path', () {
      expect(
        listFsFor(fs: 'localdisk:media', type: 'local', isLocal: false),
        'localdisk,copy_links=true:media',
      );
    });
  });

  group('it does not touch anything else', () {
    test('a cloud remote is passed through untouched', () {
      expect(
        listFsFor(fs: 'gdrive:', type: 'drive', isLocal: false),
        'gdrive:',
      );
      expect(
        listFsFor(fs: 's3:bucket/key', type: 's3', isLocal: false),
        's3:bucket/key',
      );
    });

    test('a crypt over local is still not a local backend', () {
      expect(
        listFsFor(fs: 'secret:', type: 'crypt', isLocal: false),
        'secret:',
      );
    });

    test('applying it twice changes nothing the second time', () {
      final once = listFsFor(fs: 'C:/', type: 'local', isLocal: true);
      final twice = listFsFor(fs: once, type: 'local', isLocal: true);
      expect(twice, once);
    });
  });

  /// The trap. A synthetic peer's fs is a PATH, not `name:`, so the
  /// configured-remote branch would read `C` as a remote name and emit
  /// `C,copy_links=true:/` — a remote that does not exist, which fails the
  /// listing outright rather than merely missing a folder. Worse than the bug.
  test('a drive letter is never mistaken for a remote name', () {
    for (final root in ['C:/', 'D:/', 'Z:/']) {
      final out = listFsFor(fs: root, type: 'local', isLocal: true);
      expect(out, startsWith(':local,'), reason: root);
      expect(out, endsWith(root), reason: root);
      expect(out, isNot(contains('${root[0]},')), reason: root);
    }
  });

  group('Remote.listParams uses it', () {
    test('a local pane lists through copy_links', () {
      const r = Remote(name: 'Home', type: 'local', fs: 'C:/', isLocal: true);
      final p = r.listParams('Users/someone');
      expect(p['fs'], ':local,copy_links=true:C:/');
      expect(p['remote'], 'Users/someone');
    });

    test('a cloud pane is unaffected', () {
      const r = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');
      final p = r.listParams('Work/Q1');
      expect(p['fs'], 'gdrive:');
      expect(p['remote'], 'Work/Q1');
    });

    /// The fs used for a listing is deliberately NOT the one the rest of the
    /// app shows or compares on: a connection string must never reach "Copy
    /// path", the console, or remote equality.
    test('the remote itself still reports its plain fs', () {
      const r = Remote(name: 'Home', type: 'local', fs: 'C:/', isLocal: true);
      expect(r.fs, 'C:/');
      expect(r.listParams('')['fs'], isNot('C:/'));
    });
  });
}
