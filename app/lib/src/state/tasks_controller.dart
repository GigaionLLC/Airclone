import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_schedule.dart';
import 'transfer_options.dart';

const Object _undef = Object();

/// One recorded execution of a [TransferTask]: when it ran, whether it finished
/// cleanly, and — for a failure — the engine's error text. [duration] is the
/// wall-clock run time; [bytes] is the transferred total when the engine made it
/// cheaply available (else null). Kept in a small capped list so an *unattended*
/// run's outcome is auditable — today a failed scheduled run is indistinguishable
/// from a successful one.
@immutable
class TaskRunRecord {
  const TaskRunRecord({
    required this.at,
    required this.ok,
    this.error,
    this.duration = Duration.zero,
    this.bytes,
  });

  /// When the run reached its terminal state.
  final DateTime at;

  /// Whether it finished successfully (vs. failed/canceled).
  final bool ok;

  /// Engine error text for a failed run, if any.
  final String? error;

  /// Wall-clock run time (from dispatch to terminal).
  final Duration duration;

  /// Bytes transferred, when cheaply known from the status payload; else null.
  final int? bytes;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'ok': ok,
    // Omit at default so histories stay compact and forward-readable.
    if (error != null) 'error': error,
    if (duration != Duration.zero) 'durationMs': duration.inMilliseconds,
    if (bytes != null) 'bytes': bytes,
  };

  factory TaskRunRecord.fromJson(Map<String, dynamic> j) => TaskRunRecord(
    at:
        DateTime.tryParse((j['at'] ?? '') as String) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    ok: j['ok'] == true,
    error: j['error'] as String?,
    duration: Duration(milliseconds: (j['durationMs'] as num?)?.toInt() ?? 0),
    bytes: (j['bytes'] as num?)?.toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is TaskRunRecord &&
      other.at == at &&
      other.ok == ok &&
      other.error == error &&
      other.duration == duration &&
      other.bytes == bytes;

  @override
  int get hashCode => Object.hash(at, ok, error, duration, bytes);
}

/// A saved, re-runnable transfer: a From → To pair plus its [TransferOptions].
/// [srcFs]/[dstFs] are full `remote:path` strings passed straight to the RC call;
/// [srcLabel]/[dstLabel] are human-readable for display + job rows.
///
/// An optional [schedule] makes the task repeat on a timer (evaluated by the
/// in-app scheduler while the app is open); [lastRun] is the last time it fired
/// (persisted so a restart doesn't re-fire a slot that already ran).
@immutable
class TransferTask {
  const TransferTask({
    required this.id,
    required this.name,
    required this.srcFs,
    required this.srcLabel,
    required this.dstFs,
    required this.dstLabel,
    required this.options,
    this.schedule,
    this.lastRun,
    this.history = const [],
  });

  /// Stable, per-task identity — the exact string a headless run targets
  /// (`airclone --run-task <id>`). Generated once at creation via [newId] and
  /// preserved across every [copyWith]/JSON round-trip; legacy tasks that predate
  /// this field are back-filled on first load (see [TasksController._load]).
  final String id;
  final String name;
  final String srcFs;
  final String srcLabel;
  final String dstFs;
  final String dstLabel;
  final TransferOptions options;
  final TaskSchedule? schedule;
  final DateTime? lastRun;

  /// The most recent runs (newest first), capped at [_historyCap]. Grows only
  /// through [TasksController.recordRun].
  final List<TaskRunRecord> history;

  static final _rng = Random();

  /// Newest-first cap on [history] — keeps a persisted task's footprint bounded.
  static const _historyCap = 10;

  /// A dependency-free, practically-unique id: base-36 wall-clock milliseconds
  /// plus a short random suffix (there is no `uuid` dependency). The millis
  /// prefix keeps ids roughly time-ordered; the suffix defends against two tasks
  /// created in the same millisecond.
  static String newId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
      '-${_rng.nextInt(1 << 24).toRadixString(36)}';

  /// `schedule`/`lastRun` accept an explicit `null` to clear them (via the
  /// [_undef] sentinel) — `copyWith()` with neither keeps the current value.
  /// [id] is always preserved (identity never changes).
  TransferTask copyWith({
    String? name,
    TransferOptions? options,
    Object? schedule = _undef,
    Object? lastRun = _undef,
    List<TaskRunRecord>? history,
  }) => TransferTask(
    id: id,
    name: name ?? this.name,
    srcFs: srcFs,
    srcLabel: srcLabel,
    dstFs: dstFs,
    dstLabel: dstLabel,
    options: options ?? this.options,
    schedule: identical(schedule, _undef)
        ? this.schedule
        : schedule as TaskSchedule?,
    lastRun: identical(lastRun, _undef) ? this.lastRun : lastRun as DateTime?,
    history: history ?? this.history,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'srcFs': srcFs,
    'srcLabel': srcLabel,
    'dstFs': dstFs,
    'dstLabel': dstLabel,
    'options': options.toJson(),
    // Omit when null/empty so old app versions + payloads round-trip untouched.
    if (schedule != null) 'schedule': schedule!.toJson(),
    if (lastRun != null) 'lastRun': lastRun!.toIso8601String(),
    if (history.isNotEmpty) 'history': [for (final r in history) r.toJson()],
  };

  factory TransferTask.fromJson(Map<String, dynamic> j) => TransferTask(
    // Back-fill a fresh id for legacy payloads that predate the stable-id field
    // (empty/missing). _load persists straight after so the minted id sticks —
    // otherwise a later launch would mint a *different* one and break the
    // `--run-task <id>` contract.
    id: (j['id'] is String && (j['id'] as String).isNotEmpty)
        ? j['id'] as String
        : newId(),
    name: (j['name'] ?? 'Task') as String,
    srcFs: (j['srcFs'] ?? '') as String,
    srcLabel: (j['srcLabel'] ?? '') as String,
    dstFs: (j['dstFs'] ?? '') as String,
    dstLabel: (j['dstLabel'] ?? '') as String,
    options: TransferOptions.fromJson(
      (j['options'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    schedule: j['schedule'] == null
        ? null
        : TaskSchedule.fromJson((j['schedule'] as Map).cast<String, dynamic>()),
    lastRun: j['lastRun'] == null
        ? null
        : DateTime.tryParse(j['lastRun'] as String),
    history:
        (j['history'] as List?)
            ?.map(
              (e) => TaskRunRecord.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList() ??
        const [],
  );
}

/// Persisted list of saved [TransferTask]s.
class TasksController extends Notifier<List<TransferTask>> {
  static const _key = 'transfer_tasks';

  @override
  List<TransferTask> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      state = list.map(TransferTask.fromJson).toList();
      // Legacy payloads (pre-stable-id) get a fresh id on load; write it back so
      // `--run-task <id>` targets a value that survives the next restart (a bare
      // re-decode would otherwise mint a different id each launch).
      final backfilled = list.any((m) {
        final id = m['id'];
        return id is! String || id.isEmpty;
      });
      if (backfilled) await _persist();
    } catch (_) {
      // keep empty
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        jsonEncode(state.map((t) => t.toJson()).toList()),
      );
    } catch (_) {
      // best-effort
    }
  }

  void add(TransferTask t) {
    state = [...state, t];
    _persist();
  }

  /// Replace the task with the same id (used to set a schedule or stamp the
  /// last-run time). No-op if the id isn't found.
  void update(TransferTask t) {
    state = [for (final x in state) x.id == t.id ? t : x];
    _persist();
  }

  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
    _persist();
  }

  /// Prepends a run outcome to the task's [TransferTask.history] (newest first),
  /// caps it at the 10 most recent, and persists. No-op if [id] isn't found — the
  /// task may have been deleted while its run was still in flight.
  void recordRun(String id, TaskRunRecord r) {
    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(
            history: [
              r,
              ...t.history,
            ].take(TransferTask._historyCap).toList(growable: false),
          )
        else
          t,
    ];
    _persist();
  }
}

final tasksProvider = NotifierProvider<TasksController, List<TransferTask>>(
  TasksController.new,
);
