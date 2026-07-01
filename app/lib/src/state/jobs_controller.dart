import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/job.dart';
import '../rclone/models/transfer_item.dart';
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

  /// Dispatch closures for jobs that are [JobStatus.queued], awaiting a free
  /// transfer slot. Keyed by the local job id so a cancel can drop them.
  final List<({int jobId, Future<void> Function() run})> _pending = [];

  @override
  List<Job> build() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return const [];
  }

  /// Registers a new job and returns it. Defaults to [JobStatus.running] for
  /// callers that dispatch immediately; the transfer queue creates jobs as
  /// [JobStatus.queued] and dispatches them via [enqueue]. The caller fills in
  /// [jobid] later (once the kick-off RC call returns) via [update].
  Job add({
    required JobType type,
    required String source,
    required String dest,
    int total = 0,
    JobStatus status = JobStatus.running,
  }) {
    final job = Job(
      id: _nextId++,
      type: type,
      source: source,
      dest: dest,
      total: total,
      status: status,
    );
    state = [...state, job];
    return job;
  }

  /// Queues a transfer's dispatch [run] closure for the job with [jobId]. The
  /// closure is invoked (which sets the rclone jobid or marks the job failed)
  /// as soon as a slot is free under the configured concurrency limit.
  void enqueue(int jobId, Future<void> Function() run) {
    _pending.add((jobId: jobId, run: run));
    _pump();
  }

  /// Number of jobs currently dispatched (occupying a transfer slot).
  int get _runningCount =>
      state.where((j) => j.status == JobStatus.running).length;

  /// Public hook to re-evaluate the queue (e.g. after the limit is raised).
  void pumpQueue() => _pump();

  /// Start as many queued dispatches as the concurrency limit allows. A limit
  /// of `0` means unlimited (dispatch everything immediately).
  void _pump() {
    final limit = ref.read(transferConcurrencyProvider);
    while (_pending.isNotEmpty && (limit <= 0 || _runningCount < limit)) {
      final next = _pending.removeAt(0);
      // Claim the slot before the async dispatch so the count is accurate.
      update(next.jobId, status: JobStatus.running);
      // Fire-and-forget: the closure sets jobid or marks the job terminal.
      unawaited(next.run());
    }
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
    String? rcMethod,
    Map<String, dynamic>? rcParams,
    List<TransferItem>? transferring,
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
            rcMethod: rcMethod,
            rcParams: rcParams,
            transferring: transferring,
          )
        else
          j,
    ];
  }

  /// Moves the job with [id] into a terminal [status]. For a successful job we
  /// snap the progress bar to 100% by pinning bytes to total. Freeing a slot
  /// pumps the queue so the next pending transfer can start.
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
    _pump();
  }

  /// Drops a single job from the list (also un-queues it if pending).
  void remove(int id) {
    _pending.removeWhere((p) => p.jobId == id);
    state = [
      for (final j in state)
        if (j.id != id) j,
    ];
  }

  /// Drops every job that has reached a terminal state.
  void clearFinished() {
    state = [
      for (final j in state)
        if (j.isActive) j,
    ];
  }

  /// Cancels a running or queued job: drops it from the pending queue, asks
  /// rclone to stop the async job if it was dispatched, then marks it canceled
  /// locally. Safe to call even if the engine is gone.
  Future<void> stop(int id) async {
    final job = _byId(id);
    if (job == null) return;
    // If it never left the queue, just remove the pending dispatch.
    _pending.removeWhere((p) => p.jobId == id);
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
        final items = TransferItem.listFrom(stats['transferring']);
        var total = _asInt(stats['totalBytes']);
        if (total <= 0 && items.isNotEmpty) {
          final sum = items.fold<int>(0, (s, t) => s + t.size);
          if (sum > 0) total = sum;
        }
        update(
          job.id,
          bytes: bytes,
          speedBps: speed,
          total: total > 0 ? total : null,
          transferring: items,
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

/// Maximum number of transfers allowed to run at once. `0` means unlimited
/// (every transfer dispatches immediately — the historical behavior). Persisted.
class TransferConcurrency extends Notifier<int> {
  static const _key = 'transfer_concurrency';

  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getInt(_key) ?? 0;
    } catch (_) {
      // keep default (unlimited)
    }
  }

  Future<void> set(int value) async {
    final v = value < 0 ? 0 : value;
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key, v);
    } catch (_) {
      // best-effort
    }
    // A higher limit may free capacity for queued transfers.
    ref.read(jobsControllerProvider.notifier).pumpQueue();
  }
}

final transferConcurrencyProvider = NotifierProvider<TransferConcurrency, int>(
  TransferConcurrency.new,
);
