/// The desktop runners' own window channel (#54): hide and show the main
/// window, ask whether this launch should start hidden in the tray, whether a
/// tray host exists at all (Linux), and the sign-in launch entry on Windows and
/// macOS.
///
/// Implemented by hand in each runner, not by a plugin:
///   * windows/runner/flutter_window.cpp
///   * linux/runner/my_application.cc
///   * macos/Runner/MainFlutterWindow.swift
///
/// Every call is failure-tolerant. A runner that does not answer (mobile, the
/// web, a pop-out image window's engine, a test) reads as "no tray, start
/// visible, no autostart", which is exactly the behaviour Airclone had before
/// any of this existed.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopWindow {
  DesktopWindow._();

  static const MethodChannel _channel = MethodChannel('airclone/window');

  static Future<void> Function()? _onCloseRequested;
  static bool _handlerInstalled = false;

  /// Hide the main window. The process, engine and every transfer carry on.
  static Future<void> hide() => _call<void>('hide');

  /// Show the main window again and bring it to the front.
  static Future<void> show() => _call<void>('show');

  /// True when the runner was started with `--tray` (or, on macOS, as a login
  /// item): the window stays hidden until the user opens it from the tray.
  static Future<bool> startedHidden() async =>
      await _call<bool>('startedHidden') ?? false;

  /// Whether a tray icon would actually be seen. Always true on Windows and
  /// macOS. On Linux it asks the session bus for a StatusNotifier host: stock
  /// GNOME has none, and hiding a window there would strand it.
  static Future<bool> trayHostAvailable() async =>
      await _call<bool>('trayHostAvailable') ?? false;

  /// macOS: route the window's close button to [onCloseRequested] instead of
  /// closing (which there quits the app). Ignored elsewhere, where the close
  /// already arrives as an exit request Dart can answer.
  static Future<void> setInterceptClose(bool intercept) =>
      _call<void>('setInterceptClose', intercept);

  /// Windows (Run key) and macOS 13+ (SMAppService): whether Airclone starts
  /// at sign-in. Null when the runner cannot do it here.
  static Future<bool?> nativeAutostartEnabled() =>
      _call<bool>('autostartEnabled');

  /// Turns the native sign-in launch on or off. Returns the state the OS
  /// reports afterwards, or null when it could not be changed.
  static Future<bool?> setNativeAutostart(bool enabled) =>
      _call<bool>('setAutostart', enabled);

  /// macOS: the window's close button was pressed while close is intercepted.
  static void onCloseRequested(Future<void> Function()? handler) {
    _onCloseRequested = handler;
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'closeRequested') {
        await _onCloseRequested?.call();
      }
      return null;
    });
  }

  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('airclone/window $method failed: ${e.message}');
      return null;
    }
  }
}
