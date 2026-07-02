import 'dart:io';

import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Window backdrops only exist on desktop. On mobile the acrylic plugin has no
/// implementation and — worse — `Window.setEffect` awaits an internal completer
/// that `Window.initialize` never completed (its channel call threw), so any
/// call would hang forever. Every entry point below bails out early instead.
bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Desktop window background material, applied via `flutter_acrylic`.
///
/// [systemDefault] and [solid] both leave the standard opaque window; [mica]
/// and [acrylic] request the matching Windows 11 backdrop effects.
enum WindowBackdrop { systemDefault, solid, mica, acrylic }

extension WindowBackdropLabel on WindowBackdrop {
  String get label {
    switch (this) {
      case WindowBackdrop.systemDefault:
        return 'System default';
      case WindowBackdrop.solid:
        return 'Solid';
      case WindowBackdrop.mica:
        return 'Mica (Windows 11)';
      case WindowBackdrop.acrylic:
        return 'Acrylic';
    }
  }
}

/// SharedPreferences key for the persisted [WindowBackdrop].
const _backdropKey = 'window_backdrop';

/// Reads the saved backdrop directly (used at startup, before the provider
/// graph exists, to apply the effect ahead of the first frame). Falls back to
/// [WindowBackdrop.systemDefault].
Future<WindowBackdrop> loadSavedBackdrop() async {
  try {
    final p = await SharedPreferences.getInstance();
    final name = p.getString(_backdropKey);
    return WindowBackdrop.values.firstWhere(
      (v) => v.name == name,
      orElse: () => WindowBackdrop.systemDefault,
    );
  } catch (_) {
    return WindowBackdrop.systemDefault;
  }
}

/// Persisted controller for the active [WindowBackdrop]. Updating the value
/// stores it and re-applies the effect to the live window.
class WindowBackdropController extends Notifier<WindowBackdrop> {
  static const _key = _backdropKey;

  @override
  WindowBackdrop build() {
    _load();
    return WindowBackdrop.systemDefault;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final name = p.getString(_key);
      if (name != null) {
        for (final value in WindowBackdrop.values) {
          if (value.name == name) {
            state = value;
            break;
          }
        }
      }
    } catch (_) {
      // keep default
    }
  }

  Future<void> set(WindowBackdrop value) async {
    state = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, value.name);
    } catch (_) {
      // best-effort
    }
    await applyWindowBackdrop(value, dark: true);
  }
}

final windowBackdropProvider =
    NotifierProvider<WindowBackdropController, WindowBackdrop>(
      WindowBackdropController.new,
    );

/// Initializes the window-effect plugin. Safe to call once at startup before
/// `runApp`. Any failure is a silent no-op.
Future<void> initWindowBackdrop() async {
  if (!_isDesktop) return;
  try {
    await Window.initialize();
  } catch (_) {
    // effects unsupported; keep the standard window
  }
}

/// Applies [backdrop] to the live window. [systemDefault] and [solid] map to
/// the disabled (standard) effect; [mica] and [acrylic] map to their Windows 11
/// counterparts. Any failure is a silent no-op.
Future<void> applyWindowBackdrop(
  WindowBackdrop backdrop, {
  bool dark = true,
}) async {
  if (!_isDesktop) return;
  WindowEffect effect;
  switch (backdrop) {
    case WindowBackdrop.systemDefault:
    case WindowBackdrop.solid:
      effect = WindowEffect.disabled;
      break;
    case WindowBackdrop.mica:
      effect = WindowEffect.mica;
      break;
    case WindowBackdrop.acrylic:
      effect = WindowEffect.acrylic;
      break;
  }
  try {
    await Window.setEffect(effect: effect, dark: dark);
  } catch (_) {
    // effect unsupported; keep current window background
  }
}
