import 'package:airclone/src/state/console/console_command.dart';
import 'package:airclone/src/state/console/rclone_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsoleCommand parsing (argv, not a shell)', () {
    test('splits verb / args / flags, quote-aware', () {
      final c = ConsoleCommand.parse(
        'copy gdrive:Photos "s3:my backup" --transfers 8',
      );
      expect(c.verb, 'copy');
      expect(c.args, ['gdrive:Photos', 's3:my backup', '--transfers', '8']);
      expect(c.flags, ['--transfers']);
      expect(c.isEmpty, isFalse);
    });

    test('empty / whitespace input', () {
      expect(ConsoleCommand.parse('').isEmpty, isTrue);
      expect(ConsoleCommand.parse('   ').isEmpty, isTrue);
      expect(ConsoleCommand.parse('ls').args, isEmpty);
    });

    test(
      'toRcParams dispatches command + arg verbatim (flags stay in arg)',
      () {
        final p = ConsoleCommand.parse(
          'lsjson gdrive: --max-depth 1',
        ).toRcParams();
        expect(p['command'], 'lsjson');
        expect(p['arg'], ['gdrive:', '--max-depth', '1']);
        expect(p['returnType'], 'COMBINED_OUTPUT');
      },
    );

    test('shell metacharacters are inert — they are just arg tokens', () {
      // Nothing is handed to a shell; ";" and "&&" are literal path chars here.
      final c = ConsoleCommand.parse(r'ls "gdrive:a; rm -rf b"');
      expect(c.verb, 'ls');
      expect(c.args, ['gdrive:a; rm -rf b']);
    });

    test('preview is rclone-prefixed and re-quotes spaced tokens', () {
      expect(
        ConsoleCommand.parse('copy "a b:" c:').preview(),
        'rclone copy "a b:" c:',
      );
    });

    test('withDryRun is idempotent', () {
      expect(
        ConsoleCommand.parse('sync a: b:').withDryRun().tokens.last,
        '--dry-run',
      );
      final already = ConsoleCommand.parse('sync a: b: --dry-run');
      expect(already.withDryRun().tokens, already.tokens);
      expect(ConsoleCommand.parse('sync a: b: -n').isDryRun, isTrue);
    });
  });

  group('safety classification (the allowlist + destructive detection)', () {
    test('safe verbs are safe', () {
      for (final v in [
        'ls',
        'lsjson',
        'size',
        'cat',
        'about',
        'copy',
        'tree',
      ]) {
        expect(ConsoleCommand.parse('$v x:').tier, CommandTier.safe, reason: v);
      }
    });

    test('destructive verbs are destructive', () {
      for (final v in [
        'delete',
        'purge',
        'sync',
        'move',
        'dedupe',
        'cleanup',
        'rmdirs',
      ]) {
        expect(
          ConsoleCommand.parse('$v x:').tier,
          CommandTier.destructive,
          reason: v,
        );
      }
    });

    test('blocked verbs (secret/server/meta) are blocked', () {
      for (final v in [
        'config',
        'reveal',
        'mount',
        'serve',
        'rc',
        'rcd',
        'authorize',
      ]) {
        expect(
          ConsoleCommand.parse('$v x').tier,
          CommandTier.blocked,
          reason: v,
        );
      }
    });

    test('an UNKNOWN verb is blocked (allowlist by construction)', () {
      expect(ConsoleCommand.parse('frobnicate x:').tier, CommandTier.blocked);
      expect(ConsoleCommand.parse('rm -rf /').tier, CommandTier.blocked);
    });

    test('obscure is blocked (its arg is a plaintext password)', () {
      expect(ConsoleCommand.parse('obscure hunter2').tier, CommandTier.blocked);
    });

    test('backend is destructive (subcommands can delete)', () {
      expect(
        ConsoleCommand.parse('backend cleanup-hidden s3:b').tier,
        CommandTier.destructive,
      );
    });

    test('a server/config/dump global flag blocks ANY verb (critical)', () {
      // A safe verb + --rc could spin up an unauthenticated rc server.
      expect(
        ConsoleCommand.parse('cat r:x --rc --rc-no-auth').tier,
        CommandTier.blocked,
      );
      expect(
        ConsoleCommand.parse('ls r: --rc-addr 0.0.0.0:5572').tier,
        CommandTier.blocked,
      );
      expect(
        ConsoleCommand.parse('lsjson r: --dump headers').tier,
        CommandTier.blocked,
      );
      expect(
        ConsoleCommand.parse('ls r: --config other.conf').tier,
        CommandTier.blocked,
      );
    });

    test('a destructive FLAG promotes a safe verb to destructive', () {
      expect(ConsoleCommand.parse('copy a: b:').tier, CommandTier.safe);
      expect(
        ConsoleCommand.parse('copy a: b: --delete-excluded').tier,
        CommandTier.destructive,
      );
      // even with =value form
      expect(
        ConsoleCommand.parse('copy a: b: --delete-during=true').tier,
        CommandTier.destructive,
      );
    });

    test('classifyTier is on tokens, not a raw-string match', () {
      // "delete" appearing inside a path must NOT trip destructive detection.
      expect(
        ConsoleCommand.parse('ls "gdrive:to-delete/"').tier,
        CommandTier.safe,
      );
    });
  });

  // Microsoft Store certification, 2026-07-29, policy 10.1.2.10: a reviewer ran
  // `config create local local`, got a refusal that named no alternative, and
  // logged it as "Unusable Feature: Create a local remote". A blocked verb must
  // always say where to do the thing instead.
  group('blockedMessage', () {
    String messageFor(String line) {
      final c = ConsoleCommand.parse(line);
      return blockedMessage(c.verb, c.flags);
    }

    test('config points at the in-app way to create a remote', () {
      final msg = messageFor('config create local local');
      expect(msg, contains('config'));
      expect(msg, contains('CLOUD'));
    });

    test(
      'every blocked verb in the catalog offers an alternative or a reason',
      () {
        final blocked = kRcloneCommands.values.where(
          (c) => c.tier == CommandTier.blocked,
        );
        expect(blocked, isNotEmpty);
        for (final c in blocked) {
          final msg = blockedMessage(c.name, const []);
          expect(msg, startsWith('Blocked:'), reason: c.name);
          // Longer than the bare refusal => it carries guidance. The few meta
          // verbs with no in-app equivalent (gendocs, gitannex) are exempt.
          if (!const {'gendocs', 'gitannex'}.contains(c.name)) {
            expect(
              msg.length,
              greaterThan(100),
              reason: '${c.name} refuses without saying what to do instead',
            );
          }
        }
      },
    );

    test('an unknown verb is reported as unknown, not as a secret leak', () {
      final msg = messageFor('lss remote:');
      expect(msg, contains('Unknown command'));
      expect(msg, isNot(contains('leaks secrets')));
    });

    test('a blocked FLAG blames the flag, not the verb', () {
      final msg = messageFor('ls remote: --rc-addr :5572');
      expect(msg, contains('--rc-addr'));
      // "ls" itself is perfectly runnable — the message must not imply otherwise.
      expect(msg, isNot(contains('"ls" is not permitted')));
    });
  });
}
