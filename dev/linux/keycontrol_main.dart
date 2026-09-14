// A stock Flutter app that does nothing but report the keys it receives.
//
// The control for dev/linux/test-keyboard.sh. That harness found zero key
// events reaching Airclone on a virtual display - with X input focus confirmed
// on its window - which is either a fault in Airclone or a fact about Flutter on
// Linux under a bare X server with no window manager. Those want opposite fixes,
// so the harness is pointed at a bare `flutter create` app carrying this file
// and nothing else. It prints the same two lines the harness reads from
// Airclone's own --log-input (lib/src/ui/input_log.dart).
//
// Not part of the app. It is copied over a generated project's lib/main.dart in
// CI and never built into anything that ships.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  stderr.writeln('input logging on. Control app.');
  HardwareKeyboard.instance.addHandler((KeyEvent event) {
    stderr.writeln(
      'input: ${event.runtimeType} key=${event.logicalKey.keyLabel} '
      'char=${event.character ?? "none"}',
    );
    return false;
  });
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
