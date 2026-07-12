import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/cloud_placeholder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localAbsolutePath', () {
    test('cloud remote is never a local path', () {
      const gdrive = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');
      expect(localAbsolutePath(gdrive, 'Photos/a.jpg'), isNull);
    });

    test('synthetic local peer joins its absolute fs root', () {
      const disk = Remote(
        name: 'Disk (C:)',
        type: 'local',
        fs: 'C:/Users/x/Proton Drive/',
        isLocal: true,
      );
      expect(
        localAbsolutePath(disk, 'old-backups/2016.tar'),
        'C:/Users/x/Proton Drive/old-backups/2016.tar',
      );
    });

    test('joins with exactly one slash when the root lacks a trailing one', () {
      const disk = Remote(
        name: 'root',
        type: 'local',
        fs: '/mnt/data',
        isLocal: true,
      );
      expect(localAbsolutePath(disk, 'a/b.png'), '/mnt/data/a/b.png');
    });

    test('empty within resolves to the root itself', () {
      const disk = Remote(name: 'C', type: 'local', fs: 'C:/', isLocal: true);
      expect(localAbsolutePath(disk, ''), 'C:/');
    });

    test('named local conf remote resolves only an already-absolute path', () {
      // A remote parsed from rclone.conf: type=local, fs "name:", not synthetic.
      const named = Remote(name: 'localdisk', type: 'local', fs: 'localdisk:');
      expect(localAbsolutePath(named, 'C:/data/f.jpg'), 'C:/data/f.jpg');
      expect(localAbsolutePath(named, '/home/x/f.jpg'), '/home/x/f.jpg');
      expect(localAbsolutePath(named, 'relative/f.jpg'), isNull);
    });
  });

  group('fail-open safety', () {
    test('a non-existent / bogus path is never treated as online-only', () {
      // Windows: GetFileAttributesW returns INVALID → false. Elsewhere: no FFI
      // binding → false. Either way we must not wrongly hide a file.
      expect(isOnlineOnlyPlaceholder(''), isFalse);
      expect(
        isOnlineOnlyPlaceholder('Z:/no/such/path/9d1f2e/nope.bin'),
        isFalse,
      );
    });

    test('wouldHydrateOnRead is false for cloud remotes and unresolvable paths',
        () {
      const s3 = Remote(name: 's3', type: 's3', fs: 's3:');
      expect(wouldHydrateOnRead(s3, 'bucket/big.tar'), isFalse);
      const disk = Remote(
        name: 'C',
        type: 'local',
        fs: 'C:/definitely/missing/dir/',
        isLocal: true,
      );
      expect(wouldHydrateOnRead(disk, 'nope-4c1a.bin'), isFalse);
    });
  });
}
