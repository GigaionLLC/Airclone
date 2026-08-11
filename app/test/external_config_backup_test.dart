import 'dart:convert';
import 'dart:io';

import 'package:airclone/src/state/config_io.dart';
import 'package:airclone/src/state/external_config_backup.dart';
import 'package:flutter_test/flutter_test.dart';

/// The outside-the-sandbox backup is the ONE place Airclone deliberately writes
/// config content somewhere other apps can reach, so the rules around it are the
/// thing worth pinning: where the file goes, that an encrypted backup really is
/// an opaque envelope, and that a plaintext one is recognised as plaintext.
///
/// The controller itself needs a device (platform channels for the vault and the
/// storage root), so what is tested here is the pure layer plus the real
/// seal/open round trip the controller performs.
void main() {
  group('paths', () {
    test('the backup dir sits beside the user files, not inside the app', () {
      // /storage/emulated/0/Android/data/<pkg> would be deleted with the app —
      // the whole point is a location the OS does NOT clean up on uninstall.
      expect(
        externalBackupDir('/storage/emulated/0'),
        '/storage/emulated/0/Airclone',
      );
      expect(
        externalBackupDir('/storage/emulated/0'),
        isNot(contains('/Android/')),
      );
    });

    test('each mode has its own filename, and off has none', () {
      const dir = '/storage/emulated/0/Airclone';
      expect(
        externalBackupPath(dir, ExternalBackupMode.encrypted),
        '$dir/$kEncryptedBackupName',
      );
      expect(
        externalBackupPath(dir, ExternalBackupMode.plaintext),
        '$dir/$kPlaintextBackupName',
      );
      expect(externalBackupPath(dir, ExternalBackupMode.off), isNull);
    });

    test('the plaintext copy is named so rclone itself can open it', () {
      // If Airclone is gone, this file should still be usable directly.
      expect(kPlaintextBackupName, 'rclone.conf');
    });

    test('the two filenames differ, so a mode switch cannot collide', () {
      expect(kEncryptedBackupName, isNot(kPlaintextBackupName));
    });
  });

  group('backup content', () {
    const config = '''
[work]
type = s3
access_key_id = AKIAEXAMPLE
secret_access_key = examplesecret
''';

    test(
      'an encrypted backup is an opaque envelope with no secret in the bytes',
      () async {
        // Cheap KDF params: the production Argon2id band (64 MiB) would make the
        // test slow, and what is under test is the format, not the work factor.
        const cheap = Argon2Params(memory: 64, iterations: 1, parallelism: 1);
        final sealed = await sealConfigEnvelope(
          config,
          'correct horse',
          kdf: cheap,
        );

        // Nothing recoverable by grepping the file.
        final asText = String.fromCharCodes(sealed);
        expect(asText, isNot(contains('examplesecret')));
        expect(asText, isNot(contains('AKIAEXAMPLE')));
        expect(asText, isNot(contains('[work]')));

        // findExternalBackup classifies by CONTENT, so this must sniff as ours.
        expect(
          detectConfigFormat(sealed),
          ConfigFormat.aircloneEnvelope,
          reason: 'a renamed/copied backup must still be recognised',
        );

        // And it round-trips back to the same config.
        expect(await openConfigEnvelope(sealed, 'correct horse'), config);
        await expectLater(
          openConfigEnvelope(sealed, 'wrong'),
          throwsA(isA<WrongPassphrase>()),
        );
      },
    );

    test('a plaintext backup sniffs as a plain rclone config', () {
      // The danger the UI warns about is real and this proves it: the bytes are
      // the credentials, readable by anything that can read the file.
      final bytes = utf8.encode(config);
      expect(detectConfigFormat(bytes), ConfigFormat.rcloneIni);
      expect(utf8.decode(bytes), contains('examplesecret'));
    });
  });

  group('findExternalBackup', () {
    test('returns null off Android, without touching the filesystem', () async {
      // The test host is desktop, where the feature is unsupported — a fresh
      // desktop run must never probe shared-storage paths that don't exist.
      expect(backupSupported, isFalse, reason: 'test host is not Android');
      expect(await findExternalBackup(), isNull);
    });
  });

  group('atomic write shape', () {
    test('a rename-into-place leaves no partial file behind', () async {
      // Mirrors what _write does: the user's only copy after an uninstall must
      // never be a truncated file, so the write goes to `.part` and renames.
      final dir = await Directory.systemTemp.createTemp('airclone-backup-test');
      addTearDown(() => dir.delete(recursive: true));

      final target = File('${dir.path}/$kPlaintextBackupName');
      final partial = File('${target.path}.part');
      await partial.writeAsBytes(
        utf8.encode('[a]\ntype = local\n'),
        flush: true,
      );
      await partial.rename(target.path);

      expect(await target.exists(), isTrue);
      expect(await partial.exists(), isFalse);
      expect(await target.readAsString(), contains('type = local'));
    });
  });
}
