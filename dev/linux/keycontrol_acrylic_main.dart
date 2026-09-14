// The same control app, plus the one thing Airclone does to its window that a
// stock Flutter app does not: flutter_acrylic.
//
// The plain control (keycontrol_main.dart) logged 8 key events on a virtual
// display. Airclone, under the identical harness with X input focus on its own
// window, logged none. So the fault is Airclone's, and the shortest list of
// suspects is what Airclone adds to a stock runner - flutter_acrylic first,
// because its Linux registrar reaches into the toplevel: it sets the window
// app-paintable, asks for an RGBA visual, connects its own "draw" handler and
// shows the window, all before the app has drawn anything.
//
// Merely DEPENDING on it registers the plugin, so a difference between this and
// keycontrol_main.dart is the registrar's doing; a difference that only appears
// once initialize/setEffect run is the method handler's.
//
// Not part of the app. Copied over a generated project's lib/main.dart in CI.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  stderr.writeln('input logging on. Control app with flutter_acrylic.');
  HardwareKeyboard.instance.addHandler((KeyEvent event) {
    stderr.writeln(
      'input: ${event.runtimeType} key=${event.logicalKey.keyLabel} '
      'char=${event.character ?? "none"}',
    );
    return false;
  });

  // Airclone calls both of these before runApp (state/window_backdrop.dart).
  if (!args.contains('--registrar-only')) {
    try {
      await Window.initialize();
      await Window.setEffect(effect: WindowEffect.disabled, dark: true);
    } catch (e) {
      stderr.writeln('acrylic init failed: $e');
    }
  }
  runApp(const ControlApp());
}

class ControlApp extends StatelessWidget {
  const ControlApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(child: Text('type here', style: TextStyle(fontSize: 32))),
    ),
  );
}
