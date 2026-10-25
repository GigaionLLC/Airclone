/// "Closing the window keeps Airclone running in the tray" (#54).
///
/// DEFAULT: OFF, and stored as "never chosen" (null) rather than false, so the
/// app can tell a user who turned it off from one who was never asked. Off by
/// default because:
///   * X has quit Airclone since the first release, and silently changing what
///     the close button does surprises every existing user;
///   * a hidden window still moves data, mounts drives and uses bandwidth, so
///     staying alive after X has to be the user's decision, not ours;
///   * Linux desktops without a StatusNotifier host (stock GNOME) have no tray
///     to come back from.
/// Instead, the FIRST time the user closes the window while transfers are
/// running, and has never chosen, Airclone asks once (see [decideClose] and
/// ui/close_to_tray_dialog.dart), and the answer is saved here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tri-state, persisted: null = never chosen, true = keep running in the tray,
/// false = quit on close.
class CloseToTray extends Notifier<bool?> {
  static const prefsKey = 'close_to_tray';

  @override
  bool? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(prefsKey);
      if (v != null) state = v;
    } catch (_) {
      // Unreadable: stay "never chosen", which quits on close as before.
    }
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefsKey, value);
    } catch (_) {
      // Best effort: the in-memory choice still holds for this session.
    }
  }
}

final closeToTrayProvider = NotifierProvider<CloseToTray, bool?>(
  CloseToTray.new,
);

/// Whether a tray icon is up right now. Set by the tray controller; false on
/// mobile, web, and on a Linux desktop with no indicator host, which is what
/// makes X quit there exactly as it always has.
class TrayAvailable extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final trayAvailableProvider = NotifierProvider<TrayAvailable, bool>(
  TrayAvailable.new,
);

/// What pressing the window's close button should do.
enum CloseAction {
  /// Hide the window; the engine, transfers, mounts and scheduler carry on.
  hideToTray,

  /// The old behaviour: the mounts guard, then quit.
  quit,

  /// Never chosen and something is running: ask once, then remember.
  ask,
}

/// The close decision, kept pure so every branch is tested.
///
/// No tray means quit, whatever the setting says: hiding a window that cannot
/// be brought back would look exactly like a crash that left `rcd` running.
CloseAction decideClose({
  required bool? closeToTray,
  required bool trayAvailable,
  required bool busy,
}) {
  if (!trayAvailable) return CloseAction.quit;
  switch (closeToTray) {
    case true:
      return CloseAction.hideToTray;
    case false:
      return CloseAction.quit;
    case null:
      return busy ? CloseAction.ask : CloseAction.quit;
  }
}
