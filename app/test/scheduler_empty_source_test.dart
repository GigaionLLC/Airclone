import 'package:airclone/src/rclone/rclone_client.dart';
// `EnginePhase` also exists in flutter_test's binding, so this one is named.
import 'package:airclone/src/state/engine_controller.dart' as engine;
import 'package:airclone/src/state/engine_controller.dart'
    show engineControllerProvider;
import 'package:airclone/src/state/scheduler_controller.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:airclone/src/state/transfer_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The guard the delete cap cannot be.
///
/// A cap of 100 still lets a destination holding 80 files be wiped, and the
/// case that produces both — a source that vanished or emptied — is the same
/// one. So a scheduled Sync checks its source resolves like a real folder
/// before it runs, and refuses if it does not.
///
/// These drive the real [SchedulerController.tick] against a real engine
/// client, because the thing that matters is not that a helper returned true —
/// it is that **nothing was dispatched**.
class _FakeClient implements RcloneClient {
  _FakeClient({this.listing, this.listThrows = false});

  /// What `operations/list` returns for the source, or null for "no list key".
  final List<Object?>? listing;
  final bool listThrows;

  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add(method);
    if (method == 'operations/list') {
      if (listThrows) throw Exception('remote is not answering');
      return {'list': listing};
    }
    return {};
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeEngine extends engine.EngineController {
  _FakeEngine(this._client);
  final RcloneClient _client;
  @override
  engine.EngineUi build() =>
      engine.EngineUi(phase: engine.EnginePhase.ready, client: _client);
}

/// Records dispatches instead of making them, so "did anything run?" is a
/// direct assertion rather than an inference from side effects.
class _SpyTransfers implements TransferService {
  final dispatched = <String>[];

  @override
  Future<int> transferAdvancedRaw({
    required String srcFs,
    required String dstFs,
    required String srcLabel,
    required String dstLabel,
    required TransferOptions options,
    bool forceResync = false,
  }) async {
    dispatched.add('${options.mode.name} $srcFs -> $dstFs');
    return 1;
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FixedTasks extends TasksController {
  _FixedTasks(this._initial);
  final List<TransferTask> _initial;
  @override
  List<TransferTask> build() => _initial;
}

const _hourly = TaskSchedule(kind: ScheduleKind.interval, intervalMinutes: 60);

TransferTask _task({TransferMode mode = TransferMode.sync}) => TransferTask(
  id: '1',
  name: 'photos to backup',
  srcFs: 'photos:',
  srcLabel: 'photos:',
  dstFs: 'backup:',
  dstLabel: 'backup:',
  options: TransferOptions(mode: mode, baselineEstablished: true),
  schedule: _hourly,
  lastRun: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Runs one tick and settles the unawaited dispatch behind it.
  Future<({_SpyTransfers svc, ProviderContainer c})> tickOnce({
    required _FakeClient client,
    TransferMode mode = TransferMode.sync,
  }) async {
    final svc = _SpyTransfers();
    final c = ProviderContainer(
      overrides: [
        tasksProvider.overrideWith(() => _FixedTasks([_task(mode: mode)])),
        engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        transferServiceProvider.overrideWithValue(svc),
      ],
    );
    addTearDown(c.dispose);
    c.read(schedulerProvider.notifier).tick();
    // The dispatch is fire-and-forget; give the source check and everything
    // behind it a chance to resolve before asserting.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return (svc: svc, c: c);
  }

  TaskRunRecord? lastRun(ProviderContainer c) {
    final h = c.read(tasksProvider).single.history;
    return h.isEmpty ? null : h.first;
  }

  test('an empty source refuses the run and dispatches nothing', () async {
    final r = await tickOnce(client: _FakeClient(listing: const []));

    expect(
      r.svc.dispatched,
      isEmpty,
      reason: 'a Sync from an empty source deletes the whole destination',
    );
    // Refused is not the same as "did not happen": it lands in the history the
    // Automation section shows, or this is the silent stop the whole feature
    // exists to prevent.
    expect(lastRun(r.c)?.ok, isFalse);
    expect(lastRun(r.c)?.error, kEmptySourceRefusal);
  });

  test('an unreadable source is refused too, not run on hope', () async {
    // A human watching a preview can be told "could not read that" and decide.
    // A timer at 3am cannot, so unreadable counts as unsafe.
    final r = await tickOnce(client: _FakeClient(listThrows: true));
    expect(r.svc.dispatched, isEmpty);
    expect(lastRun(r.c)?.error, kEmptySourceRefusal);
  });

  test('a source with files runs normally', () async {
    final r = await tickOnce(
      client: _FakeClient(
        listing: const [
          {'Name': 'a.jpg'},
        ],
      ),
    );
    expect(r.svc.dispatched, ['sync photos: -> backup:']);
  });

  test('Copy from an empty source still runs — it deletes nothing', () async {
    // Refusing here would stop a legitimate no-op and teach the user that the
    // guard fires for no reason.
    final r = await tickOnce(
      client: _FakeClient(listing: const []),
      mode: TransferMode.copy,
    );
    expect(r.svc.dispatched, ['copy photos: -> backup:']);
  });

  test('Move and two-way sync are likewise not gated on this', () async {
    for (final m in [TransferMode.move, TransferMode.bisync]) {
      final r = await tickOnce(
        client: _FakeClient(listing: const []),
        mode: m,
      );
      expect(r.svc.dispatched, hasLength(1), reason: '$m');
    }
  });

  test('the refusal reads as a sentence, not a code', () {
    // It is read in a list of run outcomes by someone working out why last
    // night did nothing.
    expect(kEmptySourceRefusal, contains('source'));
    expect(kEmptySourceRefusal, contains('delete'));
    expect(kEmptySourceRefusal.endsWith('.'), isTrue);
  });
}
