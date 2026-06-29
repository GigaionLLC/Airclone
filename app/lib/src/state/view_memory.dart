import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A remembered view configuration for one remote: how its listing was last
/// displayed (view mode, sort column + direction, grid density). Stored as
/// enum `.name` strings so this file stays decoupled from the UI/controller
/// enums (no import cycle).
@immutable
class ViewPref {
  const ViewPref({
    required this.viewMode,
    required this.sortKey,
    required this.ascending,
    required this.gridSize,
  });

  final String viewMode; // ViewMode.name
  final String sortKey; // SortKey.name
  final bool ascending;
  final double gridSize;

  Map<String, dynamic> toJson() => {
    'viewMode': viewMode,
    'sortKey': sortKey,
    'ascending': ascending,
    'gridSize': gridSize,
  };

  factory ViewPref.fromJson(Map<String, dynamic> j) => ViewPref(
    viewMode: j['viewMode'] as String? ?? 'list',
    sortKey: j['sortKey'] as String? ?? 'name',
    ascending: j['ascending'] as bool? ?? true,
    gridSize: (j['gridSize'] as num?)?.toDouble() ?? 112,
  );
}

/// Per-remote view memory: maps a remote name to its last [ViewPref] so opening
/// a remote restores how you last looked at it. Persisted as a JSON object.
class ViewMemory extends Notifier<Map<String, ViewPref>> {
  static const _key = 'view_memory_v1';

  @override
  Map<String, ViewPref> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = {
        for (final e in decoded.entries)
          e.key: ViewPref.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      // keep empty memory on any parse failure
    }
  }

  /// The saved preference for [remote], or null if none.
  ViewPref? prefFor(String remote) => state[remote];

  /// Records [pref] for [remote] and persists the whole map.
  void remember(String remote, ViewPref pref) {
    final existing = state[remote];
    if (existing != null &&
        existing.viewMode == pref.viewMode &&
        existing.sortKey == pref.sortKey &&
        existing.ascending == pref.ascending &&
        existing.gridSize == pref.gridSize) {
      return; // no change — avoid a needless write/notify
    }
    state = {...state, remote: pref};
    _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        jsonEncode({for (final e in state.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {
      // best-effort
    }
  }
}

final viewMemoryProvider = NotifierProvider<ViewMemory, Map<String, ViewPref>>(
  ViewMemory.new,
);
