import 'package:airclone/src/rclone/models/mount_info.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/mount_controller.dart';
import 'package:airclone/src/state/mount_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

class _CapturingClient implements RcloneClient {
  final calls = <({String method, Map<String, dynamic>? params})>[];
  Map<String, dynamic> Function(String, Map<String, dynamic>?)? onRpc;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    return onRpc?.call(method, params) ?? <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._client);
  final RcloneClient _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);
}

ProviderContainer _container(_CapturingClient client, {bool policy = true}) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      if (!policy) mountEnabledProvider.overrideWithValue(false),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('MountInfo.fromList', () {
    test('parses an object entry (MountPoint + Fs)', () {
      final m = MountInfo.fromList({'MountPoint': 'X:', 'Fs': 'gdrive:'});
      expect(m.mountPoint, 'X:');
      expect(m.fs, 'gdrive:');
    });
    test('parses a bare string entry', () {
      expect(MountInfo.fromList('Z:').mountPoint, 'Z:');
    });
    test('tolerates junk', () {
      expect(MountInfo.fromList(42).mountPoint, '');
    });
  });

  test('cacheModeValue maps modes to rclone numbers', () {
    expect(cacheModeValue('off'), 0);
    expect(cacheModeValue('minimal'), 1);
    expect(cacheModeValue('writes'), 2);
    expect(cacheModeValue('full'), 3);
    expect(cacheModeValue('???'), 2); // default writes
  });

  test(
    'mount sends fs/mountPoint + numeric CacheMode; returns actual point',
    () async {
      final client = _CapturingClient()
        ..onRpc = (m, _) =>
            m == 'mount/mount' ? {'mountPoint': 'Y:'} : <String, dynamic>{};
      final c = _container(client);
      final point = await c
          .read(mountControllerProvider.notifier)
          .mount(fs: 'gdrive:Photos', mountPoint: '*', cacheMode: 'full');
      expect(point, 'Y:');
      final call = client.calls.firstWhere((c) => c.method == 'mount/mount');
      expect(call.params!['fs'], 'gdrive:Photos');
      expect(call.params!['mountPoint'], '*');
      final vfs = call.params!['vfsOpt'] as Map<String, dynamic>;
      expect(vfs['CacheMode'], 3); // full
    },
  );

  test('policy kill-switch refuses mount (no rpc)', () async {
    final client = _CapturingClient();
    final c = _container(client, policy: false);
    await expectLater(
      c
          .read(mountControllerProvider.notifier)
          .mount(fs: 'gdrive:', mountPoint: '*'),
      throwsA(isA<RcloneException>()),
    );
    expect(client.calls.any((c) => c.method == 'mount/mount'), isFalse);
  });

  test('unmount sends the mount point', () async {
    final client = _CapturingClient();
    final c = _container(client);
    await c.read(mountControllerProvider.notifier).unmount('X:');
    final call = client.calls.firstWhere((c) => c.method == 'mount/unmount');
    expect(call.params!['mountPoint'], 'X:');
  });

  // Exit path. rclone serves every OS mount from the rcd process, so stopping
  // the engine first strands the mount — on Windows the drive letter stayed in
  // Explorer after Airclone closed and only went away on the next launch.
  group('unmountAllForExit', () {
    /// Populates `state` the way the 2s poller would, then clears the log so
    /// each test asserts only what the exit path itself does.
    Future<MountController> primed(
      _CapturingClient client,
      ProviderContainer c,
    ) async {
      final ctrl = c.read(mountControllerProvider.notifier);
      await ctrl.unmount('X:'); // ends in _poll()
      client.calls.clear();
      return ctrl;
    }

    test('unmounts everything, and does NOT re-poll on the way out', () async {
      final client = _CapturingClient()
        ..onRpc = (m, _) => m == 'mount/listmounts'
            ? {
                'mountPoints': ['X:'],
              }
            : <String, dynamic>{};
      final ctrl = await primed(client, _container(client));

      await ctrl.unmountAllForExit();

      // Exactly one call: no mount/listmounts afterwards. Refreshing a list the
      // app is about to discard only delays the window close.
      expect(client.calls.map((e) => e.method), ['mount/unmountall']);
    });

    test('still unmounts when the polled list looks empty', () async {
      // The 2s poller may not have seen a just-created mount yet. Gating the
      // call on `state` would strand exactly the mount this is meant to clean
      // up, so the call is unconditional.
      final client = _CapturingClient()
        ..onRpc = (m, _) =>
            m == 'mount/listmounts' ? {'mountPoints': []} : <String, dynamic>{};
      final c = _container(client);
      final ctrl = c.read(mountControllerProvider.notifier);
      await ctrl.unmount('X:'); // polls -> state stays empty
      expect(c.read(mountControllerProvider), isEmpty);
      client.calls.clear();

      await ctrl.unmountAllForExit();

      expect(client.calls.map((e) => e.method), ['mount/unmountall']);
    });

    test('propagates failure so the caller can bound it', () async {
      final client = _CapturingClient()
        ..onRpc = (m, _) {
          if (m == 'mount/listmounts') {
            return {
              'mountPoints': ['X:'],
            };
          }
          if (m == 'mount/unmountall') throw StateError('wedged');
          return <String, dynamic>{};
        };
      final ctrl = await primed(client, _container(client));

      // app.dart wraps this in a timeout + catch; swallowing here instead would
      // hide a wedged unmount behind a silent success.
      await expectLater(ctrl.unmountAllForExit(), throwsA(isA<StateError>()));
    });
  });
}
