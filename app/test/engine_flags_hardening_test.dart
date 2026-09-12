import 'package:airclone/src/state/engine_flags.dart';
import 'package:flutter_test/flutter_test.dart';

/// The engine puts a user's own flags in front of its own, on the rule that
/// rclone lets the last occurrence of a repeated flag win. That reasoning was
/// written down as the thing keeping the rc listener safe, and it is not:
/// last-wins beats a REPEAT, and `--rc-no-auth` is not a repeat of anything.
/// There is no later flag that turns authentication back on.
///
/// rclone's own docs equate rc access to shell access as the user running it,
/// so these are refused outright rather than ordered around.
///
/// The strip lives at the argv site, not in the tokenizer: `parseEngineFlags`
/// is shared with the command console, whose safety classifier needs to SEE a
/// dangerous flag in order to refuse it.
List<String> engineArgv(String raw) =>
    stripRcHardeningOverrides(parseEngineFlags(raw));

void main() {
  group('flags that unpick the rc listener are removed', () {
    test('--rc-no-auth, which ordering never defended against', () {
      expect(engineArgv('--rc-no-auth'), isEmpty);
      expect(engineArgv('--transfers 8 --rc-no-auth --checkers 4'), [
        '--transfers',
        '8',
        '--checkers',
        '4',
      ]);
    });

    test('a refused flag takes its value with it', () {
      // Otherwise the value is left behind as a stray positional argument and
      // rclone sees a command it was never given.
      expect(engineArgv('--rc-addr 0.0.0.0:5572'), isEmpty);
      expect(engineArgv('--rc-user evil --transfers 4'), ['--transfers', '4']);
    });

    test('the --flag=value form is caught too', () {
      expect(engineArgv('--rc-addr=0.0.0.0:5572'), isEmpty);
      expect(engineArgv('--rc-allow-origin=*'), isEmpty);
    });

    test('credentials cannot be replaced with the user own', () {
      expect(engineArgv('--rc-user me --rc-pass me'), isEmpty);
    });

    test('binding elsewhere is refused', () {
      for (final f in ['--rc-addr', '--rc-htpasswd', '--rc-allow-origin']) {
        expect(engineArgv('$f value'), isEmpty, reason: f);
      }
    });
  });

  group('ordinary flags are untouched', () {
    test('the tuning a user actually wants still passes', () {
      expect(engineArgv('--transfers 16 --checkers 8 --fast-list'), [
        '--transfers',
        '16',
        '--checkers',
        '8',
        '--fast-list',
      ]);
    });

    test('quoted values survive', () {
      expect(engineArgv('--user-agent "my agent"'), [
        '--user-agent',
        'my agent',
      ]);
    });

    test('a flag that merely starts like a refused one is kept', () {
      // --rc-job-expire-duration must not be eaten by a prefix match.
      expect(engineArgv('--rc-job-expire-duration 24h'), [
        '--rc-job-expire-duration',
        '24h',
      ]);
    });
  });

  group('the tokenizer stays pure', () {
    test('parseEngineFlags still SEES a dangerous flag', () {
      // The console depends on this: it must be able to recognise a flag in
      // order to refuse it. Stripping in the tokenizer made it invisible
      // instead, which is a worse outcome than leaving it visible.
      expect(parseEngineFlags('--rc-no-auth'), ['--rc-no-auth']);
    });
  });
}
