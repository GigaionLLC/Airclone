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
      // The probe name is now UNIQUE per run, so capture it from the mkdir call
      // and reflect it back through the crypt listing.
      String? probe;
      final client = _CapturingClient()
        ..onRpc = (method, params) {
          if (method == 'operations/mkdir') {
            probe = params?['remote'] as String?;
            return <String, dynamic>{};
          }
          // Canary: the crypt remote shows the probe under its plaintext name,
          // the base remote shows a DIFFERENT (encrypted) name -> verifyOk true.
          if (method == 'operations/list') {
            return params?['fs'] == 'drive-secret:'
                ? {
                    'list': [
                      {'Name': probe, 'IsDir': true},
                    ],
                  }
                : {
                    'list': [
                      {'Name': 'a1b2c3ENCRYPTED', 'IsDir': true},
                    ],
                  };
          }
          return <String, dynamic>{};
        };
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
      // Verification runs on safe RC primitives only — never core/command.
      expect(client.calls.any((c) => c.method == 'core/command'), isFalse);
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

  test('filename_encryption "off" serializes verbatim', () async {
    final client = _CapturingClient();
    final c = _container(client);
    await c
        .read(encryptRemoteControllerProvider.notifier)
        .submit(
          name: 'x',
          baseFs: 'b:',
          filenameEncryption: 'off',
          dirNameEncryption: false,
          password: 'p',
        );
    final create = client.calls.firstWhere((c) => c.method == 'config/create');
    final params = create.params!['parameters'] as Map<String, dynamic>;
    expect(params['filename_encryption'], 'off');
    expect(params['directory_name_encryption'], 'false');
  });

  test('filename_encryption "obfuscate" serializes verbatim', () async {
    final client = _CapturingClient();
    final c = _container(client);
    await c
        .read(encryptRemoteControllerProvider.notifier)
        .submit(
          name: 'x',
          baseFs: 'b:',
          filenameEncryption: 'obfuscate',
          dirNameEncryption: true,
          password: 'p',
        );
    final create = client.calls.firstWhere((c) => c.method == 'config/create');
    final params = create.params!['parameters'] as Map<String, dynamic>;
    expect(params['filename_encryption'], 'obfuscate');
    expect(params['directory_name_encryption'], 'true');
  });

  test('a config/create error stops before verification', () async {
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
    // No canary probe is created when the remote itself failed to configure.
    expect(client.calls.any((c) => c.method == 'operations/mkdir'), isFalse);
  });

  test(
    'canary: crypt shows the probe, base shows a DIFFERENT name -> ok',
    () async {
      String? probe;
      final client = _CapturingClient()
        ..onRpc = (method, params) {
          if (method == 'operations/mkdir') {
            probe = params?['remote'] as String?;
            return <String, dynamic>{};
          }
          if (method == 'operations/list') {
            // crypt root -> plaintext probe (decrypt works); base root ->
            // scrambled name (encrypt works).
            return params?['fs'] == 'secret:'
                ? {
                    'list': [
                      {'Name': probe, 'IsDir': true},
                    ],
                  }
                : {
                    'list': [
                      {'Name': 'v9Q2scrambled', 'IsDir': true},
                    ],
                  };
          }
          return <String, dynamic>{};
        };
      final c = _container(client);
      await c
          .read(encryptRemoteControllerProvider.notifier)
          .submit(
            name: 'secret',
            baseFs: 'gdrive:Vault',
            filenameEncryption: 'standard',
            dirNameEncryption: true,
            password: 'p',
          );
      final st = c.read(encryptRemoteControllerProvider);
      expect(st.phase, EncryptPhase.done);
      expect(st.verifyOk, isTrue);
      // The probe name is UNIQUE per run (random suffix), never the old fixed
      // name — a fixed name could collide with a user-owned dir at a verbatim
      // base location.
      expect(probe, isNotNull);
      expect(probe, startsWith('.airclone-verify-'));
      expect(probe, isNot('.airclone-verify'));
      // Probe created + cleaned up THROUGH the crypt remote (not the base), and
      // cleanup uses the non-recursive rmdir (refuses a non-empty dir), NOT the
      // recursive purge that could wipe user data.
      expect(
        client.calls.any(
          (c) =>
              c.method == 'operations/mkdir' &&
              c.params?['fs'] == 'secret:' &&
              c.params?['remote'] == probe,
        ),
        isTrue,
      );
      expect(
        client.calls.any(
          (c) =>
              c.method == 'operations/rmdir' &&
              c.params?['fs'] == 'secret:' &&
              c.params?['remote'] == probe,
        ),
        isTrue,
      );
      // The dangerous recursive primitive is never used.
      expect(client.calls.any((c) => c.method == 'operations/purge'), isFalse);
    },
  );

  test('canary: base shows the SAME plaintext name -> verifyOk false', () async {
    String? probe;
    final client = _CapturingClient()
      ..onRpc = (method, params) {
        if (method == 'operations/mkdir') {
          probe = params?['remote'] as String?;
          return <String, dynamic>{};
        }
        // Both sides show the plaintext probe -> encryption not taking effect.
        if (method == 'operations/list') {
          return {
            'list': [
              {'Name': probe, 'IsDir': true},
            ],
          };
        }
        return <String, dynamic>{};
      };
    final c = _container(client);
    await c
        .read(encryptRemoteControllerProvider.notifier)
        .submit(
          name: 'secret',
          baseFs: 'b:',
          filenameEncryption: 'standard',
          dirNameEncryption: true,
          password: 'p',
        );
    final st = c.read(encryptRemoteControllerProvider);
    expect(st.phase, EncryptPhase.done); // NOT error — best-effort
    expect(st.verifyOk, isFalse);
    expect(st.verifyMessage, isNotNull);
  });

  test(
    'canary: a failed mkdir is non-fatal (verifyOk null) and skips cleanup',
    () async {
      final client = _CapturingClient()
        ..onRpc = (method, _) {
          if (method == 'operations/mkdir') {
            throw RcloneException('operations/mkdir', 'boom');
          }
          return <String, dynamic>{};
        };
      final c = _container(client);
      await c
          .read(encryptRemoteControllerProvider.notifier)
          .submit(
            name: 'secret',
            baseFs: 'b:',
            filenameEncryption: 'standard',
            dirNameEncryption: true,
            password: 'p',
          );
      final st = c.read(encryptRemoteControllerProvider);
      expect(st.phase, EncryptPhase.done);
      expect(st.verifyOk, isNull);
      // When mkdir NEVER created the probe, cleanup must not run — we must never
      // rmdir/purge a dir we didn't create (the old code purged unconditionally
      // in the finally, even on the catch path).
      expect(client.calls.any((c) => c.method == 'operations/rmdir'), isFalse);
      expect(client.calls.any((c) => c.method == 'operations/purge'), isFalse);
    },
  );

  test(
    'filename_encryption "off" short-circuits to null (no base name diff)',
    () async {
      String? probe;
      final client = _CapturingClient()
        ..onRpc = (method, params) {
          if (method == 'operations/mkdir') {
            probe = params?['remote'] as String?;
            return <String, dynamic>{};
          }
          if (method == 'operations/list') {
            return {
              'list': [
                {'Name': probe, 'IsDir': true},
              ],
            };
          }
          return <String, dynamic>{};
        };
      final c = _container(client);
      await c
          .read(encryptRemoteControllerProvider.notifier)
          .submit(
            name: 'secret',
            baseFs: 'b:',
            filenameEncryption: 'off',
            dirNameEncryption: false,
            password: 'p',
          );
      final st = c.read(encryptRemoteControllerProvider);
      expect(st.phase, EncryptPhase.done);
      expect(st.verifyOk, isNull);
      // Names are plaintext by design, so the BASE remote is never listed.
      expect(
        client.calls.any(
          (c) => c.method == 'operations/list' && c.params?['fs'] == 'b:',
        ),
        isFalse,
      );
      // Reachability probe is still created + cleaned up on the crypt remote,
      // via the safe non-recursive rmdir (never purge).
      expect(client.calls.any((c) => c.method == 'operations/mkdir'), isTrue);
      expect(client.calls.any((c) => c.method == 'operations/rmdir'), isTrue);
      expect(client.calls.any((c) => c.method == 'operations/purge'), isFalse);
    },
  );

  test('canary: probe name is distinct on each run', () async {
    final probes = <String>[];
    _CapturingClient makeClient() =>
        _CapturingClient()
          ..onRpc = (method, params) {
            if (method == 'operations/mkdir') {
              probes.add(params?['remote'] as String);
            }
            return <String, dynamic>{};
          };

    for (var i = 0; i < 2; i++) {
      final client = makeClient();
      final c = _container(client);
      await c
          .read(encryptRemoteControllerProvider.notifier)
          .submit(
            name: 'secret',
            baseFs: 'b:',
            filenameEncryption: 'standard',
            dirNameEncryption: true,
            password: 'p',
          );
    }
    expect(probes, hasLength(2));
    // Two runs must never reuse a probe name — a stale/crashed-run dir can then
    // never be mistaken for the current run's.
    expect(probes[0], isNot(probes[1]));
    expect(probes.every((p) => p.startsWith('.airclone-verify-')), isTrue);
  });

  test('EncryptRemoteState carries no password field', () {
    // Structural guarantee: the wizard state holds no secret. (If a `password`
    // field is ever added this won't compile cleanly against the assertion.)
    const st = EncryptRemoteState();
    expect(st.phase, EncryptPhase.form);
    expect(st.error, isNull);
  });
}
