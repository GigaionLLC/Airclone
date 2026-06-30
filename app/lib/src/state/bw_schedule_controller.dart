import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bandwidth_controller.dart';
import 'bw_schedule.dart';

/// Holds the persisted bandwidth timetable and, while enabled, applies the
/// active window's rate live via [BandwidthController] on a 60s ticker (and
/// immediately on any change). Must be force-read once at launch (HomeScreen)
/// so its timer arms.
class BwScheduleController extends Notifier<BwSchedule> {
  static const _key = 'bw_schedule';
  Timer? _timer;
  String? _lastApplied;

  @override
  BwSchedule build() {
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _apply());
    ref.onDispose(() => _timer?.cancel());
    return const BwSchedule();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      state = BwSchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _apply(force: true);
    } catch (_) {
      /* keep default */
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {
      /* best-effort */
    }
  }

  void setEnabled(bool v) {
    state = state.copyWith(enabled: v);
    _persist();
    _apply(force: true);
  }

  void setWindows(List<BwWindow> windows) {
    state = state.copyWith(windows: windows);
    _persist();
    _apply(force: true);
  }

  /// Applies the active rate if it changed (or [force]). Skips when disabled —
  /// leaving whatever the user set manually.
  void _apply({bool force = false}) {
    if (!state.enabled || state.windows.isEmpty) return;
    final rate = activeRate(state.windows, DateTime.now());
    if (rate == null) return;
    if (!force && rate == _lastApplied) return;
    _lastApplied = rate;
    ref.read(bandwidthControllerProvider.notifier).setLimit(rate);
  }
}

final bwScheduleControllerProvider =
    NotifierProvider<BwScheduleController, BwSchedule>(
      BwScheduleController.new,
    );
