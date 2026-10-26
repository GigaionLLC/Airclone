/// The one-line activity summary the desktop tray shows (#54): the Windows and
/// macOS tooltip, and the disabled status row at the top of the tray menu
/// (the only place Linux can show it: AppIndicator has no tooltip).
///
/// Pure and clock-free so it can be unit-tested; the tray controller feeds it
/// a snapshot and pushes the result through [TrayTextThrottle].
library;

import 'package:flutter/foundation.dart';

import '../ui/format.dart';

/// Windows caps NOTIFYICONDATA.szTip at 128 UTF-16 units including the NUL.
const int kTrayTooltipMaxLength = 127;

/// What the tray summary is built from. Deliberately small: the tray is a
/// glance, the app window is the detail.
@immutable
class TrayActivity {
  const TrayActivity({
    this.transferring = 0,
    this.speed = 0,
    this.eta,
    this.queued = 0,
    this.queuePaused = false,
    this.bwLimit = 'off',
    this.engineReady = true,
  });

  /// Files moving right now (`core/stats` `transferring`).
  final int transferring;

  /// Bytes per second across all of them.
  final double speed;

  /// Seconds left, as rclone estimates it; null when it has no estimate.
  final double? eta;

  /// Transfers waiting for a slot (or for the queue to be resumed).
  final int queued;
  final bool queuePaused;

  /// 'off' or an rclone rate such as '5M'.
  final String bwLimit;

  /// False while the engine is starting or has failed.
  final bool engineReady;

  bool get isBusy => transferring > 0 || queued > 0;
}

/// "Transferring 2 files, 1.6 MB/s, 3 h left" or "Idle"; extras such as the
/// queue and the bandwidth limit follow after a dot. Never longer than
/// [kTrayTooltipMaxLength].
String trayStatusLine(TrayActivity a) {
  final parts = <String>[];
  if (!a.engineReady) {
    parts.add('Engine starting');
  } else if (a.transferring > 0) {
    final files = a.transferring == 1 ? '1 file' : '${a.transferring} files';
    final head = <String>['Transferring $files'];
    if (a.speed > 0) head.add('${humanSize(a.speed.round())}/s');
    final eta = formatEta(a.eta);
    if (eta != null) head.add('$eta left');
    parts.add(head.join(', '));
  } else {
    parts.add('Idle');
  }
  if (a.queued > 0) {
    parts.add('${a.queued} queued${a.queuePaused ? ' (paused)' : ''}');
  } else if (a.queuePaused) {
    parts.add('Queue paused');
  }
  if (a.bwLimit.isNotEmpty && a.bwLimit != 'off') {
    parts.add('Limit ${a.bwLimit}/s');
  }
  return parts.join(' · ');
}

/// The tooltip: the app name, then the status line, clipped to fit Windows.
String trayTooltip(TrayActivity a) =>
    clipTrayText('Airclone – ${trayStatusLine(a)}');

/// Clips [text] to [max] characters, ending in an ellipsis when cut.
String clipTrayText(String text, {int max = kTrayTooltipMaxLength}) {
  if (text.length <= max) return text;
  return '${text.substring(0, max - 1).trimRight()}…';
}

/// Coarse, human ETA: "45 s", "12 min", "3 h", "2 d". Null for no estimate.
/// Rounded UP so "1 min left" never reads as already done.
String? formatEta(double? seconds) {
  if (seconds == null || seconds.isNaN || seconds <= 0) return null;
  if (seconds.isInfinite) return null;
  final s = seconds.ceil();
  if (s < 60) return '$s s';
  if (s < 3600) return '${(s / 60).ceil()} min';
  if (s < 86400) return '${(s / 3600).round().clamp(1, 24)} h';
  return '${(s / 86400).round()} d';
}

/// Rate-limits the text pushed to the OS tray.
///
/// The stats poll ticks every second; pushing a tooltip on every tick is wasted
/// work and makes the hover text flicker. A new text goes out when it differs
/// from the last one pushed AND at least [interval] has passed since that
/// push. (The menu itself is rebuilt only on a structure change — see
/// `tray_controller.dart`.)
class TrayTextThrottle {
  TrayTextThrottle({this.interval = const Duration(seconds: 2)});

  final Duration interval;
  String? _last;
  DateTime? _lastAt;

  /// The text last pushed, if any.
  String? get last => _last;

  /// True when [text] should be pushed now; the caller then pushes it. A text
  /// refused for timing is NOT remembered: offer the current text again on
  /// the next tick and it goes out once the interval has passed.
  bool offer(String text, DateTime now) {
    if (text == _last) return false;
    final at = _lastAt;
    if (at != null && now.difference(at) < interval) return false;
    _last = text;
    _lastAt = now;
    return true;
  }

  /// Forget the last push, so the next [offer] always goes out (after the
  /// tray icon was re-created, for example).
  void reset() {
    _last = null;
    _lastAt = null;
  }
}
