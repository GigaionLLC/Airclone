import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_schedule.dart';
import 'transfer_options.dart';

const Object _undef = Object();

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
  });

  final String id;
  final String name;
  final String srcFs;
  final String srcLabel;
  final String dstFs;
  final String dstLabel;
  final TransferOptions options;
  final TaskSchedule? schedule;
  final DateTime? lastRun;

  /// `schedule`/`lastRun` accept an explicit `null` to clear them (via the
  /// [_undef] sentinel) — `copyWith()` with neither keeps the current value.
  TransferTask copyWith({
    String? name,
    TransferOptions? options,
    Object? schedule = _undef,
    Object? lastRun = _undef,
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
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'srcFs': srcFs,
    'srcLabel': srcLabel,
    'dstFs': dstFs,
    'dstLabel': dstLabel,
    'options': options.toJson(),
    // Omit when null so old app versions + payloads round-trip untouched.
    if (schedule != null) 'schedule': schedule!.toJson(),
    if (lastRun != null) 'lastRun': lastRun!.toIso8601String(),
  };

  factory TransferTask.fromJson(Map<String, dynamic> j) => TransferTask(
    id: (j['id'] ?? '') as String,
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
      state = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(TransferTask.fromJson)
          .toList();
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
}

final tasksProvider = NotifierProvider<TasksController, List<TransferTask>>(
  TasksController.new,
);
