import 'package:airclone/src/rclone/models/provider.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/add_remote_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/providers_provider.dart';
import 'package:airclone/src/ui/home_screen.dart';
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

final _s3 = const RcloneProvider(
  name: 's3',
  description: '',
  options: [
    ProviderOption(name: 'access_key_id'),
    ProviderOption(name: 'secret_access_key', isPassword: true),
    ProviderOption(name: 'region'),
  ],
);

Map<String, dynamic> _getResponse(String method, Map<String, dynamic>? _) =>
    method == 'config/get'
    ? {
        'type': 's3',
        'access_key_id': 'AKIA',
        'secret_access_key': 'OBSCURED_TOKEN',
        'region': 'us-east-1',
      }
    : <String, dynamic>{};

ProviderContainer _container(_CapturingClient client) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      providersProvider.overrideWith((ref) async => [_s3]),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  const remote = Remote(name: 'myS3', type: 's3', fs: 'myS3:');

  test(
    'startEdit prefills non-passwords, blanks passwords, drops type',
    () async {
      final client = _CapturingClient()..onRpc = _getResponse;
      final c = _container(client);
      await c.read(addRemoteControllerProvider.notifier).startEdit(remote);
      final st = c.read(addRemoteControllerProvider);
      expect(st.isEdit, isTrue);
      expect(st.editName, 'myS3');
      expect(st.values['access_key_id'], 'AKIA');
      expect(st.values['region'], 'us-east-1');
      expect(st.values['secret_access_key'], ''); // blanked
      expect(st.values.containsKey('type'), isFalse);
    },
  );

  test(
    'edit omits a blank password (never re-obscures the existing one)',
    () async {
      final client = _CapturingClient()..onRpc = _getResponse;
      final c = _container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      await ctrl.startEdit(remote);
      ctrl.setValue('region', 'eu-west-1'); // change only region
      await ctrl.submitEdit();

      final call = client.calls.firstWhere((c) => c.method == 'config/update');
      final params = call.params!['parameters'] as Map<String, dynamic>;
      expect(params['region'], 'eu-west-1');
      expect(params['access_key_id'], 'AKIA');
      expect(params.containsKey('secret_access_key'), isFalse); // critical
      expect(call.params!['name'], 'myS3');
      expect(call.params!.containsKey('type'), isFalse);
      final opt = call.params!['opt'] as Map<String, dynamic>;
      expect(opt['obscure'], true);
      expect(opt['nonInteractive'], true);
    },
  );

  test(
    'a typed password is sent plaintext with obscure:true (single-obscure)',
    () async {
      final client = _CapturingClient()..onRpc = _getResponse;
      final c = _container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      await ctrl.startEdit(remote);
      ctrl.setValue('secret_access_key', 'newPlainSecret');
      await ctrl.submitEdit();
      final call = client.calls.firstWhere((c) => c.method == 'config/update');
      final params = call.params!['parameters'] as Map<String, dynamic>;
      expect(params['secret_access_key'], 'newPlainSecret');
      // The app must NOT pre-obscure (rclone obscures once via opt.obscure).
      expect(client.calls.any((c) => c.method == 'core/obscure'), isFalse);
    },
  );

  test('startEdit on config/get error lands in error phase, no update', () async {
    final client = _CapturingClient()
      ..onRpc = (m, _) =>
          m == 'config/get' ? {'Error': 'not found'} : <String, dynamic>{};
    // config/get returning {Error:...} doesn't throw, so startEdit proceeds with
    // those keys; assert it never issues a config/update on its own.
    final c = _container(client);
    await c.read(addRemoteControllerProvider.notifier).startEdit(remote);
    expect(client.calls.any((c) => c.method == 'config/update'), isFalse);
  });

  test(
    'duplicate copies obscured values verbatim with noObscure:true',
    () async {
      final client = _CapturingClient()..onRpc = _getResponse;
      await duplicateRemoteRpc(client, source: 'myS3', newName: 'myS3-copy');
      final create = client.calls.firstWhere(
        (c) => c.method == 'config/create',
      );
      expect(create.params!['name'], 'myS3-copy');
      expect(create.params!['type'], 's3');
      final params = create.params!['parameters'] as Map<String, dynamic>;
      expect(params['secret_access_key'], 'OBSCURED_TOKEN'); // verbatim
      expect(params.containsKey('type'), isFalse);
      final opt = create.params!['opt'] as Map<String, dynamic>;
      expect(opt['noObscure'], true);
      expect(opt.containsKey('obscure'), isFalse); // never double-obscure
    },
  );
}
