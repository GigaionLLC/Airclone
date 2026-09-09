import 'package:airclone/src/state/console/console_command.dart';
import 'package:flutter_test/flutter_test.dart';

/// The console dispatches through `core/command`, which re-execs a FRESH rclone.
/// That child inherits the engine's environment but not its `--config`, and
/// rclone reports a config it cannot open as an EMPTY one — no error — so a
/// child left to resolve its own can answer `didn't find section in config file`
/// for every remote the sidebar is happily listing. Pinning the engine's own
/// config onto the argv is what removes the divergence; it used to happen only
/// when the user had set an override, leaving the default-config case exposed.
void main() {
  group('withConfigArg', () {
    test('pins the engine config onto the child argv', () {
      final cmd = ConsoleCommand.parse('ls remote:');
      expect(
        withConfigArg(cmd, r'C:\Users\me\AppData\Roaming\rclone\rclone.conf'),
        [
          'remote:',
          '--config',
          r'C:\Users\me\AppData\Roaming\rclone\rclone.conf',
        ],
      );
    });

    test('leaves the argv alone when the path is unknown', () {
      // Unresolvable config: degrade to rclone's own resolution rather than
      // failing a command the user asked for.
      final cmd = ConsoleCommand.parse('ls remote:');
      expect(withConfigArg(cmd, null), ['remote:']);
      expect(withConfigArg(cmd, ''), ['remote:']);
    });

    test("does not override a --config the USER typed", () {
      // rclone lets the last occurrence of a repeated flag win, so appending
      // ours after theirs would silently ignore an explicit instruction.
      final cmd = ConsoleCommand.parse('ls remote: --config other.conf');
      expect(withConfigArg(cmd, 'engine.conf'), [
        'remote:',
        '--config',
        'other.conf',
      ]);
      final joined = ConsoleCommand.parse('ls remote: --config=other.conf');
      expect(withConfigArg(joined, 'engine.conf'), [
        'remote:',
        '--config=other.conf',
      ]);
    });

    test('keeps the rest of the argv verbatim and appends at the end', () {
      final cmd = ConsoleCommand.parse('lsjson remote:dir --max-depth 1');
      expect(withConfigArg(cmd, 'engine.conf'), [
        'remote:dir',
        '--max-depth',
        '1',
        '--config',
        'engine.conf',
      ]);
    });

    test('a bare verb with no args still gets the config', () {
      final cmd = ConsoleCommand.parse('listremotes');
      expect(withConfigArg(cmd, 'engine.conf'), ['--config', 'engine.conf']);
    });
  });
}
