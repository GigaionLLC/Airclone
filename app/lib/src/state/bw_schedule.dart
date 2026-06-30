import 'package:flutter/foundation.dart';

/// One daily bandwidth window: from [hour]:[minute], the limit is [rate] (an
/// rclone rate like `512k`/`10M`, or `off` for unlimited) until the next window.
@immutable
class BwWindow {
  const BwWindow({
    required this.hour,
    required this.minute,
    required this.rate,
  });
  final int hour;
  final int minute;
  final String rate;

  int get minutes => hour * 60 + minute;

  BwWindow copyWith({int? hour, int? minute, String? rate}) => BwWindow(
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    rate: rate ?? this.rate,
  );

  Map<String, dynamic> toJson() => {
    'hour': hour,
    'minute': minute,
    'rate': rate,
  };
  factory BwWindow.fromJson(Map<String, dynamic> j) => BwWindow(
    hour: (j['hour'] as num?)?.toInt() ?? 0,
    minute: (j['minute'] as num?)?.toInt() ?? 0,
    rate: (j['rate'] as String?) ?? 'off',
  );
}

/// A daily bandwidth timetable. When [enabled], the in-app ticker applies the
/// active window's [rate] live via `core/bwlimit` (rclone's live limit takes a
/// single rate, so Airclone holds the clock and re-applies at each boundary).
@immutable
class BwSchedule {
  const BwSchedule({this.enabled = false, this.windows = const []});
  final bool enabled;
  final List<BwWindow> windows;

  BwSchedule copyWith({bool? enabled, List<BwWindow>? windows}) => BwSchedule(
    enabled: enabled ?? this.enabled,
    windows: windows ?? this.windows,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'windows': [for (final w in windows) w.toJson()],
  };
  factory BwSchedule.fromJson(Map<String, dynamic> j) => BwSchedule(
    enabled: j['enabled'] == true,
    windows: [
      for (final w in (j['windows'] as List? ?? const []))
        if (w is Map) BwWindow.fromJson(w.cast<String, dynamic>()),
    ],
  );
}

/// The rate in effect at [now] for [windows] (daily cycle). Returns null when
/// empty. Before the first window of the day it wraps to the LAST window's rate.
String? activeRate(List<BwWindow> windows, DateTime now) {
  if (windows.isEmpty) return null;
  final sorted = [...windows]..sort((a, b) => a.minutes.compareTo(b.minutes));
  final nowMin = now.hour * 60 + now.minute;
  var rate =
      sorted.last.rate; // wrap: before the first window → previous day's last
  for (final w in sorted) {
    if (w.minutes <= nowMin) rate = w.rate;
  }
  return rate;
}
