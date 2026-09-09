import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/sync_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Set as sync source" here, "Sync to here" somewhere else later. The gesture's
/// hazard is the gap: in the two-pane flow both endpoints are on screen when you
/// commit, but a marked source was chosen minutes ago and possibly on another
/// remote — so an overlapping pair is now two clicks away, and a one-way sync
/// deletes whatever the source does not have.
void main() {
  group('SyncSource', () {
    const remote = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');

    test('nothing is marked by default', () {
      const s = SyncSource();
      expect(s.isSet, isFalse);
      expect(s.label, isEmpty);
      expect(s.fs, isEmpty);
    });

    test('assembles fs and label the way TransferService does', () {
      const s = SyncSource(remote: remote, path: 'Photos/2024');
      expect(s.fs, 'gdrive:Photos/2024');
      expect(s.label, 'gdrive:Photos/2024');
      expect(s.isSet, isTrue);
    });

    test("a remote's root marks cleanly", () {
      const s = SyncSource(remote: remote);
      expect(s.fs, 'gdrive:');
    });

    test('mark then clear', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(syncSourceProvider.notifier);
      ctrl.mark(remote, 'Photos');
      expect(container.read(syncSourceProvider).fs, 'gdrive:Photos');
      ctrl.clear();
      expect(container.read(syncSourceProvider).isSet, isFalse);
    });
  });

  group('syncTargetRefusal', () {
    test('allows an ordinary pair on two remotes', () {
      expect(
        syncTargetRefusal(srcFs: 'gdrive:Photos', dstFs: 's3:backup/photos'),
        isNull,
      );
    });

    test('allows siblings on the same remote', () {
      expect(syncTargetRefusal(srcFs: 'gdrive:a', dstFs: 'gdrive:b'), isNull);
    });

    test('refuses the same folder', () {
      expect(
        syncTargetRefusal(srcFs: 'gdrive:Photos', dstFs: 'gdrive:Photos'),
        isNotNull,
      );
    });

    test('a trailing slash is not a different folder', () {
      expect(
        syncTargetRefusal(srcFs: 'gdrive:Photos/', dstFs: 'gdrive:Photos'),
        isNotNull,
      );
    });

    test('nor is a different case', () {
      // A Windows local path reaches the same folder through either case. A
      // false refusal costs a rename; a missed overlap costs the data.
      expect(syncTargetRefusal(srcFs: 'C:/Data', dstFs: 'c:/data'), isNotNull);
    });

    test('nor is a backslash', () {
      expect(
        syncTargetRefusal(srcFs: r'C:\Data\Photos', dstFs: 'C:/Data/Photos'),
        isNotNull,
      );
    });

    test('refuses a destination inside the source', () {
      final why = syncTargetRefusal(
        srcFs: 'gdrive:Photos',
        dstFs: 'gdrive:Photos/2024',
      );
      expect(why, isNotNull);
      expect(why, contains('inside the source'));
    });

    test('refuses a source inside the destination', () {
      // The dangerous direction: the sync would delete every sibling of the
      // source, and the source is one of the things being deleted around.
      final why = syncTargetRefusal(
        srcFs: 'gdrive:Photos/2024',
        dstFs: 'gdrive:Photos',
      );
      expect(why, isNotNull);
      expect(why, contains('delete'));
    });

    test("a remote's root contains its folders, with no slash to look for", () {
      expect(
        syncTargetRefusal(srcFs: 'gdrive:', dstFs: 'gdrive:Photos'),
        isNotNull,
      );
      expect(
        syncTargetRefusal(srcFs: 'gdrive:Photos', dstFs: 'gdrive:'),
        isNotNull,
      );
    });

    test('a local root contains everything under it', () {
      expect(syncTargetRefusal(srcFs: 'C:/', dstFs: 'C:/Users'), isNotNull);
      expect(syncTargetRefusal(srcFs: 'C:/', dstFs: 'D:/Users'), isNull);
    });

    test('a shared name PREFIX is not containment', () {
      // The classic string-prefix bug: `Photos-old` starts with `Photos` but is
      // not inside it, and refusing here would block a perfectly ordinary
      // archive-into-a-sibling sync.
      expect(
        syncTargetRefusal(srcFs: 'gdrive:Photos', dstFs: 'gdrive:Photos-old'),
        isNull,
      );
      expect(syncTargetRefusal(srcFs: 'C:/data', dstFs: 'C:/data2'), isNull);
    });

    test('a remote whose NAME extends another is not inside it', () {
      expect(syncTargetRefusal(srcFs: 'gd:', dstFs: 'gdrive:Photos'), isNull);
    });

    test('refuses an empty endpoint', () {
      expect(syncTargetRefusal(srcFs: '', dstFs: 'gdrive:x'), isNotNull);
      expect(syncTargetRefusal(srcFs: 'gdrive:x', dstFs: ''), isNotNull);
    });
  });
}
