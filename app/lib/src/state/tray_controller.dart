/// The desktop tray icon (#54): an icon, a throttled activity tooltip, and a
/// small menu: Open Airclone, Pause/Resume all, a bandwidth limit, Quit.
///
/// Desktop only, and only once a tray host exists: Windows and macOS always
/// have one; on Linux the runner asks the session bus for a StatusNotifier
/// host. With no host nothing is created and [trayAvailableProvider] stays
/// false, so closing the window quits exactly as before.
///
/// The tray never owns state of its own. Every item drives the same
/// providers the window does (queuePausedProvider, bandwidthControllerProvider),
/// so the tray and the window can never disagree.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

import '../rclone/models/job.dart';
import 'bandwidth_controller.dart';
import 'close_to_tray.dart';
import 'desktop_window.dart';
import 'engine_controller.dart';
import 'host_platform.dart';
import 'jobs_controller.dart';
import 'stats_controller.dart';
import 'tray_status.dart';

/// Bandwidth choices in the tray, the same ones as the window's top bar.
const List<String> kTrayBandwidthPresets = [
  'off',
  '1M',
  '5M',
  '10M',
  '50M',
  '100M',
];

/// "Unlimited" or "5M/s", matching the top-bar control.
String trayBandwidthLabel(String rate) =>
    rate == 'off' || rate.isEmpty ? 'Unlimited' : '$rate/s';

/// rclone may answer `core/bwlimit` with "5Mi" for a limit set as "5M".
bool sameBandwidth(String a, String b) {
  String norm(String r) {
    final t = r.trim();
    if (t.isEmpty) return 'off';
    return t.endsWith('i') ? t.substring(0, t.length - 1) : t;
  }

  return norm(a).toLowerCase() == norm(b).toLowerCase();
}

/// Everything the menu shows; equal inputs build an equal menu, which is how
/// the controller skips rebuilds that would change nothing.
@immutable
class TrayMenuInput {
  const TrayMenuInput({
    required this.status,
    required this.queuePaused,
    required this.bwLimit,
    required this.engineReady,
  });

  final String status;
  final bool queuePaused;
  final String bwLimit;
  final bool engineReady;

  /// The part of the menu a click changes. A change here is pushed at once;
  /// a status-only change waits for the throttle.
  String get structureKey => '$queuePaused|$bwLimit|$engineReady';
}

/// The tray menu. Pure apart from [onAction], so tests can walk it.
///
/// Every clickable item carries a stable [MenuItem.key] and reports that key
/// through [onAction], never a closure bound to this build. A rebuild replaces
/// the plugin's item objects, so the key is what lets a click from the menu
/// before a rebuild still reach the same action.
Menu buildTrayMenu(
  TrayMenuInput input, {
  required void Function(String key) onAction,
}) {
  final presets = [...kTrayBandwidthPresets];
  final custom = !presets.any((p) => sameBandwidth(p, input.bwLimit));
  return Menu(
    items: [
      MenuItem(
        key: 'status',
        label: clipTrayText(input.status, max: 64),
        disabled: true,
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'open',
        label: 'Open Airclone',
        onClick: (item) => onAction(item.key!),
      ),
      MenuItem(
        key: 'pause',
        label: input.queuePaused ? 'Resume all' : 'Pause all',
        toolTip: input.queuePaused
            ? 'Start the waiting transfers again'
            : 'Queued transfers wait; running ones finish',
        onClick: (item) => onAction(item.key!),
      ),
      MenuItem.submenu(
        key: 'bwlimit',
        label: 'Bandwidth limit: ${trayBandwidthLabel(input.bwLimit)}',
        disabled: !input.engineReady,
        submenu: Menu(
          items: [
            if (custom)
              MenuItem.checkbox(
                key: 'bw:current',
                label: trayBandwidthLabel(input.bwLimit),
                checked: true,
                disabled: true,
              ),
            for (final p in presets)
              MenuItem.checkbox(
                key: 'bw:$p',
                label: trayBandwidthLabel(p),
                checked: sameBandwidth(p, input.bwLimit),
                onClick: (item) => onAction(item.key!),
              ),
          ],
        ),
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'quit',
        label: 'Quit Airclone',
        onClick: (item) => onAction(item.key!),
      ),
    ],
  );
}

/// Rebuilds the context menu only when what it offers changes (plus, on Linux,
/// a throttled status change).
///
/// The menu also has a status row, which changes every couple of seconds. On
/// Windows, tray_manager 0.5.3 leaks the Bandwidth submenu handle on every
/// `setContextMenu`, and the per-process USER-object quota is exhausted after
/// 5-6 hours of that. A status-only change therefore never rebuilds: the live
/// text rides in the tooltip on Windows and macOS, and the row keeps its old
/// label until the next structure change. Linux has no tooltip and no leak, so
/// there [liveStatus] keeps the row current.
class TrayMenuPublisher {
  TrayMenuPublisher({required this.rebuild, this.liveStatus});

  final void Function(TrayMenuInput input) rebuild;

  /// Linux only: AppIndicator has no tooltip, so the menu's status row is the
  /// only status there is, and it is rebuilt for a status change too (at most
  /// every [TrayTextThrottle.interval]). Rebuilding leaks nothing on Linux;
  /// the submenu handle leak is Windows-only, where the tooltip carries the
  /// live text instead.
  final TrayTextThrottle? liveStatus;
  String? _structure;

  /// Whether a status change is waiting for the throttle interval to pass.
  bool get statusPending {
    final live = liveStatus;
    return live != null && _status != live.last;
  }

  String? _status;

  /// Rebuilds for a structure change (or, with [liveStatus], a status change
  /// the throttle lets through) and returns true; otherwise leaves the menu
  /// alone and returns false.
  bool update(TrayMenuInput input, [DateTime? now]) {
    _status = input.status;
    final structureChanged = input.structureKey != _structure;
    final live = liveStatus;
    // A structure rebuild carries the current status too, so it counts as
    // that status's push (and a click's result shows at once).
    if (structureChanged) live?.reset();
    final statusDue =
        live != null && live.offer(input.status, now ?? DateTime.now());
    if (!structureChanged && !statusDue) return false;
    _structure = input.structureKey;
    rebuild(input);
    return true;
  }
}

/// What the tray summary reads from the providers right now.
TrayActivity trayActivityFrom({
  required CoreStats stats,
  required List<Job> jobs,
  required bool queuePaused,
  required String bwLimit,
  required bool engineReady,
}) => TrayActivity(
  transferring: stats.transferring.length,
  speed: stats.speed,
  eta: stats.eta,
  queued: jobs.where((j) => j.status == JobStatus.queued).length,
  queuePaused: queuePaused,
  bwLimit: bwLimit,
  engineReady: engineReady,
);

class TrayController with TrayListener {
  TrayController(this._ref);

  final Ref _ref;
  final _tooltip = TrayTextThrottle();
  late final _menu = TrayMenuPublisher(
    liveStatus: HostPlatform.isLinux ? TrayTextThrottle() : null,
    rebuild: (input) =>
        unawaited(_guard(trayManager.setContextMenu(_buildMenu(input)))),
  );
  Timer? _trailing;
  bool _started = false;
  bool _up = false;
  final _subs = <ProviderSubscription<Object?>>[];

  /// Set by the app: a real quit (the mounts guard still runs).
  Future<void> Function()? onQuit;

  bool get isUp => _up;

  /// A deliberate quit: the menu's Quit item and Settings → Update's Quit both
  /// go through here, so both run the mounts guard in the app.
  Future<void> requestQuit() async => onQuit?.call();

  /// Creates the tray icon when this platform has a tray host. Safe to call
  /// more than once; only the first call does anything.
  Future<void> start() async {
    if (_started || !HostPlatform.isDesktop) return;
    _started = true;
    final startedHidden = await DesktopWindow.startedHidden();
    final host = await DesktopWindow.trayHostAvailable();
    if (!host) {
      // A `--tray` launch with nowhere to live must not stay invisible.
      if (startedHidden) await DesktopWindow.show();
      return;
    }
    try {
      await _setIcon();
      trayManager.addListener(this);
      _up = true;
    } catch (e) {
      debugPrint('tray: could not create the icon: $e');
      if (startedHidden) await DesktopWindow.show();
      return;
    }
    _ref.read(trayAvailableProvider.notifier).set(true);
    if (HostPlatform.isMacOS) await DesktopWindow.setInterceptClose(true);
    // macOS cannot start its engine behind a window that never appears, so a
    // tray launch there puts the window up fully transparent; this takes it
    // away for real. Elsewhere the window was never shown and this is a no-op.
    if (startedHidden) await DesktopWindow.hide();

    void changed(Object? _, Object? _) => _refresh();
    _subs
      ..add(_ref.listen<CoreStats>(statsProvider, changed))
      ..add(_ref.listen<List<Job>>(jobsControllerProvider, changed))
      ..add(_ref.listen<bool>(queuePausedProvider, changed))
      ..add(_ref.listen<BandwidthState>(bandwidthControllerProvider, changed))
      ..add(_ref.listen<EngineUi>(engineControllerProvider, changed));
    _refresh();
  }

  Future<void> _setIcon() {
    if (HostPlatform.isWindows) {
      return trayManager.setIcon('assets/tray/tray_windows.ico');
    }
    if (HostPlatform.isMacOS) {
      return trayManager.setIcon(
        'assets/tray/tray_macos_template.png',
        isTemplate: true,
      );
    }
    // Linux: tray_manager passes the bare icon NAME through when sandboxed
    // (Flatpak, Snap), where the host cannot see our file paths.
    return trayManager.setIcon(
      runningInSandboxForTray()
          ? 'com.gigaionllc.airclone'
          : 'assets/tray/tray_linux.png',
    );
  }

  TrayActivity _activity() {
    final engine = _ref.read(engineControllerProvider);
    return trayActivityFrom(
      stats: _ref.read(statsProvider),
      jobs: _ref.read(jobsControllerProvider),
      queuePaused: _ref.read(queuePausedProvider),
      bwLimit: _ref.read(bandwidthControllerProvider).rate,
      engineReady: engine.isReady,
    );
  }

  void _refresh() {
    if (!_up) return;
    final a = _activity();
    final now = DateTime.now();
    var pending = false;

    // Linux AppIndicator has no tooltip; the status row in the menu is it.
    if (!HostPlatform.isLinux) {
      final tip = trayTooltip(a);
      if (_tooltip.offer(tip, now)) {
        unawaited(_guard(trayManager.setToolTip(tip)));
      } else if (tip != _tooltip.last) {
        pending = true;
      }
    }

    final input = TrayMenuInput(
      status: trayStatusLine(a),
      queuePaused: a.queuePaused,
      bwLimit: a.bwLimit,
      engineReady: a.engineReady,
    );
    // Structure only on Windows and macOS, where the tooltip above carries the
    // live text: a rebuild per stats tick leaks a Windows submenu handle (see
    // [TrayMenuPublisher]). Linux also rebuilds for a throttled status change.
    _menu.update(input, now);
    if (_menu.statusPending) pending = true;

    // A tooltip or Linux status change refused for timing goes out once the
    // interval has passed, even if nothing else changes in between (the last
    // tick of a transfer).
    if (pending && _trailing == null) {
      _trailing = Timer(_tooltip.interval, () {
        _trailing = null;
        _refresh();
      });
    }
  }

  Menu _buildMenu(TrayMenuInput input) =>
      buildTrayMenu(input, onAction: _onMenuAction);

  /// A tray click, by the stable key every item carries rather than by object
  /// identity: the plugin may deliver a click from a menu built before a
  /// rebuild, and that item's key still names the same action.
  void _onMenuAction(String key) {
    switch (key) {
      case 'open':
        unawaited(DesktopWindow.show());
      case 'pause':
        _ref.read(queuePausedProvider.notifier).toggle();
      case 'quit':
        unawaited(requestQuit());
      default:
        if (key.startsWith('bw:')) {
          final rate = key.substring('bw:'.length);
          if (kTrayBandwidthPresets.contains(rate)) {
            unawaited(
              _ref.read(bandwidthControllerProvider.notifier).setLimit(rate),
            );
          }
        }
    }
  }

  Future<void> _guard(Future<void> f) async {
    try {
      await f;
    } catch (e) {
      debugPrint('tray: $e');
    }
  }

  // Windows: left click opens the window, right click the menu, as the
  // Windows tray convention has it. macOS: a status item opens its menu on
  // any click. Linux: the indicator host opens the menu itself.
  @override
  void onTrayIconMouseDown() {
    if (HostPlatform.isWindows) {
      unawaited(DesktopWindow.show());
    } else if (HostPlatform.isMacOS) {
      unawaited(_guard(trayManager.popUpContextMenu()));
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (HostPlatform.isWindows || HostPlatform.isMacOS) {
      unawaited(_guard(trayManager.popUpContextMenu()));
    }
  }

  /// Removes the icon. Called on the way out, so Windows does not leave a
  /// ghost icon in the notification area until the mouse passes over it.
  Future<void> stop() async {
    _trailing?.cancel();
    _trailing = null;
    for (final s in _subs) {
      s.close();
    }
    _subs.clear();
    if (!_up) return;
    _up = false;
    trayManager.removeListener(this);
    await _guard(trayManager.destroy());
  }
}

/// tray_manager 0.5.3's own sandbox test (lib/src/helpers/sandbox.dart),
/// repeated so the icon choice above matches what the plugin will do with it:
/// in Flatpak, Snap or a container it passes the string through as an icon
/// NAME, elsewhere it turns it into a path under data/flutter_assets.
bool runningInSandboxForTray() {
  final env = HostPlatform.environment;
  if (env.containsKey('FLATPAK_ID') || env.containsKey('SNAP')) return true;
  if ((env['container'] ?? '').isNotEmpty) return true;
  try {
    return File('/.dockerenv').existsSync();
  } catch (_) {
    return false;
  }
}

final trayControllerProvider = Provider<TrayController>((ref) {
  final c = TrayController(ref);
  ref.onDispose(() => unawaited(c.stop()));
  return c;
});
