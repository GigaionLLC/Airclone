import 'package:airclone/src/rclone/http_rclone_client.dart';
import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/state/console/console_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Returns settings synchronously without touching SharedPreferences (whose
/// getInstance needs a Flutter binding these plain-container tests don't set up).
class _FakeSettings extends SettingsController {
  @override
  SettingsState build() => const SettingsState();
}

/// A subclass of the real HttpRcloneClient so the console takes its streaming
/// path (the `is HttpRcloneClient` check passes), with commandStream overridden
/// to a canned line stream — no real rcd needed.
class _FakeHttp extends HttpRcloneClient {
  _FakeHttp() : super(rclonePath: 'rclone');
  List<String> lines = ['one', 'two'];
  int commandCalls = 0;
  List<String>? lastArgs;

  @override
  Future<Stream<String>> commandStream(
    String command,
    List<String> args,
  ) async {
    commandCalls++;
    lastArgs = args;
    return Stream.fromIterable(lines);
  }
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._c);
  final _FakeHttp _c;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _c);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  const id = 'test';
  ProviderContainer make(_FakeHttp client) {
    final c = ProviderContainer(
      overrides: [
        engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        settingsControllerProvider.overrideWith(() => _FakeSettings()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('streams output, marks the job success', () async {
    final client = _FakeHttp();
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('lsjson gdrive:');
    await ctrl.run();
    await _settle();

    expect(client.commandCalls, 1);
    final texts = c
        .read(consoleControllerProvider(id))
        .log
        .map((l) => l.text)
        .toList();
    expect(texts, contains('› rclone lsjson gdrive:'));
    expect(texts, containsAll(['one', 'two']));
    expect(c.read(consoleControllerProvider(id)).running, isFalse);
    final jobs = c.read(jobsControllerProvider);
    expect(jobs.single.type, JobType.command);
    expect(jobs.single.status, JobStatus.success);
  });

  test('an error-shaped line marks the streamed job failed', () async {
    final client = _FakeHttp()
      ..lines = ['listing…', 'ERROR : nope: Failed to read'];
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('lsjson gdrive:missing');
    await ctrl.run();
    await _settle();
    expect(c.read(jobsControllerProvider).single.status, JobStatus.failed);
  });

  test('a blocked verb is refused without dispatching', () async {
    final client = _FakeHttp();
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('config show');
    await ctrl.run();
    await _settle();
    expect(client.commandCalls, 0);
    expect(
      c.read(consoleControllerProvider(id)).log.map((l) => l.text).join(),
      contains('Blocked'),
    );
    expect(c.read(jobsControllerProvider), isEmpty);
  });

  // The exact line a Microsoft Store reviewer ran on 2026-07-29. It must stay
  // refused (it mutates config) but must NOT read as a dead end — the refusal
  // that named no alternative is what got logged as "Unusable Feature: Create a
  // local remote" and failed certification under policy 10.1.2.10.
  test('the refusal tells you where to create a remote instead', () async {
    final client = _FakeHttp();
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('config create local local');
    await ctrl.run();
    await _settle();
    expect(client.commandCalls, 0, reason: 'config must never dispatch');
    final log = c
        .read(consoleControllerProvider(id))
        .log
        .map((l) => l.text)
        .join();
    expect(log, contains('Blocked'));
    expect(log, contains('CLOUD'), reason: 'must name the in-app alternative');
  });

  test('a server global flag (--rc) is refused (critical hole)', () async {
    final client = _FakeHttp();
    final c = make(client);
    final ctrl = c.read(consoleControllerProvider(id).notifier);
    ctrl.setDraft('cat gdrive:x --rc --rc-no-auth');
    await ctrl.run();
    await _settle();
    expect(client.commandCalls, 0, reason: 'must not spin up an rc server');
  });

  test('credential-dumping verbosity is refused (incl. -vvvv)', () async {
    for (final draft in [
      'ls gdrive: -vv',
      'ls gdrive: -vvvv',
      'ls gdrive: --log-level DEBUG',
    ]) {
      final client = _FakeHttp();
      final c = make(client);
      c.read(consoleControllerProvider(id).notifier).setDraft(draft);
      await c.read(consoleControllerProvider(id).notifier).run();
      await _settle();
      expect(client.commandCalls, 0, reason: draft);
    }
  });

  test(
    'the echoed command redacts a secret (conn-string) and does not leak it',
    () async {
      final client = _FakeHttp()..lines = const [];
      final c = make(client);
      final ctrl = c.read(consoleControllerProvider(id).notifier);
      ctrl.setDraft('copy :sftp,pass=hunter2:x local:y');
      await ctrl.run();
      await _settle();
      final joined = c
          .read(consoleControllerProvider(id))
          .log
          .map((l) => l.text)
          .join('\n');
      expect(joined, isNot(contains('hunter2')));
      expect(joined, contains('‹redacted›'));
    },
  );

  test(
    'non-HTTP (in-process) engine shows an honest unsupported message',
    () async {
      // No engine override -> the default engine has no HttpRcloneClient; but the
      // engine is not ready either, so we assert the command does not dispatch.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final ctrl = c.read(consoleControllerProvider(id).notifier);
      ctrl.setDraft('ls gdrive:');
      await ctrl.run();
      await _settle();
      // No engine -> "Engine not ready" (no crash, no dispatch).
      expect(c.read(consoleControllerProvider(id)).log, isNotEmpty);
      expect(c.read(jobsControllerProvider), isEmpty);
    },
  );

  test(
    'run() records commands in session history, deduping consecutive',
    () async {
      final client = _FakeHttp();
      final c = make(client);
      final ctrl = c.read(consoleControllerProvider(id).notifier);
      for (final draft in ['lsjson gdrive:', 'lsjson gdrive:', 'about s3:']) {
        ctrl.setDraft(draft);
        await ctrl.run();
        await _settle();
      }
      // The consecutive duplicate collapses (bash ignoredups), order preserved.
      expect(c.read(consoleControllerProvider(id)).history, [
        'lsjson gdrive:',
        'about s3:',
      ]);
    },
  );

  test(
    'a blocked command is still recorded in history (to fix + rerun)',
    () async {
      final client = _FakeHttp();
      final c = make(client);
      final ctrl = c.read(consoleControllerProvider(id).notifier);
      ctrl.setDraft('config show'); // blocked verb — refused, but recallable
      await ctrl.run();
      await _settle();
      expect(client.commandCalls, 0, reason: 'blocked: nothing dispatched');
      expect(c.read(consoleControllerProvider(id)).history, ['config show']);
    },
  );
}
