import 'package:airclone/src/state/bookmarks_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _b = Bookmark(
  name: 'gdrive',
  type: 'drive',
  fs: 'gdrive:',
  path: 'Work/Q1',
);

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('JSON round-trips every field', () {
    final j = _b.toJson();
    final back = Bookmark.fromJson(j);
    expect(back.name, _b.name);
    expect(back.type, _b.type);
    expect(back.fs, _b.fs);
    expect(back.path, _b.path);
    expect(back.isLocal, _b.isLocal);
    expect(back.key, _b.key);
  });

  test('label/remote derive correctly (root vs subfolder)', () {
    expect(_b.label, 'gdrive/Work/Q1');
    expect(_b.remote.fs, 'gdrive:');
    const root = Bookmark(name: 's3', type: 's3', fs: 's3:', path: '');
    expect(root.label, 's3');
  });

  test('add pins once; isPinned reflects it; remove unpins', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(bookmarksProvider.notifier);

    expect(ctrl.isPinned(_b.fs, _b.path), isFalse);
    ctrl.add(_b);
    expect(c.read(bookmarksProvider).length, 1);
    expect(ctrl.isPinned(_b.fs, _b.path), isTrue);

    // Pinning the same folder again is a no-op.
    ctrl.add(_b);
    expect(c.read(bookmarksProvider).length, 1);

    ctrl.remove(_b.fs, _b.path);
    expect(c.read(bookmarksProvider), isEmpty);
    expect(ctrl.isPinned(_b.fs, _b.path), isFalse);
  });

  test('newest pin is first', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctrl = c.read(bookmarksProvider.notifier);
    ctrl.add(_b);
    ctrl.add(
      const Bookmark(name: 's3', type: 's3', fs: 's3:', path: 'backup'),
    );
    expect(c.read(bookmarksProvider).first.name, 's3');
  });

  test('survives across containers (persisted)', () async {
    final c1 = ProviderContainer();
    c1.read(bookmarksProvider.notifier).add(_b);
    await _tick(); // let _persist flush to SharedPreferences
    c1.dispose();

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(bookmarksProvider); // triggers build() → _load()
    await _tick(); // let _load complete
    expect(
      c2.read(bookmarksProvider).map((b) => b.key),
      contains(_b.key),
    );
  });
}
