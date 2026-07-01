import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/transfer_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Records dispatched RC calls; stat says "file", the copy returns a jobid.
class _FakeClient implements RcloneClient {
  final calls = <({String method, Map<String, dynamic>? params})>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    if (method == 'operations/stat') return const {'item': {'IsDir': false}};
    if (method == 'operations/copyfile') return const {'jobid': 42};
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

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

const _a = Remote(name: 'a', type: 'local', fs: 'a:');
const _b = Remote(name: 'b', type: 's3', fs: 'b:');

void main() {
  test('retry replays the exact RC call as a new job, original untouched', () async {
    final client = _FakeClient();
    final c = ProviderContainer(
      overrides: [
        engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      ],
    );
    addTearDown(c.dispose);

    final svc = c.read(transferServiceProvider);
    await svc.transfer(
      srcRemote: _a,
      srcPath: 'f.txt',
      dstRemote: _b,
      dstPath: 'f.txt',
      type: JobType.copy,
    );
    await _settle();

    final jobs = c.read(jobsControllerProvider);
    expect(jobs.length, 1);
    final original = jobs.first;
    // Force it to a failed terminal state (as the poller would on RC failure).
    c.read(jobsControllerProvider.notifier).markDone(original.id, JobStatus.failed);
    expect(c.read(jobsControllerProvider).first.canRetry, isTrue);

    final copyCallsBefore =
        client.calls.where((x) => x.method == 'operations/copyfile').length;

    await svc.retry(original.id);
    await _settle();

    // A new job exists; the original failed job is still present + failed.
    final after = c.read(jobsControllerProvider);
    expect(after.length, 2);
    expect(after.firstWhere((j) => j.id == original.id).status, JobStatus.failed);

    // The retry re-dispatched the SAME copyfile call (one more than before).
    final copyCalls =
        client.calls.where((x) => x.method == 'operations/copyfile').toList();
    expect(copyCalls.length, copyCallsBefore + 1);
    // Same src/dst, only the _group is refreshed to the new job.
    final last = copyCalls.last.params!;
    expect(last['srcFs'], 'a:');
    expect(last['srcRemote'], 'f.txt');
    expect(last['dstFs'], 'b:');
    expect(last['dstRemote'], 'f.txt');
    final newJob = after.firstWhere((j) => j.id != original.id);
    expect(last['_group'], 'airclone/${newJob.id}');
  });

  test('retry is a no-op for a job that never dispatched (no rcMethod)', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final jobs = c.read(jobsControllerProvider.notifier);
    final j = jobs.add(type: JobType.copy, source: 'x', dest: 'y');
    jobs.markDone(j.id, JobStatus.failed, error: 'Engine not ready');
    expect(c.read(jobsControllerProvider).first.canRetry, isFalse);

    await c.read(transferServiceProvider).retry(j.id);
    await _settle();
    expect(c.read(jobsControllerProvider).length, 1); // no new job created
  });
}
