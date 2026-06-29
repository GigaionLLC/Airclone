import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transfer_options.dart';

/// A saved, re-runnable transfer: a From → To pair plus its [TransferOptions].
/// [srcFs]/[dstFs] are full `remote:path` strings passed straight to the RC call;
/// [srcLabel]/[dstLabel] are human-readable for display + job rows.
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
  });

  final String id;
  final String name;
  final String srcFs;
  final String srcLabel;
  final String dstFs;
  final String dstLabel;
  final TransferOptions options;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'srcFs': srcFs,
    'srcLabel': srcLabel,
    'dstFs': dstFs,
    'dstLabel': dstLabel,
    'options': options.toJson(),
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

  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
    _persist();
  }
}

final tasksProvider = NotifierProvider<TasksController, List<TransferTask>>(
  TasksController.new,
);
