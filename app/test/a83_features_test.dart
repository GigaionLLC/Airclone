import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/mount_controller.dart';
import 'package:airclone/src/ui/checksum_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

class _FakeClient implements RcloneClient {
  _FakeClient([this.onRpc]);
  final Map<String, dynamic> Function(String, Map<String, dynamic>?)? onRpc;
  final calls = <({String method, Map<String, dynamic>? params})>[];

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

void main() {
  group('fetchChecksums', () {
    test('reads the Hashes map from operations/stat, sorted by type', () async {
      final client = _FakeClient(
        (m, p) => {
          'item': {
            'Name': 'a.bin',
            'Hashes': {'SHA-1': 'bbb', 'MD5': 'aaa', 'DropboxHash': ''},
          },
        },
      );
      final h = await fetchChecksums(client, fs: 'gd:', remote: 'a.bin');
      expect(h!.keys.toList(), ['MD5', 'SHA-1']); // sorted; empty value dropped
      expect(h['MD5'], 'aaa');
      // The stat call asked for hashes, unrestricted (cloud backend).
      final call = client.calls.single;
      expect(call.method, 'operations/stat');
      expect((call.params!['opt'] as Map)['showHash'], true);
      expect((call.params!['opt'] as Map).containsKey('hashTypes'), isFalse);
    });

    test('hashTypes restriction is passed through (local files)', () async {
      final client = _FakeClient(
        (m, p) => {
          'item': {'Hashes': {}},
        },
      );
      await fetchChecksums(
        client,
        fs: '/',
        remote: 'big.iso',
        hashTypes: localHashTypes,
      );
      expect(
        (client.calls.single.params!['opt'] as Map)['hashTypes'],
        localHashTypes,
      );
    });

    test(
      'null item → null (file gone); item without Hashes → empty map',
      () async {
        expect(
          await fetchChecksums(
            _FakeClient((m, p) => {'item': null}),
            fs: 'gd:',
            remote: 'a',
          ),
          isNull, // not found — dialog says so instead of "no hashes"
        );
        expect(
          await fetchChecksums(
            _FakeClient(
              (m, p) => {
                'item': {'Name': 'a'},
              },
            ),
            fs: 'gd:',
            remote: 'a',
          ),
          isEmpty,
        );
      },
    );
  });

  group('queue pause/resume', () {
    test('paused queue holds dispatch; resume releases it', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final jobs = c.read(jobsControllerProvider.notifier);

      c.read(queuePausedProvider.notifier).toggle(); // pause
      var dispatched = false;
      final j = jobs.add(
        type: JobType.copy,
        source: 'a',
        dest: 'b',
        status: JobStatus.queued,
      );
      jobs.enqueue(j.id, () async => dispatched = true);

      expect(dispatched, isFalse);
      expect(c.read(jobsControllerProvider).single.isQueued, isTrue);

      c.read(queuePausedProvider.notifier).toggle(); // resume → pumps
      await Future<void>.delayed(Duration.zero);
      expect(dispatched, isTrue);
      expect(c.read(jobsControllerProvider).single.isRunning, isTrue);
    });
  });

  group('Job.etaLabel', () {
    test('computes remaining time from speed', () {
      const j = Job(
        id: 1,
        type: JobType.copy,
        source: 'a',
        dest: 'b',
        status: JobStatus.running,
        bytes: 50,
        total: 150,
        speedBps: 10,
      );
      expect(j.etaLabel, '10s');
    });

    test('unknown speed/total → em dash; finished → empty', () {
      const running = Job(
        id: 1,
        type: JobType.copy,
        source: 'a',
        dest: 'b',
        status: JobStatus.running,
      );
      expect(running.etaLabel, '—');
      const done = Job(
        id: 2,
        type: JobType.copy,
        source: 'a',
        dest: 'b',
        status: JobStatus.success,
      );
      expect(done.etaLabel, '');
    });
  });

  group('mount refreshCache', () {
    test('sends vfs/refresh with rclone\'s exact wire types', () async {
      final client = _FakeClient();
      final c = ProviderContainer(
        overrides: [
          engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        ],
      );
      addTearDown(c.dispose);
      final err = await c
          .read(mountControllerProvider.notifier)
          .refreshCache('gdrive:');
      expect(err, isNull);
      final call = client.calls.singleWhere((x) => x.method == 'vfs/refresh');
      expect(call.params!['fs'], 'gdrive:');
      // rclone's vfs/rc hard-asserts STRING params — a JSON bool is rejected
      // ("value must be string"); verified live against rclone v1.74.3.
      expect(call.params!['recursive'], 'true');
      // Recursive walks can take minutes on big remotes — must run async.
      expect(call.params!['_async'], true);
    });

    test(
      'omits the fs key when empty (legacy bare-string listmounts)',
      () async {
        final client = _FakeClient();
        final c = ProviderContainer(
          overrides: [
            engineControllerProvider.overrideWith(() => _FakeEngine(client)),
          ],
        );
        addTearDown(c.dispose);
        await c.read(mountControllerProvider.notifier).refreshCache('');
        final call = client.calls.singleWhere((x) => x.method == 'vfs/refresh');
        // Present-but-empty fs would be looked up literally ("no VFS found with
        // name ''"); absent lets rclone auto-select the sole active VFS.
        expect(call.params!.containsKey('fs'), isFalse);
      },
    );

    test('surfaces the engine error message', () async {
      final client = _FakeClient(
        (m, p) => throw RcloneException('vfs/refresh', 'no VFS active'),
      );
      final c = ProviderContainer(
        overrides: [
          engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        ],
      );
      addTearDown(c.dispose);
      expect(
        await c.read(mountControllerProvider.notifier).refreshCache('x:'),
        'no VFS active',
      );
    });
  });
}
