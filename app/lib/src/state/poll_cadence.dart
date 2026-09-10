import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'registration_policy.dart';

/// How often the shared background job wakes to run whatever is due.
///
/// Only the schedules that never named an exact time reach that job (see
/// [registrationShapeFor]), so this is the lateness bound for "every N hours"
/// tasks and nothing else — a daily 09:00 task fires at 09:00 whatever this
/// says. That is worth knowing before turning it down: five minutes buys
/// punctuality for the schedules least likely to care about it.
///
/// Persisted, because the OS registration built from it outlives the process.
class PollCadence extends Notifier<int> {
  static const _key = 'scheduler_poll_minutes';

  @override
  int build() {
    _load();
    return kDefaultPollMinutes;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getInt(_key);
      if (v != null) state = clampPollMinutes(v);
    } catch (_) {
      // A cadence we cannot read is not worth crashing over; the default is a
      // reasonable answer and the registration is rebuilt from whatever we end
      // up holding.
    }
  }

  /// Clamped on the way in as well as on the way out, so nothing downstream has
  /// to wonder whether the value it holds is sane.
  Future<void> set(int minutes) async {
    final v = clampPollMinutes(minutes);
    if (v == state) return;
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key, v);
    } catch (_) {
      // Best effort; the in-memory value still drives this session.
    }
  }
}

final pollCadenceProvider = NotifierProvider<PollCadence, int>(PollCadence.new);
