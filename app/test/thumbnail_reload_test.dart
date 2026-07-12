import 'package:airclone/src/state/thumbnail_reload.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reload epoch drives every mounted `ThumbnailImage`: a bumped [tick] asks
/// tiles to re-attempt, and [force] tells them to bypass the on-disk cache.
/// These invariants are what keep "Reload" cheap (re-attempt only) and "Rebuild"
/// correct (always regenerate).
void main() {
  ProviderContainer make() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('starts at tick 0, not forcing', () {
    final c = make();
    final sig = c.read(thumbnailReloadProvider);
    expect(sig.tick, 0);
    expect(sig.force, isFalse);
  });

  test('reload() bumps the tick and is a soft (non-force) signal', () {
    final c = make();
    c.read(thumbnailReloadProvider.notifier).reload();
    final sig = c.read(thumbnailReloadProvider);
    expect(sig.tick, 1);
    expect(sig.force, isFalse);
  });

  test('rebuild() bumps the tick AND sets force (cache-bypass)', () {
    final c = make();
    c.read(thumbnailReloadProvider.notifier).rebuild();
    final sig = c.read(thumbnailReloadProvider);
    expect(sig.tick, 1);
    expect(sig.force, isTrue);
  });

  test('every reload advances the tick so tiles always see a change', () {
    final c = make();
    final n = c.read(thumbnailReloadProvider.notifier);
    n.reload();
    n.reload();
    n.rebuild();
    expect(c.read(thumbnailReloadProvider).tick, 3);
  });

  test('a soft reload after a rebuild clears force again', () {
    final c = make();
    final n = c.read(thumbnailReloadProvider.notifier);
    n.rebuild();
    expect(c.read(thumbnailReloadProvider).force, isTrue);
    n.reload();
    // A later soft reload must not keep forcing a cache-bypass on every tile.
    expect(c.read(thumbnailReloadProvider).force, isFalse);
    expect(c.read(thumbnailReloadProvider).tick, 2);
  });

  test(
    'prewarm([]) warms nothing and returns 0 without bumping the tick',
    () async {
      final c = make();
      final count = await c.read(thumbnailReloadProvider.notifier).prewarm([]);
      expect(count, 0);
      expect(c.read(thumbnailReloadProvider).tick, 0);
    },
  );
}
