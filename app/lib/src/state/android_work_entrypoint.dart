import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../headless/headless_runner.dart';

/// The channel the worker's headless engine offers this isolate (see
/// DueTasksWorker.kt): `start` hands back the argv to run, `log` sends a line
/// to logcat, `done` reports the exit code and ends the engine.
const String kAndroidWorkBackgroundChannel = 'airclone/work_bg';

/// The Dart side of a WorkManager wake — what `main()` is to a desktop
/// `--run-due` launch.
///
/// Runs as the root of a SECOND Flutter engine inside the app's own process,
/// with no Activity and no widget tree. It asks the worker for its argv (the
/// same `--run-due --timeout-minutes N` contract the OS schedulers use), runs
/// the shared headless path in-process, and reports the outcome back. It must
/// never call `exit()`: that would end the whole process, foreground Activity
/// included.
///
/// `vm:entry-point` keeps the function (and its callback handle) alive through
/// AOT tree-shaking; without it a release build's handle resolves to nothing
/// and the worker has no Dart to run.
@pragma('vm:entry-point')
Future<void> androidWorkEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plugins with a Dart-side registration (path_provider, shared_preferences)
  // register into a root isolate automatically, but calling this is idempotent
  // and is the documented belt-and-braces for a natively-spawned engine.
  DartPluginRegistrant.ensureInitialized();
  const channel = MethodChannel(kAndroidWorkBackgroundChannel);
  var code = kExitCannotStart;
  var lines = <String>[];
  try {
    final cfg = await channel.invokeMapMethod<String, Object?>('start');
    final args =
        (cfg?['args'] as List?)?.cast<String>() ?? const <String>[kRunDueFlag];
    final outcome = await runHeadlessInProcess(args);
    code = outcome.code;
    lines = [...outcome.diagnostics, ...outcome.summary];
  } catch (e, s) {
    lines = ['airclone: background run crashed: $e', '$s'];
  }
  try {
    await channel.invokeMethod<void>('done', {'code': code, 'summary': lines});
  } catch (_) {
    // The worker has already gone (cancelled, timed out); nothing to tell.
  }
}
