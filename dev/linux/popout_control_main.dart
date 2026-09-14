// Does opening and closing a second window crash a Flutter Linux app?
//
// A tester closed an Airclone pop-out image window and the WHOLE APP died:
//
//   'FlutterEngineRemoveView' returned 'kInvalidArguments'.
//     Remove view info was invalid. The implicit view cannot be removed.
//   WARNING: RemoveWindow: fb091901-...
//   WARNING: Attempted to set message handler on an FlBinaryMessenger
//     without an engine
//   Gdk-WARNING: eglMakeCurrent failed
//   Segmentation fault
//
// Two candidates, and they want opposite fixes: desktop_multi_window's own
// teardown on this embedder, or what Airclone does to each new window - it
// registers the generated plugin set on every one of them
// (linux/runner/my_application.cc), and flutter_acrylic's Linux registrar keeps
// a GLOBAL pointer to the newest registrar, hooks that window's "draw" signal
// and shows it. A dead pop-out leaves that global pointing at a freed engine.
//
// So this app opens a second window, closes it, and reports that it is still
// alive. CI runs it twice: once with the plugin alone, and once with
// flutter_acrylic registered the way Airclone registers it. Whichever one dies
// names the culprit.
//
// Not part of the app. Copied over a generated project's lib/main.dart in CI.
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // A second engine in this process re-runs main(), exactly as Airclone's
  // pop-out does. That copy renders a page and waits to be closed.
  final sub = await WindowController.fromCurrentEngine()
      .then<WindowController?>((c) => c)
      .timeout(const Duration(seconds: 3), onTimeout: () => null)
      .catchError((_) => null);
  if (sub != null && sub.arguments.isNotEmpty) {
    runApp(const _Child());
    return;
  }

  runApp(const _Parent());

  stderr.writeln('popout: opening a second window');
  final controller = await WindowController.create(
    WindowConfiguration(arguments: 'child'),
  );
  await controller.show();
  await Future<void>.delayed(const Duration(seconds: 3));
  // The harness closes it from outside, the way a person does: the plugin has
  // no close() in 0.3.1, and the crash being chased is the window-manager
  // destroy path, not an API call.
  stderr.writeln('popout: opened');

  await Future<void>.delayed(const Duration(seconds: 15));
  stderr.writeln('popout: the app survived closing the second window');
  exit(0);
}

class _Parent extends StatelessWidget {
  const _Parent();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('main window'))),
  );
}

class _Child extends StatelessWidget {
  const _Child();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('pop-out'))),
  );
}
