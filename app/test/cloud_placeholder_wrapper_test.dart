import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/cloud_placeholder.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `crypt` or `alias` remote can sit on a LOCAL path. Its type is then
/// "crypt"/"alias", never "local" — so the placeholder guard used to give up,
/// report "not a local path", and let the caller read the file. On a sync
/// folder (Proton Drive, OneDrive, iCloud) that silently downloads it in full.
///
/// The guard's whole purpose is to prevent exactly that, so the wrapper case
/// bypassing it inverted the feature.
void main() {
  group('resolveLocalBackingRoot', () {
    test('follows crypt -> alias -> a local path', () {
      final dump = <String, dynamic>{
        'secret': {'type': 'crypt', 'remote': 'stash:vault'},
        'stash': {'type': 'alias', 'remote': '/mnt/proton/My files'},
      };
      expect(
        resolveLocalBackingRoot('secret', dump),
        '/mnt/proton/My files/vault',
      );
    });

    test('a Windows drive letter is a path, not a remote called "C"', () {
      final dump = <String, dynamic>{
        'secret': {'type': 'crypt', 'remote': r'C:/Users/x/Proton Drive'},
      };
      // The colon at index 1 would otherwise split into remote "C", path "/...".
      expect(
        resolveLocalBackingRoot('secret', dump),
        r'C:/Users/x/Proton Drive',
      );
    });

    test('a crypt over a CLOUD backend resolves to null, not a path', () {
      final dump = <String, dynamic>{
        'secret': {'type': 'crypt', 'remote': 'gdrive:vault'},
        'gdrive': {'type': 'drive'},
      };
      expect(resolveLocalBackingRoot('secret', dump), isNull);
    });

    test('a cycle terminates instead of hanging', () {
      final dump = <String, dynamic>{
        'a': {'type': 'alias', 'remote': 'b:'},
        'b': {'type': 'alias', 'remote': 'a:'},
      };
      expect(resolveLocalBackingRoot('a', dump), isNull);
    });
  });

  group('isLocalBacked', () {
    const crypt = Remote(name: 'secret', type: 'crypt', fs: 'secret:');
    const union = Remote(name: 'pool', type: 'union', fs: 'pool:');

    test('true for a wrapper resolved onto local storage', () {
      setRemoteBackingRoots({'secret': '/mnt/proton'});
      expect(isLocalBacked(crypt), isTrue);
    });

    test('false for a wrapper resolved onto a cloud backend', () {
      setRemoteBackingRoots({'secret': null});
      expect(isLocalBacked(crypt), isFalse);
    });

    test('NULL — not false — when the remote was never resolved', () {
      // union/combine take a list of upstreams and are deliberately not
      // followed. Null must mean "unknown", so a tree-walking caller fails
      // closed; reporting false here is what downloads someone's drive.
      setRemoteBackingRoots({'secret': '/mnt/proton'});
      expect(isLocalBacked(union), isNull);
    });
  });

  group('localAbsolutePath', () {
    test('joins a wrapper path onto its resolved local root', () {
      setRemoteBackingRoots({'stash': '/mnt/proton/My files'});
      const alias = Remote(name: 'stash', type: 'alias', fs: 'stash:');
      expect(
        localAbsolutePath(alias, 'rclone/rclone.exe'),
        '/mnt/proton/My files/rclone/rclone.exe',
      );
    });

    test('still null for a genuine cloud remote', () {
      setRemoteBackingRoots({'gdrive': null});
      const cloud = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');
      expect(localAbsolutePath(cloud, 'a/b.txt'), isNull);
    });
  });
}
