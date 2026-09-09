import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/recent_locations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Remote _r(String name) =>
    Remote(name: name, type: 'drive', fs: '$name:', isLocal: false);

/// The trail is OFF by default (see recents_enabled_test.dart) — these cover the
/// list's own behaviour, so they switch it on.
class _Enabled extends RecentsEnabled {
  @override
  bool build() => true;
  @override
  Future<void> set(bool v) async => state = v;
}

ProviderContainer _enabledContainer() {
  final c = ProviderContainer(
    overrides: [recentsEnabledProvider.overrideWith(_Enabled.new)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('record pushes newest first and dedupes by fs+path', () {
    final c = _enabledContainer();
    final ctrl = c.read(recentLocationsProvider.notifier);

    ctrl.record(_r('a'), 'x');
    ctrl.record(_r('b'), 'y');
    ctrl.record(_r('a'), 'x'); // revisit a:x → moves to front, no duplicate

    final list = c.read(recentLocationsProvider);
    expect(list.length, 2);
    expect(list.first.label, 'a/x');
    expect(list[1].label, 'b/y');
  });

  test('root vs subfolder are distinct entries; label reflects path', () {
    final c = _enabledContainer();
    final ctrl = c.read(recentLocationsProvider.notifier);
    ctrl.record(_r('a'), '');
    ctrl.record(_r('a'), 'sub');
    final list = c.read(recentLocationsProvider);
    expect(list.map((l) => l.label), ['a/sub', 'a']);
  });

  test('caps at 12, dropping the oldest', () {
    final c = _enabledContainer();
    final ctrl = c.read(recentLocationsProvider.notifier);
    for (var i = 0; i < 15; i++) {
      ctrl.record(_r('r'), 'p$i');
    }
    final list = c.read(recentLocationsProvider);
    expect(list.length, 12);
    expect(list.first.path, 'p14'); // newest kept
    expect(list.any((l) => l.path == 'p0'), isFalse); // oldest dropped
  });
}
