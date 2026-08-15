import 'package:airclone/src/state/media_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The player's repeat button is a *remembered* preference, not per-file state:
/// set it once and the next preview still loops. That only holds if the value
/// round-trips through SharedPreferences.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer make() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('repeat is off until asked for', () {
    expect(make().read(repeatPlaybackProvider), isFalse);
  });

  test('toggle flips and persists', () async {
    final c = make();
    await c.read(repeatPlaybackProvider.notifier).toggle();
    expect(c.read(repeatPlaybackProvider), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('media_repeat'), isTrue);

    await c.read(repeatPlaybackProvider.notifier).toggle();
    expect(c.read(repeatPlaybackProvider), isFalse);
    expect(prefs.getBool('media_repeat'), isFalse);
  });

  test('setting the value it already has writes nothing new', () async {
    final c = make();
    await c.read(repeatPlaybackProvider.notifier).set(false);
    final prefs = await SharedPreferences.getInstance();
    // Never stored, because nothing changed.
    expect(prefs.getBool('media_repeat'), isNull);
  });

  test('a previous session that left repeat on is restored', () async {
    SharedPreferences.setMockInitialValues({'media_repeat': true});
    final c = make();
    c.read(repeatPlaybackProvider);
    await pumpEventQueue();
    expect(c.read(repeatPlaybackProvider), isTrue);
  });
}
