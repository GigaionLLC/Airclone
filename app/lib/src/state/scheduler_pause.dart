import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Why the scheduler stopped, or null while it is running.
///
/// A scheduled one-way Sync deletes whatever the source no longer has. When that
/// run aborts because it would have deleted more than its cap, something about
/// the world has changed — an external drive is not mounted, a token expired, a
/// folder was renamed — and the right response is not to try again in an hour.
///
/// The pause is deliberately GLOBAL rather than per-task, because those causes
/// are environmental: the drive that is missing for one task is missing for every
/// task pointing at it. Letting the others keep firing is how one bad night
/// becomes several.
@immutable
class SchedulerPause {
  const SchedulerPause({
    required this.at,
    required this.taskId,
    required this.taskName,
    required this.reason,
  });

  /// When the run that tripped it finished.
  final DateTime at;

  /// The task whose run tripped it, so the user knows where to look.
  final String taskId;
  final String taskName;

  /// The engine's own words. Kept verbatim rather than summarised — a paraphrase
  /// of an error is one more thing that can be wrong.
  final String reason;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'taskId': taskId,
    'taskName': taskName,
    'reason': reason,
  };

  static SchedulerPause? fromJson(Map<String, dynamic> j) {
    final at = DateTime.tryParse((j['at'] ?? '').toString());
    if (at == null) return null;
    return SchedulerPause(
      at: at,
      taskId: (j['taskId'] ?? '').toString(),
      taskName: (j['taskName'] ?? '').toString(),
      reason: (j['reason'] ?? '').toString(),
    );
  }
}

/// Persisted, because a pause that forgets itself on restart is not a pause. The
/// whole point is that a human looks before anything runs again.
class SchedulerPaused extends Notifier<SchedulerPause?> {
  static const _key = 'scheduler_paused';

  @override
  SchedulerPause? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is Map) state = SchedulerPause.fromJson(j.cast<String, dynamic>());
    } catch (_) {
      // A pause we cannot read is not a reason to crash. It IS a reason to stay
      // running rather than stay stopped: the failure mode of a false pause is
      // "nothing backs up and nobody knows why", which is worse than one extra
      // run that trips the cap again and pauses properly.
    }
  }

  /// Stop the scheduler. Safe to call twice — the FIRST reason is kept, because
  /// it is the one that describes what actually went wrong; a later run failing
  /// because the scheduler is paused would otherwise overwrite it.
  Future<void> pause(SchedulerPause p) async {
    if (state != null) return;
    state = p;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(p.toJson()));
    } catch (_) {
      // Best effort. In-memory state still stops this session.
    }
  }

  /// Explicit, and only ever from a user action. There is no auto-resume and no
  /// timeout: the point of the pause is that somebody looks.
  Future<void> resume() async {
    state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Best effort.
    }
  }
}

final schedulerPausedProvider =
    NotifierProvider<SchedulerPaused, SchedulerPause?>(SchedulerPaused.new);

/// Whether [error] is rclone refusing to exceed the delete cap.
///
/// Over the RC there is no exit code — only the error string from `job/status` —
/// so this is a text match, and text matches rot. It is kept deliberately loose
/// (either spelling of the flag, any case) and it is the ONLY place that decides,
/// so there is one thing to fix if rclone rewords it.
///
/// VERIFY THIS AGAINST A REAL ABORTED RUN before trusting it. If the wording
/// turns out to vary across rclone versions, the fallback is to pause on any
/// failure of a scheduled destructive sync — blunter, but it cannot silently
/// stop working, and silently-stopped-working is the failure this whole feature
/// exists to prevent.
bool isDeleteCapError(String? error) {
  if (error == null || error.isEmpty) return false;
  final e = error.toLowerCase();
  return e.contains('max-delete') ||
      e.contains('max delete') ||
      e.contains('too many deletes');
}
