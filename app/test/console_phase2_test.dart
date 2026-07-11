import 'package:airclone/src/state/console/console_autocomplete.dart';
import 'package:airclone/src/state/console/console_command.dart';
import 'package:airclone/src/state/console/console_docs.dart';
import 'package:airclone/src/state/console/console_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('secret redaction', () {
    test('redacts a secret flag value (space and =value forms)', () {
      expect(redactTokens(['sync', 'a:', 'b:', '--sftp-pass', 'hunter2']), [
        'sync',
        'a:',
        'b:',
        '--sftp-pass',
        kRedacted,
      ]);
      expect(redactTokens(['config', '--s3-secret-access-key=AKIAxxx']), [
        'config',
        '--s3-secret-access-key=$kRedacted',
      ]);
    });

    test('non-secret flags and their values are untouched', () {
      expect(redactTokens(['copy', 'a:', 'b:', '--transfers', '8']), [
        'copy',
        'a:',
        'b:',
        '--transfers',
        '8',
      ]);
    });

    test('redacts secrets embedded in a connection-string arg', () {
      expect(redactTokens([':sftp,host=h,pass=xxx:path']), [
        ':sftp,host=h,pass=$kRedacted:path',
      ]);
    });

    test(
      'output scrubber hides auth headers / tokens / bearer / AWS creds',
      () {
        expect(
          redactOutputLine('Authorization: Bearer abc.def.ghi'),
          contains(kRedacted),
        );
        expect(
          redactOutputLine('sent Bearer eyJhbGci123'),
          isNot(contains('eyJhbGci123')),
        );
        expect(
          redactOutputLine('?access_token=SEKRET&x=1'),
          isNot(contains('SEKRET')),
        );
        expect(
          redactOutputLine('Credential=AKIA/20240101/us'),
          contains(kRedacted),
        );
        // ordinary output is left alone
        expect(
          redactOutputLine('Copied (new) 3 files'),
          'Copied (new) 3 files',
        );
      },
    );

    test('detects credential-dumping verbosity in all its forms', () {
      for (final d in [
        'copy a: b: -vv',
        'ls a: -vvvv',
        'ls a: -vvP',
        'copy a: b: -v -v',
        'ls a: --dump headers',
        'ls a: --dump-bodies',
        'ls a: --verbose 2',
        'ls a: --log-level DEBUG',
        'ls a: --log-level=DEBUG',
      ]) {
        expect(hasCredentialDump(ConsoleCommand.parse(d)), isTrue, reason: d);
      }
      expect(hasCredentialDump(ConsoleCommand.parse('ls a: -v')), isFalse);
      expect(hasCredentialDump(ConsoleCommand.parse('ls a:')), isFalse);
      expect(
        hasCredentialDump(ConsoleCommand.parse('ls a: --log-level INFO')),
        isFalse,
      );
    });

    test('secret keyword ANYWHERE in the flag name is redacted (de-anchored)', () {
      for (final f in [
        '--crypt-password2',
        '--drive-service-account-credentials',
        '--sftp-key-pem',
      ]) {
        expect(
          redactTokens(['copy', 'a:', 'b:', f, 'SEKRET']).join(' '),
          isNot(contains('SEKRET')),
          reason: f,
        );
      }
    });

    test('compound connection-string secret keys are redacted', () {
      expect(
        redactTokens([
          ':s3,access_key_id=AKIA,secret_access_key=REALSECRET:b',
        ]).join(),
        isNot(contains('REALSECRET')),
      );
    });

    test('redactedPreview quotes + redacts', () {
      expect(
        redactedPreview(ConsoleCommand.parse('sync a: b: --sftp-pass secret')),
        'rclone sync a: b: --sftp-pass $kRedacted',
      );
    });
  });

  group('doc links', () {
    test('command + flag URLs', () {
      expect(
        RcloneDocs.commandUrl('copy'),
        'https://rclone.org/commands/rclone_copy/',
      );
      expect(
        RcloneDocs.commandUrl('lsjson'),
        'https://rclone.org/commands/rclone_lsjson/',
      );
      expect(RcloneDocs.commandUrl('frobnicate'), isNull);
      expect(
        RcloneDocs.flagUrl('--transfers'),
        'https://rclone.org/flags/#transfers',
      );
      expect(
        RcloneDocs.flagUrl('--max-depth=1'),
        'https://rclone.org/flags/#max-depth',
      );
    });

    test('forToken routes verb→command, flag→flags, path→null', () {
      expect(
        RcloneDocs.forToken('copy', isFirst: true),
        contains('rclone_copy'),
      );
      expect(
        RcloneDocs.forToken('--dry-run', isFirst: false),
        contains('flags/#dry-run'),
      );
      expect(RcloneDocs.forToken('gdrive:x', isFirst: false), isNull);
    });
  });

  group('autocomplete', () {
    test('token[0] suggests subcommands by prefix, blocked hidden', () {
      final s = suggestFor('ls');
      expect(s.map((x) => x.value), contains('ls'));
      expect(s.map((x) => x.value), contains('lsjson'));
      // "config" (blocked) never suggested
      expect(suggestFor('conf').map((x) => x.value), isNot(contains('config')));
      // prefix ranks first
      expect(s.first.value.startsWith('ls'), isTrue);
    });

    test('a "-" token suggests flags; a plain token suggests remotes', () {
      expect(
        suggestFor('copy a: --tr').map((x) => x.value),
        contains('--transfers'),
      );
      final remotes = suggestFor('copy ', remotes: ['gdrive', 's3']);
      expect(remotes.map((x) => x.value), containsAll(['gdrive:', 's3:']));
    });

    test('destructive verbs/flags are flagged for styling', () {
      expect(
        suggestFor('del').firstWhere((x) => x.value == 'delete').destructive,
        isTrue,
      );
      expect(
        suggestFor(
          'sync a: b: --delete-ex',
        ).firstWhere((x) => x.value == '--delete-excluded').destructive,
        isTrue,
      );
    });

    test('applySuggestion replaces the current token + trailing space', () {
      expect(applySuggestion('ls', 'lsjson'), 'lsjson ');
      expect(applySuggestion('copy gdr', 'gdrive:'), 'copy gdrive: ');
      expect(applySuggestion('copy ', 'gdrive:'), 'copy gdrive: ');
    });
  });
}
