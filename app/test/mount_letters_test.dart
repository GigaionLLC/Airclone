import 'package:airclone/src/state/mount_letters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// rclone's `*` takes the next free letter, which is right for a one-off and
/// wrong for a drive you have shortcuts and muscle memory pointed at: mount two
/// remotes in a different order and yesterday's K: is today's L:.
void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('nothing is pinned until something is', () {
    final c = container();
    expect(c.read(mountLettersProvider.notifier).forFs('gdrive:'), isNull);
  });

  test('a pin comes back for the same fs', () async {
    final c = container();
    final letters = c.read(mountLettersProvider.notifier);
    await letters.remember('gdrive:', 'K:');
    expect(letters.forFs('gdrive:'), 'K:');
  });

  test('two folders of one remote hold different letters', () async {
    // Keyed by the full fs, not the remote name, so these do not fight over one
    // letter.
    final c = container();
    final letters = c.read(mountLettersProvider.notifier);
    await letters.remember('gdrive:', 'K:');
    await letters.remember('gdrive:work', 'W:');
    expect(letters.forFs('gdrive:'), 'K:');
    expect(letters.forFs('gdrive:work'), 'W:');
  });

  test('unpinning removes it rather than leaving a stale letter', () async {
    final c = container();
    final letters = c.read(mountLettersProvider.notifier);
    await letters.remember('gdrive:', 'K:');
    await letters.forget('gdrive:');
    expect(letters.forFs('gdrive:'), isNull);
  });

  test('auto is the absence of a pin, so it clears one', () async {
    // Keeps the checkbox's two states symmetric: re-mounting on Auto with the
    // box ticked must not silently keep yesterday's letter pinned.
    final c = container();
    final letters = c.read(mountLettersProvider.notifier);
    await letters.remember('gdrive:', 'K:');
    await letters.remember('gdrive:', '*');
    expect(letters.forFs('gdrive:'), isNull);
  });

  test('an empty mount point is not a pin either', () async {
    final c = container();
    final letters = c.read(mountLettersProvider.notifier);
    await letters.remember('gdrive:', '');
    expect(letters.forFs('gdrive:'), isNull);
  });

  test('re-pinning to a new letter replaces the old one', () async {
    final c = container();
    final letters = c.read(mountLettersProvider.notifier);
    await letters.remember('gdrive:', 'K:');
    await letters.remember('gdrive:', 'M:');
    expect(letters.forFs('gdrive:'), 'M:');
    expect(c.read(mountLettersProvider), {'gdrive:': 'M:'});
  });
}
