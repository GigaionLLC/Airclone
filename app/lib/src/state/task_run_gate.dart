import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../rclone/models/job.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'engine_controller.dart';
import 'host_platform.dart';
import 'jobs_controller.dart';

/// Why [TaskRunGate.tryClaim] said no, or that it said yes.
enum TaskClaim {
  /// The caller now owns the task's run and must [TaskRunGate.attach] the job
  /// it dispatches, or [TaskRunGate.release] if it dispatches nothing.
  claimed,

  /// This app instance is already running the task.
  runningHere,

  /// Another Airclone process (a background run, a second window, the other
  /// engine on Android) holds the task's lock.
  runningElsewhere,
}

/// One saved task may only ever have one run in flight, across every way a run
/// can start: the in-app scheduler, Run now, the photo-backup button, and every
/// headless wake (`--run-due`, `--run-task`, Android WorkManager, iOS
/// BGProcessingTask). Two overlapping copies of the same sync race each other
/// on the same destination, double the traffic, and record two outcomes for
/// one slot.
///
/// Two layers, because no single primitive covers every case:
///
/// - An exclusive OS file lock ([RandomAccessFile.lock]) on a per-task file in
///   the app's own support directory, held for the whole run. It works across
///   processes (the GUI and a headless run are separate processes on desktop),
///   and the OS drops it when the holder dies, so a crash cannot leave a task
///   locked forever.
/// - A claim on a per-task name in [IsolateNameServer]. On Linux, macOS and
///   Android the file lock is a POSIX record lock, which belongs to the
///   PROCESS: a second isolate in the same process would be granted it too.
///   Android runs exactly that case, a WorkManager engine inside the app's own
///   process next to the foreground one. The name server is process-wide, so
///   it closes that gap. A holder answers a ping on its port; a name whose
///   isolate has gone without releasing is detected by its silence and taken
///   over.
///
/// The file name comes from the task id alone, never from a path someone
/// supplied. An id made only of `[A-Za-z0-9-]` (every id the app generates) is
/// used as it is; anything else is hex-encoded behind a `_` prefix that the
/// plain form cannot start with, so two ids can never share a lock file and no
/// id can climb out of the directory.
class TaskRunLocks {
  TaskRunLocks({Future<Directory> Function()? baseDir, bool? useNameServer})
    : _baseDir = baseDir ?? getApplicationSupportDirectory,
      _useNameServer = useNameServer ?? true;

  final Future<Directory> Function() _baseDir;
  final bool _useNameServer;
  final Map<String, RandomAccessFile> _files = {};
  final Map<String, ReceivePort> _ports = {};

  /// How long a contended name gets to answer before it is presumed stale. A
  /// busy UI isolate still answers within a frame or two; two seconds is
  /// generous, and the wait only happens on the contended path.
  static const pingTimeout = Duration(seconds: 2);

  static final _plainId = RegExp(r'^[A-Za-z0-9-]{1,64}$');

  /// The lock-file base name for [taskId]. Public for the tests.
  @visibleForTesting
  static String lockKey(String taskId) => _plainId.hasMatch(taskId)
      ? taskId
      : '_${utf8.encode(taskId).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  /// Takes both layers for [taskId]. True when this caller now holds them.
  ///
  /// False only when another holder is alive. A lock directory that cannot be
  /// reached (no support directory, a read-only disk) does not block the run:
  /// the in-process layer still holds, and refusing every scheduled run because
  /// a lock file could not be created would be a worse failure than the one the
  /// lock prevents.
  Future<bool> tryAcquire(String taskId) async {
    final key = lockKey(taskId);
    if (_files.containsKey(key) || _ports.containsKey(key)) return false;
    if (_useNameServer && !await _claimName(key)) return false;
    final file = await _lockFile(key);
    if (file == _contended) {
      _releaseName(key);
      return false;
    }
    if (file is RandomAccessFile) _files[key] = file;
    return true;
  }

  /// Gives up both layers for [taskId]. Safe to call when nothing is held.
  Future<void> release(String taskId) async {
    final key = lockKey(taskId);
    final file = _files.remove(key);
    if (file != null) {
      try {
        await file.unlock();
      } catch (_) {
        // Closing below releases it too.
      }
      try {
        await file.close();
      } catch (_) {
        // Nothing left to do; the OS frees it when the process ends.
      }
    }
    _releaseName(key);
  }

  static final _contended = _Sentinel();

  /// Opens and locks the file for [key]. Returns the open file when locked,
  /// [_contended] when another process holds it, and null when the directory
  /// could not be used at all.
  Future<Object?> _lockFile(String key) async {
    RandomAccessFile? raf;
    try {
      final base = await _baseDir();
      final dir = Directory(
        '${base.path}${HostPlatform.pathSeparator}run-locks',
      );
      await dir.create(recursive: true);
      // FileMode.append creates the file without truncating it, so opening a
      // file another process has locked never disturbs it.
      raf = await File(
        '${dir.path}${HostPlatform.pathSeparator}$key.lock',
      ).open(mode: FileMode.append);
    } catch (_) {
      return null;
    }
    try {
      await raf.lock(FileLock.exclusive);
      return raf;
    } on FileSystemException {
      try {
        await raf.close();
      } catch (_) {
        // Best effort.
      }
      return _contended;
    }
  }

  Future<bool> _claimName(String key) async {
    final name = 'airclone.run.$key';
    final port = ReceivePort();
    port.listen((msg) {
      if (msg is SendPort) msg.send(true);
    });
    if (IsolateNameServer.registerPortWithName(port.sendPort, name)) {
      _ports[key] = port;
      return true;
    }
    final holder = IsolateNameServer.lookupPortByName(name);
    if (holder != null && await _answers(holder)) {
      port.close();
      return false;
    }
    // The holder is gone without releasing (its isolate ended). Take the name
    // over. Two isolates finding the same stale name in the same instant could
    // both get here; the file lock still separates them across processes, and
    // the window is the length of one ping.
    IsolateNameServer.removePortNameMapping(name);
    if (IsolateNameServer.registerPortWithName(port.sendPort, name)) {
      _ports[key] = port;
      return true;
    }
    port.close();
    return false;
  }

  void _releaseName(String key) {
    final port = _ports.remove(key);
    if (port == null) return;
    final name = 'airclone.run.$key';
    // Only remove the mapping if it is still ours.
    if (IsolateNameServer.lookupPortByName(name) == port.sendPort) {
      IsolateNameServer.removePortNameMapping(name);
    }
    port.close();
  }

  static Future<bool> _answers(SendPort holder) async {
    final reply = ReceivePort();
    try {
      holder.send(reply.sendPort);
      await reply.first.timeout(pingTimeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      reply.close();
    }
  }
}

class _Sentinel {}

final taskRunLocksProvider = Provider<TaskRunLocks>((_) => TaskRunLocks());

/// The task id → running local job mapping, and the gate every run start goes
/// through. State maps a claimed task id to the LOCAL [Job.id] it is running,
/// or to null while the claim is held but the job has not been dispatched yet.
///
/// A claim ends when the real job does: [Job.isFinished], the job removed from
/// the list, or the engine that ran it gone (a dead `rcd` takes its jobs with
/// it, and a restarted one has never heard of them). It does NOT end when a
/// supervisor gives up waiting, because the job may still be running, and
/// starting a second copy beside it is the bug this exists to prevent.
class TaskRunGate extends Notifier<Map<String, int?>> {
  /// The engine client each attached job was dispatched to, so a restart is
  /// noticed even though the new client is non-null too.
  final Map<String, RcloneClient?> _clientFor = {};

  @override
  Map<String, int?> build() {
    ref.listen<List<Job>>(jobsControllerProvider, (_, _) => _sweep());
    ref.listen(engineControllerProvider, (_, _) => _sweep());
    // Read now: a disposed ref cannot read anything.
    final locks = ref.read(taskRunLocksProvider);
    ref.onDispose(() {
      for (final id in state.keys) {
        unawaited(locks.release(id));
      }
    });
    return const {};
  }

  /// Whether [taskId] has a run in flight in this app instance.
  bool isRunning(String taskId) => state.containsKey(taskId);

  /// The local job id [taskId] is running, if it has been dispatched.
  int? jobFor(String taskId) => state[taskId];

  /// Claims [taskId] for one run. The in-process part is synchronous — the
  /// id is in [state] before the first await — so two callers in this isolate
  /// can never both pass, however their awaits interleave.
  Future<TaskClaim> tryClaim(String taskId) async {
    if (state.containsKey(taskId)) return TaskClaim.runningHere;
    state = {...state, taskId: null};
    final ok = await ref.read(taskRunLocksProvider).tryAcquire(taskId);
    if (ok) return TaskClaim.claimed;
    state = {...state}..remove(taskId);
    return TaskClaim.runningElsewhere;
  }

  /// Records that the claim on [taskId] is now running local job [jobId]. From
  /// here the claim follows that job, and is released when it ends.
  void attach(String taskId, int jobId) {
    if (!state.containsKey(taskId)) return;
    _clientFor[taskId] = ref.read(engineControllerProvider).client;
    state = {...state, taskId: jobId};
    // The job may already be terminal (a dispatch that failed fast).
    _sweep();
  }

  /// Ends the claim on [taskId]. Idempotent.
  void release(String taskId) {
    if (!state.containsKey(taskId)) return;
    _clientFor.remove(taskId);
    state = {...state}..remove(taskId);
    unawaited(ref.read(taskRunLocksProvider).release(taskId));
  }

  void _sweep() {
    if (state.isEmpty) return;
    final jobs = ref.read(jobsControllerProvider);
    final client = ref.read(engineControllerProvider).client;
    for (final entry in state.entries.toList()) {
      final jobId = entry.value;
      if (jobId == null) continue;
      Job? job;
      for (final j in jobs) {
        if (j.id == jobId) job = j;
      }
      final engineGone =
          client == null || !identical(client, _clientFor[entry.key]);
      if (job == null || job.isFinished || engineGone) release(entry.key);
    }
  }
}

final taskRunGateProvider = NotifierProvider<TaskRunGate, Map<String, int?>>(
  TaskRunGate.new,
);

/// The SnackBar text for a Run now that [TaskRunGate.tryClaim] refused.
String alreadyRunningMessage(String taskName, TaskClaim claim) =>
    claim == TaskClaim.runningElsewhere
    ? '"$taskName" is already running in another Airclone process.'
    : '"$taskName" is already running — see Transfers.';

/// The tasks-panel line for due tasks held back by a run still in flight
/// (`SchedulerStatus.skippedWhileRunning`). Empty [names] (the tasks were
/// deleted since) still reads correctly.
String skippedWhileRunningMessage(List<String> names) {
  final who = names.isEmpty
      ? 'A scheduled task'
      : names.length == 1
      ? '"${names.single}"'
      : '${names.length} scheduled tasks';
  final verb = names.length > 1 ? 'were' : 'was';
  return '$who $verb due but still running from last time — '
      'the next run starts when that one ends.';
}
