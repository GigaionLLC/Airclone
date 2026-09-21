/// What the add-a-cloud driver actually puts on the wire.
///
/// These are the invariants rclone's interactive config machine imposes on a
/// frontend, each of which has been got wrong at least once: no `opt.all`,
/// `parameters` on every call including the continues, the ephemeral answers
/// re-sent each time, passwords never re-sent, and the whole thing run as an
/// async job so a blocking sign-in cannot freeze the engine.
library;

import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/add_remote_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/providers_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// A client that records every call and answers from a script.
class FakeClient implements RcloneClient {
  FakeClient({this.asyncJobs = false});

  /// When true, `config/create` answers with a jobid and the result arrives
  /// through `job/status` — the way a real engine behaves for `_async`.
  final bool asyncJobs;

  final calls = <({String method, Map<String, dynamic>? params})>[];

  /// Queued results for the config calls, in order.
  final List<Map<String, dynamic>> scripted = [];

  /// What `config/oauthstatus` should answer.
  Map<String, dynamic> oauthStatus = const {'status': 'stopped'};

  /// When set, `config/oauthstatus` throws — an engine without the method.
  bool oauthStatusSupported = true;

  Map<String, dynamic>? _pendingJobResult;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    switch (method) {
      case 'config/dump':
        return <String, dynamic>{};
      case 'config/oauthstatus':
        if (!oauthStatusSupported) {
          throw RcloneException(method, 'method not found', statusCode: 404);
        }
        return oauthStatus;
      case 'config/oauthstop':
        return <String, dynamic>{};
      case 'config/delete':
        return <String, dynamic>{};
      case 'job/status':
        final out = _pendingJobResult ?? <String, dynamic>{};
        _pendingJobResult = null;
        return {'finished': true, 'error': '', 'output': out};
      case 'config/create':
      case 'config/update':
        final next = scripted.isEmpty
            ? <String, dynamic>{}
            : scripted.removeAt(0);
        if (asyncJobs) {
          _pendingJobResult = next;
          return {'jobid': calls.length};
        }
        return next;
      default:
        return <String, dynamic>{};
    }
  }

  /// Every config call, in order.
  Iterable<({String method, Map<String, dynamic>? params})> get configCalls =>
      calls.where(
        (c) => c.method == 'config/create' || c.method == 'config/update',
      );

  ({String method, Map<String, dynamic>? params}) get firstConfigCall =>
      configCalls.first;

  Iterable<({String method, Map<String, dynamic>? params})> get continueCalls =>
      configCalls.where((c) => (c.params?['opt'] as Map?)?['continue'] == true);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._client);
  final RcloneClient _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);
}

const sftp = RcloneProvider(
  name: 'sftp',
  description: 'SSH/SFTP',
  options: [
    ProviderOption(name: 'host', required: true),
    ProviderOption(name: 'user'),
    ProviderOption(name: 'pass', isPassword: true),
  ],
);

const drive = RcloneProvider(
  name: 'drive',
  description: 'Google Drive',
  options: [
    ProviderOption(name: 'client_id'),
    ProviderOption(name: 'client_secret'),
    ProviderOption(name: 'token', advanced: true),
  ],
);

ProviderContainer container(FakeClient client, {List<RcloneProvider>? list}) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      providersProvider.overrideWith((ref) async => list ?? [sftp, drive]),
      urlOpenerProvider.overrideWithValue((_) async => true),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// A question rclone would ask, in the shape it arrives in.
Map<String, dynamic> question(
  String state,
  String name, {
  String type = 'bool',
}) => {
  'State': state,
  'Option': {'Name': name, 'Type': type},
};

void main() {
  test('the opening create never sends opt.all', () async {
    final client = FakeClient();
    final c = container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProvider(sftp);
    ctrl.setName('box');
    ctrl.setValue('host', 'example.com');
    await ctrl.submit();

    final opt = client.firstConfigCall.params!['opt'] as Map<String, dynamic>;
    // `all` walks EVERY option as a separate question, and only non-empty
    // values count as pre-answered — so every field left blank came back as a
    // question. That is what made this flow feel like an interrogation.
    expect(opt.containsKey('all'), isFalse);
    expect(opt['nonInteractive'], isTrue);
    expect(opt['obscure'], isTrue);
  });

  test('config calls run as async jobs', () async {
    final client = FakeClient(asyncJobs: true);
    final c = container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProvider(sftp);
    ctrl.setName('box');
    await ctrl.submit();

    // Without `_async` a blocking sign-in freezes the in-process engine, which
    // serialises every RPC through a single worker isolate.
    expect(client.firstConfigCall.params!['_async'], isTrue);
    expect(client.calls.any((x) => x.method == 'job/status'), isTrue);
    // verifying is transient: the connection test runs and the flow lands on
    // the success screen.
    expect(c.read(addRemoteControllerProvider).phase, AddPhase.done);
    expect(c.read(addRemoteControllerProvider).verifyFailed, isFalse);
  });

  test('an engine that ignores _async still completes', () async {
    // Older engines answer inline rather than with a jobid; the driver must
    // take the result it was handed rather than poll for a job that is not
    // there.
    final client = FakeClient();
    final c = container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProvider(sftp);
    ctrl.setName('box');
    await ctrl.submit();
    expect(client.calls.any((x) => x.method == 'job/status'), isFalse);
    expect(c.read(addRemoteControllerProvider).phase, AddPhase.done);
  });

  group('the continue steps', () {
    test('always carry parameters', () async {
      // rclone's rc argument parser rejects config/create and config/update
      // with HTTP 400 when `parameters` is absent — including on a continue.
      final client = FakeClient()
        ..scripted.add(question('*all-set,0,false', 'nounc'));
      final c = container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProvider(sftp);
      ctrl.setName('box');
      await ctrl.submit();
      expect(c.read(addRemoteControllerProvider).phase, AddPhase.question);
      await ctrl.answer('true');

      expect(client.continueCalls, isNotEmpty);
      for (final call in client.continueCalls) {
        expect(call.params!.containsKey('parameters'), isTrue);
      }
    });

    test('re-send sticky ephemeral answers', () async {
      // rclone strips `config_*` keys before saving and rebuilds its answer map
      // from `parameters` on every call, so an answer sent only once is
      // forgotten and the question comes straight back.
      final client = FakeClient()
        ..scripted.add(
          question('client_id_warning', 'config_shared_client_id'),
        );
      final c = container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProvider(drive);
      ctrl.setName('gdrive');
      await ctrl.signIn(SignInMethod.thisDevice);

      final opening = client.firstConfigCall.params!['parameters'] as Map;
      expect(opening['config_is_local'], 'true');
      expect(opening['config_auth_no_browser'], 'true');

      await ctrl.answer('false');
      final cont = client.continueCalls.last.params!['parameters'] as Map;
      expect(cont['config_is_local'], 'true');
      expect(cont['config_auth_no_browser'], 'true');
    });

    test('never re-send a password', () async {
      final client = FakeClient()
        ..scripted.add(question('*all-set,0,false', 'nounc'));
      final c = container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProvider(sftp);
      ctrl.setName('box');
      ctrl.setValue('pass', 'hunter2');
      await ctrl.submit();
      await ctrl.answer('true');

      // The opening call obscures it once; a continue carries no `obscure`, so
      // re-sending would write the password back in the clear.
      expect(
        (client.firstConfigCall.params!['parameters'] as Map)['pass'],
        'hunter2',
      );
      for (final call in client.continueCalls) {
        final params = call.params!['parameters'] as Map;
        expect(params.containsKey('pass'), isFalse);
      }
    });
  });

  test('an edit routes to config/update and keeps its name', () async {
    final client = FakeClient();
    final c = container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    await ctrl.startEdit(const Remote(name: 'box', type: 'sftp', fs: 'box:'));
    await ctrl.submitEdit();
    expect(client.configCalls.last.method, 'config/update');
    expect(client.configCalls.last.params!['name'], 'box');
    expect(client.configCalls.last.params!.containsKey('type'), isFalse);
  });

  test('a name already in use is refused before anything is created', () async {
    final client = _TakenNameClient();
    final c = container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProvider(sftp);
    ctrl.setName('taken');
    await ctrl.submit();

    // config/create on an existing name REPLACES it silently, which on a crypt
    // remote is data loss with no error.
    expect(client.configCalls, isEmpty);
    expect(c.read(addRemoteControllerProvider).phase, AddPhase.setup);
    expect(
      c.read(addRemoteControllerProvider).error,
      contains('already exists'),
    );
  });

  test(
    'an unreadable config refuses rather than assuming the name is free',
    () async {
      final client = _UnreadableConfigClient();
      final c = container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProvider(sftp);
      ctrl.setName('box');
      await ctrl.submit();
      expect(client.configCalls, isEmpty);
      expect(
        c.read(addRemoteControllerProvider).error,
        contains('nothing was created'),
      );
    },
  );
}

class _TakenNameClient extends FakeClient {
  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'config/dump') {
      calls.add((method: method, params: params));
      return {
        'taken': {'type': 'sftp'},
      };
    }
    return super.rpc(method, params);
  }
}

class _UnreadableConfigClient extends FakeClient {
  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'config/dump') {
      calls.add((method: method, params: params));
      throw RcloneException(method, 'config is encrypted');
    }
    return super.rpc(method, params);
  }
}
