import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import 'engine_controller.dart';

/// Owns the list of transfer [Job]s and a SINGLE periodic poller that keeps
/// every running job's progress fresh.
///
/// The poller ticks once a second; for each running job that has an rclone
/// [Job.jobid] it asks `core/stats` for live bytes/total/speed and `job/status`
/// for completion. Every RC call is wrapped in try/catch so a transient engine
/// hiccup never tears the timer down. The timer is cancelled in [ref.onDispose].
class JobsController extends Notifier<List<Job>> {
  Timer? _timer;
  int _nextId = 0;

  @override
  List<Job> build() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return const [];
  }

  /// Registers a new running job and returns it. The caller fills in [jobid]
  /// later (once the kick-off RC call returns) via [update].
  Job add({
    required JobType type,
    required String source,
    required String dest,
    int total = 0,
  }) {
    final job = Job(
      id: _nextId++,
      type: type,
      source: source,
      dest: dest,
      total: total,
    );
    state = [...state, job];
    return job;
  }

  /// Patches mutable fields of the job with [id]. Unspecified fields are kept.
  void update(
    int id, {
    JobStatus? status,
    int? bytes,
    int? total,
    double? speedBps,
    String? error,
    int? jobid,
  }) {
    state = [
      for (final j in state)
        if (j.id == id)
          j.copyWith(
            status: status,
            bytes: bytes,
            total: total,
            speedBps: speedBps,
            error: error,
            jobid: jobid,
          )
        else
          j,
    ];
  }

  /// Moves the job with [id] into a terminal [status]. For a successful job we
  /// snap the progress bar to 100% by pinning bytes to total.
  void markDone(int id, JobStatus status, {String? error}) {
    state = [
      for (final j in state)
        if (j.id == id)
          j.copyWith(
            status: status,
            speedBps: 0,
            error: error,
            bytes: status == JobStatus.success && j.total > 0 ? j.total : null,
          )
        else
          j,
    ];
  }

  /// Drops a single job from the list.
  void remove(int id) {
    state = [
      for (final j in state)
        if (j.id != id) j,
    ];
  }

  /// Drops every job that has reached a terminal state.
  void clearFinished() {
    state = [
      for (final j in state)
        if (j.isRunning) j,
    ];
  }

  /// Cancels a running job: asks rclone to stop the async job, then marks it
  /// canceled locally. Safe to call even if the engine is gone.
  Future<void> stop(int id) async {
    final job = _byId(id);
    if (job == null) return;
    final client = ref.read(engineControllerProvider).client;
    final jobid = job.jobid;
    if (client != null && jobid != null) {
      try {
        await client.rpc('job/stop', {'jobid': jobid});
      } catch (_) {
        // Best-effort: the job may have already finished.
      }
    }
    markDone(id, JobStatus.canceled);
  }

  Job? _byId(int id) {
    for (final j in state) {
      if (j.id == id) return j;
    }
    return null;
  }

  /// One poll tick: refresh every running job that has a [Job.jobid].
  Future<void> _poll() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    final running = state.where((j) => j.isRunning && j.jobid != null).toList();
    if (running.isEmpty) return;

    for (final job in running) {
      final jobid = job.jobid!;

      // Live byte counters / speed for this job's group.
      try {
        final stats = await client.rpc('core/stats', {
          'group': 'airclone/$jobid',
        });
        final bytes = _asInt(stats['bytes']);
        final speed = _asDouble(stats['speed']);
        var total = _asInt(stats['totalBytes']);
        if (total <= 0) {
          final transferring = stats['transferring'];
          if (transferring is List) {
            var sum = 0;
            for (final t in transferring) {
              if (t is Map) sum += _asInt(t['size']);
            }
            if (sum > 0) total = sum;
          }
        }
        update(
          job.id,
          bytes: bytes,
          speedBps: speed,
          total: total > 0 ? total : null,
        );
      } catch (_) {
        // Stats may be unavailable momentarily; skip this field this tick.
      }

      // Completion check.
      try {
        final status = await client.rpc('job/status', {'jobid': jobid});
        final finished = status['finished'] == true;
        if (finished) {
          final success = status['success'] == true;
          final err = status['error'];
          markDone(
            job.id,
            success ? JobStatus.success : JobStatus.failed,
            error: (err is String && err.isNotEmpty) ? err : null,
          );
        }
      } catch (_) {
        // Leave the job running; we'll try again next tick.
      }
    }
  }

  static int _asInt(Object? v) => v is num ? v.toInt() : 0;
  static double _asDouble(Object? v) => v is num ? v.toDouble() : 0;
}

final jobsControllerProvider = NotifierProvider<JobsController, List<Job>>(
  JobsController.new,
);
