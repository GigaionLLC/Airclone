/// Two copies of Airclone must not kill each other's engine.
///
/// The previous version used ONE shared marker file holding one PID, and killed
/// whatever was in it on every start. Launching a second Airclone therefore
/// killed the first one's live `rcd` — the first window simply lost its engine —
/// and then overwrote the marker, so the first one's clean exit deleted a record
/// that by then pointed at the second one's child, leaving that one unreapable.
///
/// The rule now: reap only while holding an exclusive lock, which is only
/// available when no other instance is running.
///
/// The POLICY is what these tests pin, with the lock injected. They cannot pin
/// it through the real lock, because POSIX advisory locks belong to the PROCESS:
/// opening one file twice in a single process and locking both SUCCEEDS on
/// Linux and macOS, while on Windows — where locks are per-handle — it
/// conflicts. An earlier version of this file simulated the sibling in-process
/// and duly passed on Windows and failed on Linux CI. Cross-process exclusion is
/// a platform guarantee; what is worth testing is what the code does once told
/// a sibling is alive.
library;

import 'dart:io';

import 'package:airclone/src/rclone/http_rclone_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late File lockFile;
  late List<int> killed;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('airclone_reap');
    lockFile = File('${tmp.path}${Platform.pathSeparator}airclone_rcd.lock');
    killed = [];
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      try {
        await tmp.delete(recursive: true);
      } on FileSystemException {
        // Windows keeps a handle on a still-locked file; the OS reclaims it.
      }
    }
  });

  File marker(int ownerPid, int rcdPid) {
    final f = File(
      '${tmp.path}${Platform.pathSeparator}airclone_rcd_$ownerPid.pid',
    );
    f.writeAsStringSync('$rcdPid');
    return f;
  }

  /// [siblingRunning] stands in for another Airclone holding the lock.
  Future<RandomAccessFile?> reap({
    int ownPid = 4242,
    bool siblingRunning = false,
  }) => reapOrphanedRcd(
    tempDir: tmp,
    lockFile: lockFile,
    ownPid: ownPid,
    kill: killed.add,
    acquireLock: siblingRunning ? (_) => null : null,
  );

  test('an orphan from a crashed previous run is reaped', () async {
    final m = marker(1111, 9001);
    final lock = await reap();
    expect(lock, isNotNull, reason: 'nothing else is running, so we own it');
    expect(killed, [9001]);
    expect(m.existsSync(), isFalse, reason: 'the marker is cleared too');
    lock!
      ..unlockSync()
      ..closeSync();
  });

  test('every orphan is reaped, not just the most recent', () async {
    // With the lock held, nobody else is alive to own any of these.
    marker(1111, 9001);
    marker(2222, 9002);
    marker(3333, 9003);
    final lock = await reap();
    expect(killed..sort(), [9001, 9002, 9003]);
    lock!
      ..unlockSync()
      ..closeSync();
  });

  test('NOTHING is reaped while another instance holds the lock', () async {
    final m = marker(1111, 9001);

    final lock = await reap(siblingRunning: true);

    expect(lock, isNull, reason: 'we must not claim single-instance ownership');
    // The whole point: that PID is a live sibling's engine.
    expect(killed, isEmpty);
    expect(
      m.existsSync(),
      isTrue,
      reason: 'the sibling still needs its marker',
    );
  });

  test('once the sibling exits, the next launch reaps what it left', () async {
    marker(1111, 9001);
    expect(await reap(siblingRunning: true), isNull);
    expect(killed, isEmpty);

    final lock = await reap();
    expect(lock, isNotNull);
    expect(killed, [9001]);
    lock!
      ..unlockSync()
      ..closeSync();
  });

  test('the real lock can be taken and released', () async {
    // The mechanism, as far as one process can check it: a real exclusive lock
    // is acquired and handed back, and releasing it lets the next call take it.
    // Whether two PROCESSES exclude each other is the platform's guarantee, not
    // something this can demonstrate.
    final first = await reap();
    expect(first, isNotNull);
    first!
      ..unlockSync()
      ..closeSync();
    final second = await reap();
    expect(second, isNotNull);
    second!
      ..unlockSync()
      ..closeSync();
  });

  test('our own marker is never killed', () async {
    // Defends against reaping the engine we are about to use.
    marker(4242, 9999);
    final lock = await reap(ownPid: 9999);
    expect(killed, isEmpty);
    lock!
      ..unlockSync()
      ..closeSync();
  });

  test('unrelated files in temp are left alone', () async {
    final other = File('${tmp.path}${Platform.pathSeparator}something.pid')
      ..writeAsStringSync('1234');
    final rclone = File('${tmp.path}${Platform.pathSeparator}rclone.pid')
      ..writeAsStringSync('5678');
    final lock = await reap();
    expect(killed, isEmpty, reason: 'never a broad name match');
    expect(other.existsSync(), isTrue);
    expect(rclone.existsSync(), isTrue);
    lock!
      ..unlockSync()
      ..closeSync();
  });

  test('a marker with junk in it is cleaned up, not acted on', () async {
    final m = marker(1111, 0)..writeAsStringSync('not-a-pid');
    final lock = await reap();
    expect(killed, isEmpty);
    expect(m.existsSync(), isFalse);
    lock!
      ..unlockSync()
      ..closeSync();
  });
}
