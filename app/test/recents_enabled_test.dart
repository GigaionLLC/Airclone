import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/recent_locations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Home screen grew a "Recent" row nobody asked for, listing remote and
/// folder names on the first screen of the app where anyone glancing at the
/// window can read them. A history feature nobody opted into should be opt-in,
/// so the trail is now off unless it is switched on in Settings → Security.
const _gdrive = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');
const _s3 = Remote(name: 's3', type: 's3', fs: 's3:');

/// A container whose enabled-flag starts [on], without touching SharedPreferences.
ProviderContainer _container({required bool on}) {
  final c = ProviderContainer(
    overrides: [recentsEnabledProvider.overrideWith(() => _FixedFlag(on))],
  );
  addTearDown(c.dispose);
  return c;
}

class _FixedFlag extends RecentsEnabled {
  _FixedFlag(this._initial);
  final bool _initial;
  @override
  bool build() => _initial;
  @override
  Future<void> set(bool v) async => state = v;
}

void main() {
  test('nothing is recorded while the trail is off', () {
    final c = _container(on: false);
    c.read(recentLocationsProvider.notifier).record(_gdrive, 'Photos');
    expect(c.read(recentLocationsProvider), isEmpty);
  });

  test('recording works once it is switched on', () {
    final c = _container(on: true);
    c.read(recentLocationsProvider.notifier)
      ..record(_gdrive, 'Photos')
      ..record(_s3, 'backup');
    final trail = c.read(recentLocationsProvider);
    expect(trail.map((l) => l.label), ['s3/backup', 'gdrive/Photos']);
  });

  test('switching it off clears what was already collected', () {
    // Not just "stops adding": the trail the user has opted out of must leave
    // the Home screen now, not at the next restart.
    final c = _container(on: true);
    c.read(recentLocationsProvider.notifier).record(_gdrive, 'Photos');
    expect(c.read(recentLocationsProvider), isNotEmpty);
    c.read(recentsEnabledProvider.notifier).set(false);
    expect(c.read(recentLocationsProvider), isEmpty);
  });

  test('the default is off', () {
    // Read through a plain container: build() returns the private default and
    // only a stored preference can raise it.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(recentsEnabledProvider), isFalse);
  });
}
