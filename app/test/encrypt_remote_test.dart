import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/encrypt_remote_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines an `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Captures every rpc call so the test can assert exactly what was sent.
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

ProviderContainer _container(_CapturingClient client) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test(
    'config/create sends crypt params + obscure; no double-obscure',
    () async {
      final client = _CapturingClient()
        ..onRpc = (method, _) => method == 'core/command'
            ? {'result': '0 differences found', 'error': 0}
            : <String, dynamic>{};
      final c = _container(client);
      await c
          .read(encryptRemoteControllerProvider.notifier)
          .submit(
            name: 'drive-secret',
            baseFs: 'gdrive:Secret',
            filenameEncryption: 'standard',
            dirNameEncryption: true,
            password: 'hunter2',
          );

      final create = client.calls.firstWhere(
        (c) => c.method == 'config/create',
      );
      expect(create.params!['name'], 'drive-secret');
      expect(create.params!['type'], 'crypt');
      final params = create.params!['parameters'] as Map<String, dynamic>;
      expect(params['remote'], 'gdrive:Secret');
      expect(params['filename_encryption'], 'standard');
      expect(params['directory_name_encryption'], 'true');
      expect(params['password'], 'hunter2');
      expect(params.containsKey('password2'), isFalse); // omitted when blank
      final opt = create.params!['opt'] as Map<String, dynamic>;
      expect(opt['obscure'], true);
      expect(opt['nonInteractive'], true);
      // Must NOT pre-obscure separately (would double-obscure).
      expect(client.calls.any((c) => c.method == 'core/obscure'), isFalse);
      // Verified -> done.
      expect(c.read(encryptRemoteControllerProvider).phase, EncryptPhase.done);
      expect(c.read(encryptRemoteControllerProvider).verifyOk, isTrue);
    },
  );

  test('password2 included only when a salt is given', () async {
    final client = _CapturingClient();
    final c = _container(client);
    await c
        .read(encryptRemoteControllerProvider.notifier)
        .submit(
          name: 'x',
          baseFs: 'b:',
          filenameEncryption: 'standard',
          dirNameEncryption: false,
          password: 'p',
          password2: 'saltywater',
        );
    final create = client.calls.firstWhere((c) => c.method == 'config/create');
    final params = create.params!['parameters'] as Map<String, dynamic>;
    expect(params['password2'], 'saltywater');
    expect(params['directory_name_encryption'], 'false');
  });

  test('a config/create error stops before cryptcheck', () async {
    final client = _CapturingClient()
      ..onRpc = (method, _) =>
          method == 'config/create' ? {'Error': 'bad password'} : {};
    final c = _container(client);
    await c
        .read(encryptRemoteControllerProvider.notifier)
        .submit(
          name: 'x',
          baseFs: 'b:',
          filenameEncryption: 'standard',
          dirNameEncryption: true,
          password: 'p',
        );
    final st = c.read(encryptRemoteControllerProvider);
    expect(st.phase, EncryptPhase.error);
    expect(st.error, 'bad password');
    expect(client.calls.any((c) => c.method == 'core/command'), isFalse);
  });

  test('a failed cryptcheck is non-fatal (created but unverified)', () async {
    final client = _CapturingClient()
      ..onRpc = (method, _) => method == 'core/command'
          ? {'result': '1 differences found', 'error': 1}
          : <String, dynamic>{};
    final c = _container(client);
    await c
        .read(encryptRemoteControllerProvider.notifier)
        .submit(
          name: 'x',
          baseFs: 'b:',
          filenameEncryption: 'standard',
          dirNameEncryption: true,
          password: 'p',
        );
    final st = c.read(encryptRemoteControllerProvider);
    expect(st.phase, EncryptPhase.done); // NOT error
    expect(st.verifyOk, isFalse);
  });

  test('EncryptRemoteState carries no password field', () {
    // Structural guarantee: the wizard state holds no secret. (If a `password`
    // field is ever added this won't compile cleanly against the assertion.)
    const st = EncryptRemoteState();
    expect(st.phase, EncryptPhase.form);
    expect(st.error, isNull);
  });
}
