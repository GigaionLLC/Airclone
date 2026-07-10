import 'dart:convert';

import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/scheduler_controller.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:airclone/src/state/transfer_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:shared_preferences/shared_preferences.dart';

/// Generous settle for the persistence chains (build→_load, or _load→_persist),
/// which span two SharedPreferences round-trips.
Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 20));

/// A fixed in-memory task list so a controller can be driven without waiting on
/// SharedPreferences (mirrors scheduler_tick_test's double). `recordRun` is
/// inherited and mutates [state] normally; its best-effort persist is a no-op.
class _FixedTasks extends TasksController {
  _FixedTasks(this._initial);
  final List<TransferTask> _initial;
  @override
  List<TransferTask> build() => _initial;
}

/// Minimal fake: the dispatch call returns a jobid; `job/status` reports the run
/// finished-with-error (the outcome we assert propagates into history).
class _FailingClient implements RcloneClient {
  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'job/status') {
      return const {'finished': true, 'success': false, 'error': 'boom'};
    }
    if (method == 'core/stats') return const {};
    return const {'jobid': 7}; // dispatch (sync/copy etc.)
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

TransferTask _task({
  String id = 't1',
  List<TaskRunRecord> history = const [],
}) => TransferTask(
  id: id,
  name: id,
  srcFs: 'a:',
  srcLabel: 'a:',
  dstFs: 'b:',
  dstLabel: 'b:',
  options: const TransferOptions(),
  history: history,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('stable id', () {
    test('legacy JSON without an id is back-filled with a fresh id', () {
      final legacy = _task().toJson()..remove('id');
      final t = TransferTask.fromJson(legacy);
      expect(t.id, isNotEmpty);
    });

    test('a present id round-trips unchanged (not re-minted on decode)', () {
      final t = _task(id: 'stable-123');
      expect(TransferTask.fromJson(t.toJson()).id, 'stable-123');
      // Decode-encode-decode again to prove the value is genuinely stable.
      final round = TransferTask.fromJson(
        TransferTask.fromJson(t.toJson()).toJson(),
      );
      expect(round.id, 'stable-123');
    });

    test('newId mints distinct, non-empty ids', () {
      final a = TransferTask.newId();
      final b = TransferTask.newId();
      expect(a, isNotEmpty);
      expect(a, isNot(b));
    });

    test(
      '_load persists the back-filled id so it survives a restart',
      () async {
        // Seed a legacy payload (no id) straight into prefs.
        final legacy = _task().toJson()..remove('id');
        SharedPreferences.setMockInitialValues({
          'transfer_tasks': jsonEncode([legacy]),
        });

        final c1 = ProviderContainer();
        c1.read(tasksProvider); // build() → _load() back-fills + persists
        await _pump();
        final id1 = c1.read(tasksProvider).single.id;
        expect(id1, isNotEmpty);
        c1.dispose();

        // A fresh container reloads the SAME id (persisted), not a new mint.
        final c2 = ProviderContainer();
        addTearDown(c2.dispose);
        c2.read(tasksProvider);
        await _pump();
        expect(c2.read(tasksProvider).single.id, id1);
      },
    );
  });

  group('TaskRunRecord JSON', () {
    test('round-trips every field', () {
      final r = TaskRunRecord(
        at: DateTime(2026, 7, 9, 10, 30),
        ok: false,
        error: 'nope',
        duration: const Duration(seconds: 12, milliseconds: 500),
        bytes: 4096,
      );
      expect(TaskRunRecord.fromJson(r.toJson()), r);
    });

    test('a clean run omits defaults yet still round-trips', () {
      final r = TaskRunRecord(at: DateTime(2026, 7, 9), ok: true);
      final j = r.toJson();
      expect(j.containsKey('error'), isFalse);
      expect(j.containsKey('durationMs'), isFalse);
      expect(j.containsKey('bytes'), isFalse);
      expect(TaskRunRecord.fromJson(j), r);
    });
  });

  group('recordRun', () {
    test('prepends newest-first and caps at 10', () {
      final c = ProviderContainer(
        overrides: [
          tasksProvider.overrideWith(() => _FixedTasks([_task()])),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(tasksProvider.notifier);
      for (var i = 0; i < 12; i++) {
        n.recordRun(
          't1',
          TaskRunRecord(
            at: DateTime(2026, 1, 1).add(Duration(minutes: i)),
            ok: true,
          ),
        );
      }
      final h = c.read(tasksProvider).single.history;
      expect(h.length, 10); // capped at the 10 most recent
      // Newest (minute 11) is first; the two oldest (0, 1) were dropped.
      expect(h.first.at, DateTime(2026, 1, 1, 0, 11));
      expect(h.last.at, DateTime(2026, 1, 1, 0, 2));
    });

    test('is a no-op for an unknown id', () {
      final c = ProviderContainer(
        overrides: [
          tasksProvider.overrideWith(() => _FixedTasks([_task()])),
        ],
      );
      addTearDown(c.dispose);
      c
          .read(tasksProvider.notifier)
          .recordRun('nope', TaskRunRecord(at: DateTime(2026, 1, 1), ok: true));
      expect(c.read(tasksProvider).single.history, isEmpty);
    });

    test('persists across a restart', () async {
      final c1 = ProviderContainer();
      c1.read(tasksProvider.notifier); // build → _load (empty prefs)
      await _pump(); // let _load settle so it can't clobber our writes
      c1.read(tasksProvider.notifier).add(_task(id: 'p1'));
      await _pump();
      c1
          .read(tasksProvider.notifier)
          .recordRun(
            'p1',
            TaskRunRecord(at: DateTime(2026, 5, 5), ok: true, bytes: 10),
          );
      await _pump();
      final raw = (await SharedPreferences.getInstance()).getString(
        'transfer_tasks',
      );
      expect(raw, contains('history'));
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(tasksProvider);
      await _pump();
      final t = c2.read(tasksProvider).firstWhere((t) => t.id == 'p1');
      expect(t.history.single.ok, isTrue);
      expect(t.history.single.bytes, 10);
    });
  });

  group('scheduler outcome path (recordRunOutcome)', () {
    test('a job that finishes with an error lands a failed record', () async {
      final client = _FailingClient();
      final c = ProviderContainer(
        overrides: [
          engineControllerProvider.overrideWith(() => _FakeEngine(client)),
          tasksProvider.overrideWith(() => _FixedTasks([_task(id: 't1')])),
        ],
      );
      addTearDown(c.dispose);

      // Dispatch exactly as SchedulerController._runAndRecord does, then
      // supervise the outcome with a fast poll so the test stays deterministic.
      final jobId = await c
          .read(transferServiceProvider)
          .transferAdvancedRaw(
            srcFs: 'a:',
            dstFs: 'b:',
            srcLabel: 'a:',
            dstLabel: 'b:',
            options: const TransferOptions(),
          );
      await recordRunOutcome(
        readClient: () => client,
        tasks: c.read(tasksProvider.notifier),
        readJobs: () => c.read(jobsControllerProvider),
        taskId: 't1',
        jobId: jobId,
        pollInterval: const Duration(milliseconds: 1),
      );

      final h = c.read(tasksProvider).single.history;
      expect(h, hasLength(1));
      expect(h.single.ok, isFalse);
      expect(h.single.error, 'boom');
    });

    test('a dispatch failure (engine down) records a failed run', () async {
      // No engine override → client == null, so the dispatch fails immediately
      // and the supervisor must record from that terminal state (no jobid ever
      // assigned, so it never polls job/status).
      final c = ProviderContainer(
        overrides: [
          tasksProvider.overrideWith(() => _FixedTasks([_task(id: 't2')])),
        ],
      );
      addTearDown(c.dispose);

      final jobId = await c
          .read(transferServiceProvider)
          .transferAdvancedRaw(
            srcFs: 'a:',
            dstFs: 'b:',
            srcLabel: 'a:',
            dstLabel: 'b:',
            options: const TransferOptions(),
          );
      await recordRunOutcome(
        readClient: () => null,
        tasks: c.read(tasksProvider.notifier),
        readJobs: () => c.read(jobsControllerProvider),
        taskId: 't2',
        jobId: jobId,
        pollInterval: const Duration(milliseconds: 1),
      );

      final h = c.read(tasksProvider).single.history;
      expect(h.single.ok, isFalse);
      expect(h.single.error, 'Engine not ready');
    });
  });
}
