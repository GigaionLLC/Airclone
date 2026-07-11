import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/console/console_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// A plain RcloneClient (NOT HttpRcloneClient) so the controller takes the
/// buffered core/command path. Records calls + returns a canned result.
class _FakeClient implements RcloneClient {
  final calls = <String>[];
  Map<String, dynamic> result = const {'result': 'one\ntwo', 'error': false};

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add(method);
    if (method == 'core/command') return result;
    return const {};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._c);
  final RcloneClient _c;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _c);
}

void main() {
  ProviderContainer make(_FakeClient client) {
    final c = ProviderContainer(
      overrides: [
        engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  const id = 'test';

  test('runs a command, captures output lines, marks the job done', () async {
    final client = _FakeClient();
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('lsjson gdrive:');
    await ctrl.run();

    expect(client.calls, contains('core/command'));
    final texts = c
        .read(consoleControllerProvider(id))
        .log
        .map((l) => l.text)
        .toList();
    expect(texts, contains('› rclone lsjson gdrive:'));
    expect(texts, containsAll(['one', 'two']));
    expect(c.read(consoleControllerProvider(id)).running, isFalse);
    // A JobType.command job settled to success.
    final jobs = c.read(jobsControllerProvider);
    expect(jobs.single.type, JobType.command);
    expect(jobs.single.status, JobStatus.success);
  });

  test('a non-zero command exit marks the job failed', () async {
    final client = _FakeClient()
      ..result = const {'result': 'boom', 'error': true};
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('cat gdrive:missing');
    await ctrl.run();
    expect(c.read(jobsControllerProvider).single.status, JobStatus.failed);
  });

  test('a blocked verb is refused without dispatching', () async {
    final client = _FakeClient();
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('config show');
    await ctrl.run();
    expect(client.calls, isEmpty);
    expect(
      c.read(consoleControllerProvider(id)).log.map((l) => l.text).join(),
      contains('Blocked'),
    );
    expect(c.read(jobsControllerProvider), isEmpty);
  });

  test('credential-dumping verbosity is refused without dispatching', () async {
    final client = _FakeClient();
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('ls gdrive: -vv');
    await ctrl.run();
    expect(client.calls, isEmpty);
    expect(
      c.read(consoleControllerProvider(id)).log.map((l) => l.text).join(),
      contains('Refused'),
    );
  });

  test('the echoed command + job row redact a secret flag value', () async {
    final client = _FakeClient();
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('copy :sftp,pass=hunter2:x local:y');
    await ctrl.run();
    final joined = c
        .read(consoleControllerProvider(id))
        .log
        .map((l) => l.text)
        .join('\n');
    expect(joined, isNot(contains('hunter2')));
    expect(joined, contains('‹redacted›'));
  });
}
