import 'dart:convert';
import 'dart:io';

import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/config_backups.dart';
import 'package:airclone/src/state/config_io.dart';
import 'package:airclone/src/state/config_transfer_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines an `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Controller-level coverage for the config import/export ORCHESTRATION over the
/// pure config-IO seam: the extracted pure helpers (subprocess argv/env, merge
/// loop, replace ordering) exercised without a real engine/subprocess, plus the
/// controller wired to a fake client + temp backups for the merge path, closure
/// scoping, and the encrypted-envelope round-trip.

/// Captures every rpc so a test can assert exactly what was sent (mirrors
/// encrypt_remote_test's fake).
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

class _FakeSettings extends SettingsController {
  _FakeSettings(this._state);
  final SettingsState _state;
  @override
  SettingsState build() => _state;
}

/// Deliberately tiny Argon2id params so envelope round-trips don't pay the
/// production memory-hard cost in the test run (open re-derives from the
/// header-recorded params, so correctness is unaffected).
const _fastKdf = Argon2Params(memory: 64, iterations: 1, parallelism: 1);

void main() {
  group('rcloneEncryptedDumpCommand (pure argv/env)', () {
    test('runs `config dump --config <tmp>` with the pass ONLY in the env', () {
      final cmd = rcloneEncryptedDumpCommand('/tmp/pick.conf', 's3cr3t');
      // Argv is exactly the shared dump-probe vector — password never on it.
      expect(cmd.args, ['config', 'dump', '--config', '/tmp/pick.conf']);
      expect(cmd.args, configDumpArgs('/tmp/pick.conf'));
      expect(cmd.args.contains('s3cr3t'), isFalse);
      // The password travels out-of-band via RCLONE_CONFIG_PASS.
      expect(cmd.env, {'RCLONE_CONFIG_PASS': 's3cr3t'});
    });
  });

  group('replaceViaRcd (encrypted-config replace through the RC seam)', () {
    test(
      'creates every incoming remote, then deletes only the stale ones',
      () async {
        final client = _CapturingClient();
        var backedUp = false;
        final report = await replaceViaRcd(
          client: client,
          incoming: {
            'drive': {'type': 'drive', 'token': 't'},
            'newbie': {'type': 's3'},
          },
          existingNames: ['drive', 'gone1', 'gone2'],
          backup: () async => backedUp = true,
        );
        // Backup ran before any mutation.
        expect(backedUp, isTrue);
        // Two creates (incoming) then two deletes (stale-only; 'drive' is kept
        // because it is also incoming — overwritten by the create, not deleted).
        final creates = client.calls
            .where((c) => c.method == 'config/create')
            .toList();
        final deletes = client.calls
            .where((c) => c.method == 'config/delete')
            .toList();
        expect(
          creates.map((c) => c.params?['name']),
          containsAll(['drive', 'newbie']),
        );
        expect(deletes.map((c) => c.params?['name']), ['gone1', 'gone2']);
        // Creates precede deletes — no wanted remote is stranded mid-op.
        final firstDelete = client.calls.indexWhere(
          (c) => c.method == 'config/delete',
        );
        final lastCreate = client.calls.lastIndexWhere(
          (c) => c.method == 'config/create',
        );
        expect(lastCreate, lessThan(firstDelete));
        expect(report.allOk, isTrue);
        expect(report.created, containsAll(['drive', 'newbie']));
      },
    );

    test(
      'a create Error is reported as a failure, deletes still run',
      () async {
        final client = _CapturingClient()
          ..onRpc = (m, p) => (m == 'config/create' && p?['name'] == 'bad')
              ? {'Error': 'boom'}
              : <String, dynamic>{};
        final report = await replaceViaRcd(
          client: client,
          incoming: {
            'bad': {'type': 'drive'},
          },
          existingNames: ['stale'],
          backup: () async {},
        );
        expect(report.allOk, isFalse);
        expect(report.failed.single.name, 'bad');
        expect(
          client.calls.any(
            (c) => c.method == 'config/delete' && c.params?['name'] == 'stale',
          ),
          isTrue,
        );
      },
    );
  });

  group('importCreateBody (pure)', () {
    test('type is hoisted out of parameters; values stored verbatim', () {
      final body = importCreateBody('drive-imported', {
        'type': 'drive',
        'token': '{"access_token":"x"}',
        'pass': 'OBSCURED==',
      });
      expect(body['name'], 'drive-imported');
      expect(body['type'], 'drive');
      final params = body['parameters'] as Map<String, dynamic>;
      expect(params.containsKey('type'), isFalse); // type is not a parameter
      expect(params['token'], '{"access_token":"x"}');
      expect(params['pass'], 'OBSCURED==');
      final opt = body['opt'] as Map<String, dynamic>;
      // Imported secrets are already obscured — must NOT be re-obscured.
      expect(opt['noObscure'], true);
      expect(opt['nonInteractive'], true);
      expect(opt.containsKey('obscure'), isFalse);
    });

    test('a missing type becomes an empty string (never crashes)', () {
      final body = importCreateBody('x', {'k': 'v'});
      expect(body['type'], '');
    });
  });

  group('mergeRemotes (pure loop)', () {
    test(
      'config/create per decision under its final (renamed) name, backup first',
      () async {
        final log = <String>[];
        final client = _CapturingClient()
          ..onRpc = (method, params) {
            if (method == 'config/create') {
              log.add('create:${params?['name']}');
            }
            return <String, dynamic>{};
          };
        final incoming = <String, Map<String, String>>{
          'fresh': {'type': 'drive', 'token': 'aaa'},
          'drive': {'type': 's3', 'secret': 'OBS=='},
        };
        final plan = [
          const ImportDecision(name: 'fresh', type: 'drive', collision: false),
          const ImportDecision(
            name: 'drive',
            type: 's3',
            collision: true,
            renamedTo: 'drive-imported',
          ),
        ];
        final report = await mergeRemotes(
          client: client,
          incoming: incoming,
          plan: plan,
          backup: () async => log.add('backup'),
        );

        // Backup ran BEFORE any create (the trust substrate ordering).
        expect(log.first, 'backup');
        expect(log, ['backup', 'create:fresh', 'create:drive-imported']);

        // The collision imported under its rename target; the clean one under its
        // own name.
        expect(report.created, ['fresh', 'drive-imported']);
        expect(report.allOk, isTrue);

        final creates = client.calls
            .where((c) => c.method == 'config/create')
            .toList();
        expect(creates.length, 2);
        // Second create carries the incoming 'drive' section, renamed.
        final renamed = creates[1].params!;
        expect(renamed['name'], 'drive-imported');
        expect(renamed['type'], 's3');
        expect((renamed['parameters'] as Map)['secret'], 'OBS==');
      },
    );

    test('a per-remote failure is recorded, never a silent success', () async {
      final client = _CapturingClient()
        ..onRpc = (method, params) => params?['name'] == 'bad'
            ? {'Error': 'auth failed'}
            : <String, dynamic>{};
      final report = await mergeRemotes(
        client: client,
        incoming: {
          'good': {'type': 'drive'},
          'bad': {'type': 's3'},
        },
        plan: [
          const ImportDecision(name: 'good', type: 'drive', collision: false),
          const ImportDecision(name: 'bad', type: 's3', collision: false),
        ],
        backup: () async {},
      );
      expect(report.created, ['good']);
      expect(report.allOk, isFalse);
      expect(report.failed.single.name, 'bad');
      expect(report.failed.single.error, 'auth failed');
    });

    test('a pending interactive question counts as a failure', () async {
      final client = _CapturingClient()
        ..onRpc = (_, _) => {'State': 'needs-oauth'};
      final report = await mergeRemotes(
        client: client,
        incoming: {
          'x': {'type': 'drive'},
        },
        plan: [
          const ImportDecision(name: 'x', type: 'drive', collision: false),
        ],
        backup: () async {},
      );
      expect(report.created, isEmpty);
      expect(report.failed.single.name, 'x');
    });
  });

  group('replaceConfigFile (pure ordering)', () {
    test('snapshots the OLD config before overwriting, then restarts', () async {
      final tmp = Directory.systemTemp.createTempSync('airclone_replace');
      addTearDown(() => tmp.delete(recursive: true));
      final active = File('${tmp.path}/rclone.conf');
      await active.writeAsString('[old]\ntype = s3\n');
      final backups = ConfigBackups(Directory('${tmp.path}/backups'));
      var restarted = false;

      await replaceConfigFile(
        active: active,
        backups: backups,
        newBytes: utf8.encode('[new]\ntype = drive\n'),
        restart: () async => restarted = true,
      );

      // The active file now holds the new config…
      expect(await active.readAsString(), '[new]\ntype = drive\n');
      // …and the engine was restarted after the write.
      expect(restarted, isTrue);
      // …and a backup captured the OLD content — proof the backup preceded the
      // overwrite (a backup taken after would hold the NEW content).
      final saved = await backups.listBackups();
      expect(saved, hasLength(1));
      expect(await saved.single.readAsString(), '[old]\ntype = s3\n');
    });
  });

  group('ConfigTransferController.applyMerge (fake client + temp backups)', () {
    test(
      'creates each planned remote and snapshots the active config',
      () async {
        final tmp = Directory.systemTemp.createTempSync('airclone_merge');
        addTearDown(() => tmp.delete(recursive: true));
        final active = File('${tmp.path}/rclone.conf');
        await active.writeAsString('[existing]\ntype = s3\n');
        final backupsDir = Directory('${tmp.path}/backups');

        final client = _CapturingClient();
        final container = ProviderContainer(
          overrides: [
            engineControllerProvider.overrideWith(() => _FakeEngine(client)),
            configBackupsProvider.overrideWith(
              (ref) async => ConfigBackups(backupsDir),
            ),
            settingsControllerProvider.overrideWith(
              () =>
                  _FakeSettings(SettingsState(configPathOverride: active.path)),
            ),
          ],
        );
        addTearDown(container.dispose);

        final ctrl = container.read(configTransferControllerProvider);
        final incoming = <String, Map<String, String>>{
          'newremote': {'type': 'drive', 'token': 'tok'},
        };
        final report = await ctrl.applyMerge(incoming, [
          const ImportDecision(
            name: 'newremote',
            type: 'drive',
            collision: false,
          ),
        ]);

        expect(report.created, ['newremote']);
        final create = client.calls.firstWhere(
          (c) => c.method == 'config/create',
        );
        expect(create.params!['name'], 'newremote');
        expect((create.params!['parameters'] as Map)['token'], 'tok');
        // The active config was snapshotted before the create.
        final backups = ConfigBackups(backupsDir);
        expect(await backups.listBackups(), hasLength(1));
      },
    );
  });

  group('ConfigTransferController.scopedModel (dependency closure)', () {
    test('a scoped crypt drags in its base; unrelated remotes stay out', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(configTransferControllerProvider);

      final full = <String, Map<String, String>>{
        'drive': {'type': 'drive'},
        'drive-secret': {'type': 'crypt', 'remote': 'drive:vault'},
        's3': {'type': 's3'},
      };
      final scoped = ctrl.scopedModel(full, {'drive-secret'});
      // Base auto-included, unrelated s3 excluded.
      expect(scoped.keys.toSet(), {'drive-secret', 'drive'});
      expect(scoped.containsKey('s3'), isFalse);
      // Values are carried through verbatim.
      expect(scoped['drive-secret']!['remote'], 'drive:vault');
    });
  });

  group('ConfigTransferController envelope round-trip', () {
    test('sealExport → openExport recovers the exact model', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(configTransferControllerProvider);

      final model = <String, Map<String, String>>{
        'drive': {'type': 'drive', 'token': 'a=b=='},
        's3': {'type': 's3', 'provider': 'AWS'},
      };
      // Fast KDF params keep the memory-hard Argon2id off the test's back; the
      // header records them, so openExport re-derives regardless.
      final sealed = await ctrl.sealExport(
        model,
        'correct horse',
        kdf: _fastKdf,
      );
      // It's a real Airclone envelope the importer would sniff.
      expect(detectConfigFormat(sealed), ConfigFormat.aircloneEnvelope);
      final reopened = await ctrl.openExport(sealed, 'correct horse');
      expect(reopened, equals(model));
    });

    test('a wrong passphrase throws WrongPassphrase', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(configTransferControllerProvider);
      final sealed = await ctrl.sealExport(
        {
          'r': {'type': 's3'},
        },
        'right',
        kdf: _fastKdf,
      );
      expect(
        () => ctrl.openExport(sealed, 'wrong'),
        throwsA(isA<WrongPassphrase>()),
      );
    });
  });
}
