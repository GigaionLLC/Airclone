import 'package:airclone/src/rclone/rclone_log.dart';
import 'package:airclone/src/state/diagnostics.dart';
import 'package:airclone/src/state/engine_log_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The join between the engine layer and the app's evidence channel.
///
/// The rclone clients no longer call `logDiagnostic` themselves — they call a
/// sink, and Airclone passes [logEngineEvent]. That indirection is exactly the
/// kind that goes quietly wrong: wire nothing and engine failures vanish from
/// bug reports, wire something that bypasses the ring and they arrive
/// unredacted. Both are invisible until someone needs a report to be right.
void main() {
  group('logEngineEvent', () {
    test('engine events reach the ring, redacted at ingest', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final log = container.read(diagnosticsProvider.notifier);
      attachGlobalDiagnostics(log);

      // The shape that made this matter: at -vv rclone echoes the rc
      // credentials it was handed, and those lines are what a failure report
      // carries out of the machine.
      logEngineEvent(
        RcloneLogLevel.error,
        'engine',
        'ERROR : rcd: --rc-pass hunter2 refused',
        detail: 'pass = alsosecret',
      );

      final entry = container.read(diagnosticsProvider).single;
      expect(entry.area, 'engine');
      expect(entry.level, DiagLevel.error);
      expect(entry.message, isNot(contains('hunter2')));
      expect(entry.detail, isNot(contains('alsosecret')));
      expect(entry.message, contains('rcd:'), reason: 'still readable');
    });

    test('every engine level maps to a diagnostics level', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      attachGlobalDiagnostics(container.read(diagnosticsProvider.notifier));

      logEngineEvent(RcloneLogLevel.info, 'engine', 'i');
      logEngineEvent(RcloneLogLevel.warning, 'engine', 'w');
      logEngineEvent(RcloneLogLevel.error, 'engine', 'e');

      expect(container.read(diagnosticsProvider).map((e) => e.level), [
        DiagLevel.info,
        DiagLevel.warning,
        DiagLevel.error,
      ]);
    });

    test('the default sink says nothing at all', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      attachGlobalDiagnostics(container.read(diagnosticsProvider.notifier));

      // What a host that wires no sink gets. Silence is the point: these lines
      // can carry credentials, so a package must not log them by default.
      discardRcloneLog(RcloneLogLevel.error, 'engine', 'ERROR : something');

      expect(container.read(diagnosticsProvider), isEmpty);
    });
  });
}
