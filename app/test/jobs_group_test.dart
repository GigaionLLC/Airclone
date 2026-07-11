import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Records the `group` passed to every `core/stats` call so we can prove the
/// poller scopes stats to the SAME group the transfer was dispatched with. A
/// file stat + a copyfile jobid keep the dispatch flow going; job/status stays
/// unfinished so the job is still running when the 1 s poller ticks.
class _StatsSpyClient implements RcloneClient {
  final statsGroups = <String?>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    switch (method) {
      case 'operations/stat':
        return const {
          'item': {'IsDir': false},
        };
      case 'operations/copyfile':
        return const {'jobid': 42}; // rclone jobid (deliberately != local id 0)
      case 'core/stats':
        statsGroups.add(params?['group'] as String?);
        return const {'bytes': 100, 'totalBytes': 200, 'speed': 50.0};
      case 'job/status':
        return const {'finished': false};
    }
    return const {};
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
  test(
    'the poller scopes core/stats to the LOCAL job-id group (matches dispatch)',
    () async {
      final client = _StatsSpyClient();
      final c = ProviderContainer(
        overrides: [
          engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        ],
      );
      addTearDown(c.dispose);

      final job = c.read(jobsControllerProvider.notifier).add(
        type: JobType.copy,
        source: 'a:f',
        dest: 'b:f',
      );
      // Simulate a dispatched transfer: rclone jobid 42, group tagged with the
      // LOCAL id (exactly what TransferService does).
      c.read(jobsControllerProvider.notifier).update(job.id, jobid: 42);
      expect(job.id, isNot(42), reason: 'local id and rclone jobid must differ');

      // Wait for one 1 s poller tick to fire.
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(client.statsGroups, isNotEmpty, reason: 'poller should have ticked');
      // Every stats query is scoped to airclone/<localId>, NOT airclone/42.
      expect(client.statsGroups, everyElement('airclone/${job.id}'));
      expect(client.statsGroups, isNot(contains('airclone/42')));

      // And the byte counters actually landed on the job (progress works).
      final polled = c.read(jobsControllerProvider).first;
      expect(polled.bytes, 100);
      expect(polled.total, 200);
    },
    timeout: const Timeout(Duration(seconds: 6)),
  );
}
