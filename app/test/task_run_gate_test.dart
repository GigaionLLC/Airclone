import 'dart:io';

import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/task_run_gate.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Answers every call with an empty map: no job ever reports finished, so a
/// job's state is driven only by what the test does to the jobs list.
class _QuietClient implements RcloneClient {
  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._client);
  final RcloneClient? _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);

  void die() => state = const EngineUi(phase: EnginePhase.ready);
}

/// The real controller without its 1 s engine poll, so add/markDone/remove
/// drive the list directly.
class _StillJobs extends JobsController {
  @override
  List<Job> build() => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('airclone-locks-'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  TaskRunLocks locksIn(Directory d, {bool useNameServer = false}) =>
      TaskRunLocks(baseDir: () async => d, useNameServer: useNameServer);

  group('TaskRunLocks.lockKey', () {
    test('an app-generated id is used as it is', () {
      expect(TaskRunLocks.lockKey('1729-abc-DEF'), '1729-abc-DEF');
    });

    test('anything else is hex behind a prefix, never a path', () {
      final k = TaskRunLocks.lockKey('../../etc/passwd');
      expect(k, startsWith('_'));
      expect(k, matches(RegExp(r'^_[0-9a-f]+$')));
      expect(k.contains('/'), isFalse);
      expect(k.contains(r'\'), isFalse);
      expect(k.contains('.'), isFalse);
    });

    test('two different ids never share a key', () {
      expect(TaskRunLocks.lockKey('a b'), isNot(TaskRunLocks.lockKey('a_b')));
      // A plain id cannot collide with an encoded one: the encoded form starts
      // with `_`, which the plain alphabet does not contain.
      expect(TaskRunLocks.lockKey('_61'), isNot('_61'));
    });
  });

  group('TaskRunLocks with two holders', () {
    test('the lock file lives in <support>/run-locks', () async {
      final a = locksIn(tmp);
      expect(await a.tryAcquire('t1'), isTrue);
      expect(
        File(
          '${tmp.path}${Platform.pathSeparator}run-locks'
          '${Platform.pathSeparator}t1.lock',
        ).existsSync(),
        isTrue,
      );
      await a.release('t1');
    });

    test('one holder cannot take the same task twice', () async {
      final a = locksIn(tmp);
      expect(await a.tryAcquire('t1'), isTrue);
      expect(await a.tryAcquire('t1'), isFalse);
      // A different task is independent.
      expect(await a.tryAcquire('t2'), isTrue);
      await a.release('t1');
      expect(await a.tryAcquire('t1'), isTrue);
      await a.release('t1');
      await a.release('t2');
    });

    test(
      'a second holder in this process is refused, then gets it on release',
      () async {
        // The in-process case Android runs: a WorkManager engine beside the
        // foreground one. The name-server layer is what separates them.
        final a = locksIn(tmp, useNameServer: true);
        final b = locksIn(tmp, useNameServer: true);
        expect(await a.tryAcquire('t1'), isTrue);
        expect(await b.tryAcquire('t1'), isFalse);
        await a.release('t1');
        expect(await b.tryAcquire('t1'), isTrue);
        expect(await a.tryAcquire('t1'), isFalse);
        await b.release('t1');
      },
    );

    test(
      'a holder in another process is refused, then gets it on release',
      () async {
        // Hold the lock from a separate process with the same OS primitive
        // (an fcntl record lock, what RandomAccessFile.lock uses on POSIX).
        final dir = Directory('${tmp.path}/run-locks')..createSync();
        final path = '${dir.path}/t1.lock';
        File(path).createSync();
        final holder = await Process.start('python3', [
          '-I',
          '-c',
          'import fcntl,sys\n'
              'f=open(sys.argv[1],"a")\n'
              'fcntl.lockf(f,fcntl.LOCK_EX)\n'
              'print("held",flush=True)\n'
              'sys.stdin.read()\n',
          path,
        ]);
        addTearDown(holder.kill);
        final ready = holder.stdout
            .transform(const SystemEncoding().decoder)
            .firstWhere((s) => s.contains('held'));
        await ready.timeout(const Duration(seconds: 10));

        final b = locksIn(tmp);
        expect(await b.tryAcquire('t1'), isFalse);

        // The OS drops the lock when its holder ends, crash or not.
        await holder.stdin.close();
        await holder.exitCode.timeout(const Duration(seconds: 10));
        expect(await b.tryAcquire('t1'), isTrue);
        await b.release('t1');
      },
      skip: Platform.isLinux || Platform.isMacOS
          ? false
          : 'needs python3 and POSIX record locks',
    );

    test('an unusable lock directory does not block the run', () async {
      final locks = TaskRunLocks(
        baseDir: () async => throw const FileSystemException('no support dir'),
      );
      expect(await locks.tryAcquire('t1'), isTrue);
      // ...and the in-process layer still holds.
      expect(await locks.tryAcquire('t1'), isFalse);
      await locks.release('t1');
    });
  });

  group('TaskRunGate', () {
    late ProviderContainer c;
    late _FakeEngine engine;

    setUp(() {
      c = ProviderContainer(
        overrides: [
          engineControllerProvider.overrideWith(
            () => engine = _FakeEngine(_QuietClient()),
          ),
          jobsControllerProvider.overrideWith(_StillJobs.new),
          taskRunLocksProvider.overrideWithValue(locksIn(tmp)),
        ],
      );
      addTearDown(c.dispose);
    });

    TaskRunGate gate() => c.read(taskRunGateProvider.notifier);
    JobsController jobs() => c.read(jobsControllerProvider.notifier);
    Job newJob() => jobs().add(type: JobType.sync, source: 'a:', dest: 'b:');

    test(
      'a second claim while the first runs is refused as runningHere',
      () async {
        expect(await gate().tryClaim('t1'), TaskClaim.claimed);
        expect(await gate().tryClaim('t1'), TaskClaim.runningHere);
        expect(gate().isRunning('t1'), isTrue);
      },
    );

    test('two claims racing in one isolate: exactly one wins', () async {
      final results = await Future.wait([
        gate().tryClaim('t1'),
        gate().tryClaim('t1'),
      ]);
      expect(results.where((r) => r == TaskClaim.claimed), hasLength(1));
      expect(results, contains(TaskClaim.runningHere));
    });

    test('the claim follows the attached job and ends when it ends', () async {
      expect(await gate().tryClaim('t1'), TaskClaim.claimed);
      final job = newJob();
      gate().attach('t1', job.id);
      expect(gate().jobFor('t1'), job.id);

      // Still running: Run now is refused.
      expect(await gate().tryClaim('t1'), TaskClaim.runningHere);

      jobs().markDone(job.id, JobStatus.success);
      expect(gate().isRunning('t1'), isFalse);
      // The lock was released too, so the next run can claim it.
      await Future<void>.delayed(Duration.zero);
      expect(await gate().tryClaim('t1'), TaskClaim.claimed);
    });

    test('a removed job releases its claim', () async {
      await gate().tryClaim('t1');
      final job = newJob();
      gate().attach('t1', job.id);
      jobs().remove(job.id);
      expect(gate().isRunning('t1'), isFalse);
    });

    test('a dead engine releases its claims', () async {
      await gate().tryClaim('t1');
      final job = newJob();
      gate().attach('t1', job.id);
      engine.die();
      expect(gate().isRunning('t1'), isFalse);
    });

    test('attaching an already-finished job releases at once', () async {
      await gate().tryClaim('t1');
      final job = newJob();
      jobs().markDone(job.id, JobStatus.failed, error: 'Engine not ready');
      gate().attach('t1', job.id);
      expect(gate().isRunning('t1'), isFalse);
    });

    test('a claim held elsewhere is refused as runningElsewhere', () async {
      final other = locksIn(tmp, useNameServer: true);
      final mine = ProviderContainer(
        overrides: [
          engineControllerProvider.overrideWith(
            () => _FakeEngine(_QuietClient()),
          ),
          jobsControllerProvider.overrideWith(_StillJobs.new),
          taskRunLocksProvider.overrideWithValue(
            locksIn(tmp, useNameServer: true),
          ),
        ],
      );
      addTearDown(mine.dispose);
      expect(await other.tryAcquire('t1'), isTrue);
      final g = mine.read(taskRunGateProvider.notifier);
      expect(await g.tryClaim('t1'), TaskClaim.runningElsewhere);
      // A refused claim leaves nothing behind.
      expect(g.isRunning('t1'), isFalse);
      await other.release('t1');
      expect(await g.tryClaim('t1'), TaskClaim.claimed);
      g.release('t1');
    });
  });

  group('messages', () {
    test('Run now on a running task', () {
      expect(
        alreadyRunningMessage('Photos', TaskClaim.runningHere),
        contains('already running'),
      );
      expect(
        alreadyRunningMessage('Photos', TaskClaim.runningElsewhere),
        contains('another Airclone process'),
      );
    });

    test('the skipped-while-running line', () {
      expect(skippedWhileRunningMessage(['A']), startsWith('"A" was due'));
      expect(skippedWhileRunningMessage(['A', 'B']), startsWith('2 scheduled'));
      expect(skippedWhileRunningMessage(['A', 'B']), contains('were due'));
      expect(skippedWhileRunningMessage([]), startsWith('A scheduled task'));
    });
  });
}
