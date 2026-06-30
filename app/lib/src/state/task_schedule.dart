import 'package:flutter/foundation.dart';

/// How a saved task repeats.
enum ScheduleKind { interval, daily, weekly }

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

/// A repeat rule attached to a saved [TransferTask]. The in-app scheduler
/// evaluates it on a timer **while Airclone is open** — there is no background
/// service, so a slot that falls while the app is closed runs once on next
/// launch (catch-up) rather than at the exact wall-clock time.
@immutable
class TaskSchedule {
  const TaskSchedule({
    required this.kind,
    this.intervalMinutes = 360,
    this.hour = 9,
    this.minute = 0,
    this.weekdays = const [],
  });

  final ScheduleKind kind;

  /// For [ScheduleKind.interval]: minutes between runs.
  final int intervalMinutes;

  /// For daily/weekly: wall-clock time of day (0–23 / 0–59).
  final int hour;
  final int minute;

  /// For [ScheduleKind.weekly]: `DateTime.weekday` values (Mon=1 … Sun=7).
  final List<int> weekdays;

  TaskSchedule copyWith({
    ScheduleKind? kind,
    int? intervalMinutes,
    int? hour,
    int? minute,
    List<int>? weekdays,
  }) => TaskSchedule(
    kind: kind ?? this.kind,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays ?? this.weekdays,
  );

  /// A short human description, e.g. "Every 6 hours", "Daily at 09:00",
  /// "Mon, Wed at 18:30".
  String describe() {
    switch (kind) {
      case ScheduleKind.interval:
        final m = intervalMinutes;
        if (m % 60 == 0) {
          final h = m ~/ 60;
          return 'Every $h hour${h == 1 ? '' : 's'}';
        }
        return 'Every $m min';
      case ScheduleKind.daily:
        return 'Daily at ${_hhmm(hour, minute)}';
      case ScheduleKind.weekly:
        if (weekdays.isEmpty) return 'Weekly (no days)';
        final days = (weekdays.toList()..sort())
            .map((d) => _weekdayShort[(d - 1).clamp(0, 6)])
            .join(', ');
        return '$days at ${_hhmm(hour, minute)}';
    }
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'intervalMinutes': intervalMinutes,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays,
  };

  factory TaskSchedule.fromJson(Map<String, dynamic> j) => TaskSchedule(
    kind: ScheduleKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => ScheduleKind.interval,
    ),
    intervalMinutes: (j['intervalMinutes'] as num?)?.toInt() ?? 360,
    hour: (j['hour'] as num?)?.toInt() ?? 9,
    minute: (j['minute'] as num?)?.toInt() ?? 0,
    weekdays:
        (j['weekdays'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const [],
  );

  @override
  bool operator ==(Object other) =>
      other is TaskSchedule &&
      other.kind == kind &&
      other.intervalMinutes == intervalMinutes &&
      other.hour == hour &&
      other.minute == minute &&
      listEquals(other.weekdays, weekdays);

  @override
  int get hashCode => Object.hash(
    kind,
    intervalMinutes,
    hour,
    minute,
    Object.hashAll(weekdays),
  );
}

/// Whether [s] is due to run at [now] given its [lastRun] (null = never run).
///
/// Pure + side-effect free so it can be unit-tested. The "slot" comparison
/// (`now >= slot && lastRun < slot`) both catches up a single missed clock-time
/// slot and prevents a second fire once [lastRun] has been stamped past it.
bool isDue(TaskSchedule s, {required DateTime now, DateTime? lastRun}) {
  switch (s.kind) {
    case ScheduleKind.interval:
      if (lastRun == null) return true;
      return now.difference(lastRun).inMinutes >= s.intervalMinutes;
    case ScheduleKind.daily:
      final slot = DateTime(now.year, now.month, now.day, s.hour, s.minute);
      if (now.isBefore(slot)) return false;
      return lastRun == null || lastRun.isBefore(slot);
    case ScheduleKind.weekly:
      if (s.weekdays.isEmpty || !s.weekdays.contains(now.weekday)) return false;
      final slot = DateTime(now.year, now.month, now.day, s.hour, s.minute);
      if (now.isBefore(slot)) return false;
      return lastRun == null || lastRun.isBefore(slot);
  }
}

/// The next time [s] will fire at or after [from] (for display). When a slot is
/// already overdue this returns [from] ("due now"); callers may show [isDue]
/// instead for that case.
DateTime nextRun(TaskSchedule s, {required DateTime from, DateTime? lastRun}) {
  switch (s.kind) {
    case ScheduleKind.interval:
      final next = (lastRun ?? from).add(Duration(minutes: s.intervalMinutes));
      return next.isAfter(from) ? next : from;
    case ScheduleKind.daily:
      var slot = DateTime(from.year, from.month, from.day, s.hour, s.minute);
      if (slot.isBefore(from)) slot = slot.add(const Duration(days: 1));
      return slot;
    case ScheduleKind.weekly:
      if (s.weekdays.isEmpty) return from;
      for (var i = 0; i < 8; i++) {
        final day = DateTime(
          from.year,
          from.month,
          from.day,
          s.hour,
          s.minute,
        ).add(Duration(days: i));
        if (s.weekdays.contains(day.weekday) && !day.isBefore(from)) return day;
      }
      return from;
  }
}
