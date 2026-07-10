import 'package:airclone/src/headless/headless_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-parts coverage for the headless entrypoint: CLI arg parsing, the
/// headless-invocation predicate that gates `main()` (and mirrors the Windows
/// runner's own scan), and the exit-code decision table. No engine or process
/// is spawned — the runtime path lives behind [runHeadless] and is exercised
/// end-to-end, not here.
void main() {
  group('isHeadlessInvocation', () {
    test('true for --run-due', () {
      expect(isHeadlessInvocation(['--run-due']), isTrue);
    });

    test('true for --run-task with an id', () {
      expect(isHeadlessInvocation(['--run-task', 'abc']), isTrue);
    });

    test('true for a bare --run-task (id validated later → exit 2)', () {
      expect(isHeadlessInvocation(['--run-task']), isTrue);
    });

    test('true for the --run-task=<id> joined form', () {
      expect(isHeadlessInvocation(['--run-task=abc']), isTrue);
    });

    test('false for a normal launch (no headless flags)', () {
      expect(isHeadlessInvocation([]), isFalse);
      expect(isHeadlessInvocation(['--enable-dart-profiling']), isFalse);
      expect(isHeadlessInvocation(['--timeout-minutes', '30']), isFalse);
    });
  });

  group('parseHeadlessArgs — task id', () {
    test('extracts the value after --run-task', () {
      final r = parseHeadlessArgs(['--run-task', 'nightly-7x']);
      expect(r.taskId, 'nightly-7x');
      expect(r.runDue, isFalse);
    });

    test('extracts the value from the --run-task=<id> joined form', () {
      expect(parseHeadlessArgs(['--run-task=xy-1']).taskId, 'xy-1');
    });

    test('a bare --run-task with no value yields a null id', () {
      expect(parseHeadlessArgs(['--run-task']).taskId, isNull);
    });
  });

  group('parseHeadlessArgs — run-due flag', () {
    test('detects --run-due and leaves taskId null', () {
      final r = parseHeadlessArgs(['--run-due']);
      expect(r.runDue, isTrue);
      expect(r.taskId, isNull);
    });
  });

  group('parseHeadlessArgs — timeout', () {
    test('defaults to 360 minutes when absent', () {
      expect(
        parseHeadlessArgs(['--run-due']).timeout,
        const Duration(minutes: kDefaultTimeoutMinutes),
      );
    });

    test('parses the space-separated form', () {
      expect(
        parseHeadlessArgs(['--run-due', '--timeout-minutes', '30']).timeout,
        const Duration(minutes: 30),
      );
    });

    test('parses the --timeout-minutes=<n> joined form', () {
      expect(
        parseHeadlessArgs(['--timeout-minutes=5', '--run-due']).timeout,
        const Duration(minutes: 5),
      );
    });

    test('falls back to the default on a non-numeric value', () {
      expect(
        parseHeadlessArgs(['--timeout-minutes', 'oops']).timeout,
        const Duration(minutes: kDefaultTimeoutMinutes),
      );
    });

    test('falls back to the default on a non-positive value', () {
      expect(
        parseHeadlessArgs(['--timeout-minutes', '0']).timeout,
        const Duration(minutes: kDefaultTimeoutMinutes),
      );
      expect(
        parseHeadlessArgs(['--timeout-minutes', '-4']).timeout,
        const Duration(minutes: kDefaultTimeoutMinutes),
      );
    });
  });

  group('parseHeadlessArgs — unknown-arg tolerance', () {
    test('ignores flags the toolchain / OS scheduler may inject', () {
      final r = parseHeadlessArgs([
        '--enable-dart-profiling',
        '--run-task',
        't-42',
        '--observatory-port',
        '0',
      ]);
      expect(r.taskId, 't-42');
      expect(r.runDue, isFalse);
      expect(r.timeout, const Duration(minutes: kDefaultTimeoutMinutes));
    });
  });

  group('exitCodeForRun — decision table', () {
    test('empty (nothing due) → 0', () {
      expect(exitCodeForRun(const []), kExitOk);
    });

    test('every task ok → 0', () {
      expect(exitCodeForRun(const [true, true, true]), kExitOk);
    });

    test('any task failed → 1', () {
      expect(exitCodeForRun(const [true, false, true]), kExitFailed);
      expect(exitCodeForRun(const [false]), kExitFailed);
    });

    test('a timeout forces 1 even when the completed tasks were ok', () {
      expect(exitCodeForRun(const [true], timedOut: true), kExitFailed);
      expect(exitCodeForRun(const [], timedOut: true), kExitFailed);
    });

    test('the three exit-code constants are stable (0 / 1 / 2)', () {
      expect(kExitOk, 0);
      expect(kExitFailed, 1);
      expect(kExitCannotStart, 2);
    });
  });

  group('HeadlessTaskResult.summaryLine', () {
    test('a successful run tags [OK] and shows bytes when known', () {
      const r = HeadlessTaskResult(
        taskId: 't1',
        name: 'Nightly backup',
        ok: true,
        bytes: 2048,
      );
      expect(r.summaryLine, startsWith('[OK'));
      expect(r.summaryLine, contains('Nightly backup'));
      expect(r.summaryLine, contains('t1'));
      expect(r.summaryLine, contains('2048'));
    });

    test('a failed run tags [FAIL] and carries the error text', () {
      const r = HeadlessTaskResult(
        taskId: 't2',
        name: 'Docs sync',
        ok: false,
        error: 'boom',
      );
      expect(r.summaryLine, startsWith('[FAIL'));
      expect(r.summaryLine, contains('boom'));
    });

    test('a failure with no error text still reads cleanly', () {
      const r = HeadlessTaskResult(taskId: 't3', name: 'x', ok: false);
      expect(r.summaryLine, contains('unknown error'));
    });
  });
}
