import 'package:airclone/src/rclone/models/serve_server.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/serve_controller.dart';
import 'package:airclone/src/state/serve_policy.dart';
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

ProviderContainer _container(
  _CapturingClient client, {
  bool servePolicy = true,
}) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      if (!servePolicy) serveEnabledProvider.overrideWithValue(false),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('ServeServer.fromList', () {
    test('parses the documented serve/list element', () {
      final s = ServeServer.fromList({
        'addr': '[::]:4321',
        'id': 'nfs-ffc2a4e5',
        'params': {
          'fs': 'remote:',
          'type': 'nfs',
          'opt': {'ListenAddr': ':4321'},
          'vfsOpt': {'CacheMode': 'full'},
        },
      });
      expect(s.id, 'nfs-ffc2a4e5');
      expect(s.addr, '[::]:4321');
      expect(s.type, 'nfs');
      expect(s.fs, 'remote:');
    });

    test('[::] / 0.0.0.0 / bare :port are EXPOSED, not loopback', () {
      for (final a in ['[::]:4321', '0.0.0.0:8080', ':8080']) {
        expect(
          ServeServer(id: 'x', addr: a, type: 'http', fs: 'r:').isLoopback,
          isFalse,
          reason: a,
        );
      }
      expect(
        const ServeServer(
          id: 'x',
          addr: '127.0.0.1:8080',
          type: 'http',
          fs: 'r:',
        ).isLoopback,
        isTrue,
      );
      // an http server on [::] is exposed + auth-capable => requiresAuth
      expect(
        const ServeServer(
          id: 'x',
          addr: '[::]:4321',
          type: 'http',
          fs: 'r:',
        ).requiresAuth,
        isTrue,
      );
    });

    test('tolerates a malformed element without throwing', () {
      final s = ServeServer.fromList({'id': 7, 'params': 'oops'});
      expect(s.id, '');
      expect(s.type, '');
    });

    test(
      'displayUrl uses 127.0.0.1 for loopback, lanIp for all-interfaces',
      () {
        const lo = ServeServer(
          id: 'x',
          addr: '127.0.0.1:8080',
          type: 'webdav',
          fs: 'r:',
        );
        expect(lo.displayUrl(), 'http://127.0.0.1:8080');
        const any = ServeServer(id: 'x', addr: ':8080', type: 'http', fs: 'r:');
        expect(any.displayUrl(lanIp: '192.168.1.5'), 'http://192.168.1.5:8080');
      },
    );
  });

  group('ServeController.start — security enforced in code', () {
    test('loopback bind needs no auth and sends 127.0.0.1', () async {
      final client = _CapturingClient()
        ..onRpc = (_, _) => {'id': 'http-1', 'addr': '127.0.0.1:8080'};
      final c = _container(client);
      await c
          .read(serveControllerProvider.notifier)
          .start(type: 'http', fs: 'gd:Photos', lan: false, port: 8080);
      final call = client.calls.firstWhere((c) => c.method == 'serve/start');
      expect(call.params!['addr'], '127.0.0.1:8080');
      expect(call.params!.containsKey('user'), isFalse);
      // no rc creds / config password ever leak into serve params
      for (final k in ['rc_user', 'rc_pass', '_config', 'RCLONE_CONFIG_PASS']) {
        expect(call.params!.containsKey(k), isFalse, reason: k);
      }
    });

    test('LAN auth-capable serve REFUSES without user+pass (no rpc)', () async {
      final client = _CapturingClient();
      final c = _container(client);
      await expectLater(
        c
            .read(serveControllerProvider.notifier)
            .start(type: 'webdav', fs: 'gd:', lan: true, port: 8080),
        throwsA(isA<RcloneException>()),
      );
      expect(client.calls.any((c) => c.method == 'serve/start'), isFalse);
    });

    test('LAN serve with user+pass binds :port and sends creds', () async {
      final client = _CapturingClient()
        ..onRpc = (_, _) => {'id': 'http-2', 'addr': '[::]:8080'};
      final c = _container(client);
      await c
          .read(serveControllerProvider.notifier)
          .start(
            type: 'http',
            fs: 'gd:',
            lan: true,
            port: 8080,
            user: 'u',
            pass: 'p',
          );
      final call = client.calls.firstWhere((c) => c.method == 'serve/start');
      expect(call.params!['addr'], ':8080');
      expect(call.params!['user'], 'u');
      expect(call.params!['pass'], 'p');
    });

    test('LAN DLNA REFUSES without acknowledgement', () async {
      final client = _CapturingClient();
      final c = _container(client);
      await expectLater(
        c
            .read(serveControllerProvider.notifier)
            .start(type: 'dlna', fs: 'gd:', lan: true, port: 8200),
        throwsA(isA<RcloneException>()),
      );
      expect(client.calls.any((c) => c.method == 'serve/start'), isFalse);
    });

    test('policy kill-switch refuses start but allows stopall', () async {
      final client = _CapturingClient();
      final c = _container(client, servePolicy: false);
      await expectLater(
        c
            .read(serveControllerProvider.notifier)
            .start(type: 'http', fs: 'gd:', lan: false, port: 8080),
        throwsA(isA<RcloneException>()),
      );
      expect(client.calls.any((c) => c.method == 'serve/start'), isFalse);
      await c.read(serveControllerProvider.notifier).panicStopAll();
      expect(client.calls.any((c) => c.method == 'serve/stopall'), isTrue);
    });
  });
}
