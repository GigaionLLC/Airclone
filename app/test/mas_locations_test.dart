import 'package:airclone/src/state/local_locations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Mac App Store build persists a security-scoped bookmark beside each
/// Location's path, because under the sandbox the path alone cannot be read
/// after a relaunch. These are the pure, platform-independent halves of that:
/// the serialisation must round-trip, and it must stay compatible with every
/// entry written before bookmarks existed.
void main() {
  group('LocalLocation bookmark serialisation', () {
    test('round-trips a bookmark through JSON', () {
      const b = 'Ym9va21hcmstYnl0ZXM=';
      final before = LocalLocation.fromJson({
        'name': 'Projects',
        'fs': '/Users/me/Projects/',
        'kind': 'folder',
        'bookmark': b,
      });
      expect(before.bookmark, b);
      expect(LocalLocation.fromJson(before.toJson()).bookmark, b);
    });

    test('an entry written before bookmarks existed still loads', () {
      // The whole existing user base has entries in exactly this shape; a
      // stricter parse would wipe somebody's sidebar on upgrade.
      final legacy = LocalLocation.fromJson({
        'name': 'Docs',
        'fs': '/Users/me/Docs/',
        'kind': 'documents',
        // no 'bookmark' key at all
      });
      expect(legacy.bookmark, isNull);
      expect(legacy.remote.fs, '/Users/me/Docs/');
      expect(legacy.kind, LocalKind.documents);
    });

    test('omits the key entirely when there is no bookmark', () {
      // Non-MAS platforms must not start writing a null field into everyone's
      // preferences.
      final json = LocalLocation.fromJson({
        'name': 'D',
        'fs': '/d/',
        'kind': 'folder',
      }).toJson();
      expect(json.containsKey('bookmark'), isFalse);
    });

    test('copyWith attaches a bookmark without disturbing the rest', () {
      final loc = LocalLocation.fromJson({
        'name': 'Pics',
        'fs': '/p/',
        'kind': 'pictures',
      });
      final withB = loc.copyWith(bookmark: 'abc');
      expect(withB.bookmark, 'abc');
      expect(withB.remote.fs, '/p/');
      expect(withB.kind, LocalKind.pictures);
    });
  });

  group('iOS local storage (buildIosUserFolders)', () {
    test('seeds exactly the container Documents directory', () {
      final out = buildIosUserFolders(
        '/var/mobile/Containers/Data/App/X/Documents',
      );
      expect(out, hasLength(1));
      expect(
        out.single.remote.fs,
        '/var/mobile/Containers/Data/App/X/Documents/',
      );
      expect(out.single.remote.isLocal, isTrue);
      expect(out.single.kind, LocalKind.documents);
    });

    test('seeds nothing when the root has not been resolved', () {
      // An empty Locations list is the honest state; a row pointing at "" would
      // render fine and fail on every open.
      expect(buildIosUserFolders(''), isEmpty);
    });

    test('never seeds the container root, only Documents', () {
      // The whole point: "Home" at the container root would expose Library/ and
      // tmp/, which are app plumbing.
      final out = buildIosUserFolders('/c/Documents');
      expect(
        out.map((l) => l.remote.fs),
        everyElement(contains('/Documents/')),
      );
    });
  });
}
