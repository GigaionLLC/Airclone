import 'package:airclone/src/state/config_encryption.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildConfigEncryptionCommand (pure argv/env/stdin)', () {
    test(
      'encrypt: `config encryption set`, new password twice on stdin, no env',
      () {
        final cmd = buildConfigEncryptionCommand(
          op: ConfigEncryptionOp.encrypt,
          configPath: r'C:\cfg\rclone.conf',
          newPassword: 'hunter2',
        );
        expect(cmd.args, [
          'config',
          'encryption',
          'set',
          '--config',
          r'C:\cfg\rclone.conf',
        ]);
        expect(cmd.env, isEmpty);
        expect(cmd.stdin, 'hunter2\nhunter2\n');
      },
    );

    test('changePassword: OLD in RCLONE_CONFIG_PASS, NEW twice on stdin', () {
      final cmd = buildConfigEncryptionCommand(
        op: ConfigEncryptionOp.changePassword,
        configPath: '/home/u/.config/rclone/rclone.conf',
        currentPassword: 'oldpw',
        newPassword: 'newpw',
      );
      expect(cmd.args.take(3), ['config', 'encryption', 'set']);
      expect(cmd.env, {'RCLONE_CONFIG_PASS': 'oldpw'});
      expect(cmd.stdin, 'newpw\nnewpw\n');
    });

    test('decrypt: `config encryption remove`, current in env, NO stdin', () {
      final cmd = buildConfigEncryptionCommand(
        op: ConfigEncryptionOp.decrypt,
        configPath: '/cfg.conf',
        currentPassword: 'cur',
      );
      expect(cmd.args, [
        'config',
        'encryption',
        'remove',
        '--config',
        '/cfg.conf',
      ]);
      expect(cmd.env, {'RCLONE_CONFIG_PASS': 'cur'});
      expect(cmd.stdin, isNull);
    });

    test('null/empty configPath omits --config (rclone default location)', () {
      for (final p in [null, '']) {
        final cmd = buildConfigEncryptionCommand(
          op: ConfigEncryptionOp.encrypt,
          configPath: p,
          newPassword: 'x',
        );
        expect(cmd.args, ['config', 'encryption', 'set'], reason: '"$p"');
        expect(cmd.args, isNot(contains('--config')));
      }
    });

    test(
      'the NEW password never appears in argv (stdin-only, not process list)',
      () {
        final cmd = buildConfigEncryptionCommand(
          op: ConfigEncryptionOp.encrypt,
          configPath: '/c.conf',
          newPassword: 's3cr3t-value',
        );
        expect(cmd.args.join(' '), isNot(contains('s3cr3t-value')));
      },
    );

    test(
      'missing/empty new password is refused (never an unprotected encrypt)',
      () {
        for (final pw in [null, '']) {
          expect(
            () => buildConfigEncryptionCommand(
              op: ConfigEncryptionOp.encrypt,
              newPassword: pw,
            ),
            throwsArgumentError,
            reason: '"$pw"',
          );
        }
      },
    );

    test(
      'missing current password is refused for change + decrypt (no hang)',
      () {
        expect(
          () => buildConfigEncryptionCommand(
            op: ConfigEncryptionOp.changePassword,
            newPassword: 'new',
            currentPassword: null,
          ),
          throwsArgumentError,
        );
        expect(
          () => buildConfigEncryptionCommand(
            op: ConfigEncryptionOp.decrypt,
            currentPassword: '',
          ),
          throwsArgumentError,
        );
      },
    );

    test('changePassword still requires the new password too', () {
      expect(
        () => buildConfigEncryptionCommand(
          op: ConfigEncryptionOp.changePassword,
          currentPassword: 'old',
          newPassword: '',
        ),
        throwsArgumentError,
      );
    });
  });
}
