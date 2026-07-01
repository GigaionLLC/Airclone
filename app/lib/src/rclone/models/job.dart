import 'package:flutter/foundation.dart';

/// What kind of transfer a [Job] represents. Drives the row label in the UI.
enum JobType { copy, move, sync, delete, upload, download }

/// Lifecycle of a [Job]. A job may sit [queued] (waiting for a transfer slot
/// when a concurrency limit is set), runs as [running] until the underlying
/// rclone job finishes, then settles into one of the terminal states.
enum JobStatus { queued, running, success, failed, canceled }

/// A single in-flight (or finished) transfer tracked by the Jobs engine.
///
/// Mutable by design: the periodic poller updates [bytes]/[total]/[speedBps]
/// in place and the controller swaps in fresh copies via [copyWith] so Riverpod
/// notifies listeners. [jobid] is the rclone async job id once the RC call that
/// kicked off the work has returned.
@immutable
class Job {
  const Job({
    required this.id,
    required this.type,
    required this.source,
    required this.dest,
    this.status = JobStatus.running,
    this.bytes = 0,
    this.total = 0,
    this.speedBps = 0,
    this.error,
    this.jobid,
    this.rcMethod,
    this.rcParams,
  });

  /// Local, app-assigned id (stable for the life of the job).
  final int id;

  final JobType type;

  /// Human-readable source, e.g. `gdrive:Work/file.txt`.
  final String source;

  /// Human-readable destination, e.g. `s3:backup/file.txt`.
  final String dest;

  final JobStatus status;

  /// Bytes transferred so far.
  final int bytes;

  /// Total bytes expected; `0` until known.
  final int total;

  /// Current speed in bytes per second.
  final double speedBps;

  /// Error text for a [JobStatus.failed] job, if any.
  final String? error;

  /// rclone async job id (from the `{jobid}` response). Null until assigned.
  final int? jobid;

  /// The resolved RC method + params this job dispatched, retained so the job
  /// can be replayed. Null until dispatch (or for jobs that failed before it),
  /// which also means the job isn't retryable.
  final String? rcMethod;
  final Map<String, dynamic>? rcParams;

  /// Whether this job can be re-run (it reached dispatch, then terminated).
  bool get canRetry =>
      rcMethod != null &&
      (status == JobStatus.failed || status == JobStatus.canceled);

  /// Whether the job is still actively transferring.
  bool get isRunning => status == JobStatus.running;

  /// Whether the job is waiting for a free transfer slot.
  bool get isQueued => status == JobStatus.queued;

  /// Whether the job is still pending or in flight (not yet terminal).
  bool get isActive =>
      status == JobStatus.queued || status == JobStatus.running;

  /// Whether the job has reached a terminal state.
  bool get isFinished =>
      status == JobStatus.success ||
      status == JobStatus.failed ||
      status == JobStatus.canceled;

  /// Fraction complete in `[0, 1]`. `0` while [total] is unknown.
  double get progress {
    if (total <= 0) return 0;
    return (bytes / total).clamp(0.0, 1.0);
  }

  /// Estimated time remaining as a short label (e.g. `12s`, `3m`, `—`).
  String get etaLabel {
    if (!isRunning) return '';
    if (speedBps <= 0 || total <= 0 || bytes >= total) return '—';
    final remaining = total - bytes;
    final seconds = (remaining / speedBps).round();
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${(seconds / 60).round()}m';
    return '${(seconds / 3600).round()}h';
  }

  Job copyWith({
    JobType? type,
    String? source,
    String? dest,
    JobStatus? status,
    int? bytes,
    int? total,
    double? speedBps,
    String? error,
    int? jobid,
    String? rcMethod,
    Map<String, dynamic>? rcParams,
  }) => Job(
    id: id,
    type: type ?? this.type,
    source: source ?? this.source,
    dest: dest ?? this.dest,
    status: status ?? this.status,
    bytes: bytes ?? this.bytes,
    total: total ?? this.total,
    speedBps: speedBps ?? this.speedBps,
    error: error ?? this.error,
    jobid: jobid ?? this.jobid,
    rcMethod: rcMethod ?? this.rcMethod,
    rcParams: rcParams ?? this.rcParams,
  );
}
