import 'package:flutter/foundation.dart';

/// What kind of transfer a [Job] represents. Drives the row label in the UI.
enum JobType { copy, move, sync, delete, upload, download }

/// Lifecycle of a [Job]. A job is [running] until the underlying rclone job
/// finishes, then it settles into one of the terminal states.
enum JobStatus { running, success, failed, canceled }

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

  /// Whether the job is still actively transferring.
  bool get isRunning => status == JobStatus.running;

  /// Whether the job has reached a terminal state.
  bool get isFinished => status != JobStatus.running;

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
  );
}
