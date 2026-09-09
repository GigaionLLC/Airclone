import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/encrypt_remote_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines an `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// `config/create` on a name that ALREADY EXISTS silently replaces that remote:
/// exit 0, no warning, nothing in the response that distinguishes it from
/// creating a new one.
///
/// On a crypt remote that is data loss without an error. The files stay where
/// they are, but the new password/salt cannot decrypt their names, so rclone
/// skips them and returns an empty listing — the pane then renders "Empty
/// folder". A user hit exactly that, and the wizard's own round-trip canary
/// does not catch it, because it only proves the NEW key is self-consistent.
class _CapturingClient implements RcloneClient {
  _CapturingClient({this.existing = const [], this.dumpThrows = false});

  /// Remote names already in the config, as `config/dump` would report them.
  final List<String> existing;
  final bool dumpThrows;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add(method);
    if (method == 'config/dump') {
      if (dumpThrows) throw StateError('config unreadable');
      return {
        for (final n in existing) n: <String, dynamic>{'type': 'drive'},
      };
    }
    return <String, dynamic>{};
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

ProviderContainer _container(_CapturingClient client) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _submit(ProviderContainer c, String name) => c
    .read(encryptRemoteControllerProvider.notifier)
    .submit(
      name: name,
      baseFs: 'gdrive:Secret',
      filenameEncryption: 'standard',
      dirNameEncryption: true,
      password: 'hunter2',
    );

void main() {
  test('refuses to create over an existing remote', () async {
    final client = _CapturingClient(existing: ['drive-secret', 'gdrive']);
    final c = _container(client);

    await _submit(c, 'drive-secret');

    // The bug: this used to sail through and replace the remote.
    expect(client.calls, isNot(contains('config/create')));
    final st = c.read(encryptRemoteControllerProvider);
    expect(st.phase, EncryptPhase.error);
    expect(st.error, contains('already exists'));
  });

  test('fails closed when the existing remotes cannot be read', () async {
    // An unreadable config must NOT read as "that name is free". Guessing wrong
    // in that direction is what destroys a populated remote.
    final client = _CapturingClient(dumpThrows: true);
    final c = _container(client);

    await _submit(c, 'drive-secret');

    expect(client.calls, isNot(contains('config/create')));
    expect(c.read(encryptRemoteControllerProvider).phase, EncryptPhase.error);
  });

  test('still creates when the name is free', () async {
    final client = _CapturingClient(existing: ['gdrive']);
    final c = _container(client);

    await _submit(c, 'drive-secret');

    expect(client.calls, contains('config/create'));
  });
}
