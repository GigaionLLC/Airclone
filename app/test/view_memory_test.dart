import 'package:airclone/src/state/view_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ViewPref survives a JSON round-trip', () {
    const pref = ViewPref(
      viewMode: 'grid',
      sortKey: 'modified',
      ascending: false,
      gridSize: 140,
    );
    final restored = ViewPref.fromJson(pref.toJson());
    expect(restored.viewMode, 'grid');
    expect(restored.sortKey, 'modified');
    expect(restored.ascending, false);
    expect(restored.gridSize, 140);
  });

  test('ViewPref.fromJson tolerates a malformed/partial map', () {
    final p = ViewPref.fromJson(const {'viewMode': 'media'});
    expect(p.viewMode, 'media');
    expect(p.sortKey, 'name'); // default
    expect(p.ascending, true); // default
    expect(p.gridSize, 112); // default
  });

  test('remember stores a pref; prefFor reads it back', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final mem = c.read(viewMemoryProvider.notifier);

    expect(mem.prefFor('gdrive'), isNull);
    const pref = ViewPref(
      viewMode: 'grid',
      sortKey: 'size',
      ascending: true,
      gridSize: 100,
    );
    mem.remember('gdrive', pref);
    expect(mem.prefFor('gdrive')?.viewMode, 'grid');
    expect(mem.prefFor('gdrive')?.sortKey, 'size');
  });

  test('remember of an identical pref does not replace the map', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final mem = c.read(viewMemoryProvider.notifier);

    const pref = ViewPref(
      viewMode: 'list',
      sortKey: 'name',
      ascending: true,
      gridSize: 112,
    );
    mem.remember('s3', pref);
    final after = c.read(viewMemoryProvider);
    mem.remember('s3', pref); // identical → no-op
    expect(identical(after, c.read(viewMemoryProvider)), isTrue);
  });
}
