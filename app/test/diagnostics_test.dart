import 'package:airclone/src/state/diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The diagnostics log is the one place Airclone lets failure details leave the
/// device — by the user's own hand, into a bug report. Redaction is therefore
/// the load-bearing part: it runs at INGEST, so an export path that forgot to
/// sanitise still cannot leak. These tests pin what must never survive it.
void main() {
  redactionGapsClosed();
  group('redactSensitive', () {
    test('strips rclone config secrets by key name', () {
      const raw = '''
[work]
type = s3
access_key_id = AKIAIOSFODNN7EXAMPLE
secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
pass = zX9_obscured_value
''';
      final out = redactSensitive(raw);
      expect(out, isNot(contains('wJalrXUtnFEMI')));
      expect(out, isNot(contains('zX9_obscured_value')));
      expect(out, contains('<redacted>'));
      // Non-secret structure survives — that is what makes a report useful.
      expect(out, contains('type = s3'));
    });

    test('strips an OAuth token blob whole, not just its first field', () {
      const raw =
          'token = {"access_token":"ya29.abc","refresh_token":"1//xyz"} ok';
      final out = redactSensitive(raw);
      expect(out, isNot(contains('ya29.abc')));
      expect(out, isNot(contains('1//xyz')));
      expect(out, contains('ok'));
    });

    test('strips credentials embedded in a URL', () {
      final out = redactSensitive(
        'dial https://alice:hunter2@webdav.example.com/dav failed',
      );
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('alice')));
      expect(out, contains('webdav.example.com'));
    });

    test('strips Authorization headers', () {
      final out = redactSensitive('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9');
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
    });

    test('strips email addresses', () {
      expect(
        redactSensitive('account jane.doe+x@example.com denied'),
        'account <email> denied',
      );
    });

    test('replaces the home-directory NAME but keeps the rest of the path', () {
      expect(
        redactSensitive(r'C:\Users\jbraun\AppData\Roaming\rclone\rclone.conf'),
        r'C:\Users\<user>\AppData\Roaming\rclone\rclone.conf',
      );
      expect(
        redactSensitive('/home/jbraun/.config/rclone/rclone.conf'),
        '/home/<user>/.config/rclone/rclone.conf',
      );
      expect(
        redactSensitive('/Users/jbraun/Library/Application Support/x'),
        '/Users/<user>/Library/Application Support/x',
      );
    });

    test('leaves ordinary error text alone', () {
      const raw = 'directory not found: /storage/emulated/0/DCIM/Camera';
      expect(redactSensitive(raw), raw);
    });
  });

  group('DiagEntry.format', () {
    test('renders a one-line event', () {
      final e = DiagEntry(
        time: DateTime(2026, 8, 11, 9, 4, 7),
        level: DiagLevel.error,
        area: 'config-import',
        message: 'Merge failed',
      );
      expect(e.format(), '09:04:07  ERROR  config-import  Merge failed');
    });

    test('indents a multi-line detail under its event', () {
      final e = DiagEntry(
        time: DateTime(2026, 8, 11, 9, 4, 7),
        level: DiagLevel.warning,
        area: 'engine',
        message: 'restarted',
        detail: 'line one\nline two',
      );
      final lines = e.format().split('\n');
      expect(lines, hasLength(3));
      expect(lines[1].startsWith('           line one'), isTrue);
      expect(lines[2].startsWith('           line two'), isTrue);
    });
  });

  group('buildDiagnosticsReport', () {
    const env = DiagnosticsEnvironment(
      appVersion: '0.6.1',
      platform: 'android',
      osVersion: '15',
      installChannel: 'playStore',
      engineVersion: 'v1.74.0',
      engineMode: 'binary',
    );

    test('header carries versions and the install channel', () {
      final out = buildDiagnosticsReport(env, const []);
      expect(out, contains('App:      0.6.1'));
      expect(out, contains('Install:  playStore'));
      expect(out, contains('Engine:   v1.74.0'));
      expect(out, contains('(nothing recorded this session)'));
    });

    test('lists entries oldest first', () {
      final out = buildDiagnosticsReport(env, [
        DiagEntry(
          time: DateTime(2026, 8, 11, 9),
          level: DiagLevel.info,
          area: 'engine',
          message: 'first',
        ),
        DiagEntry(
          time: DateTime(2026, 8, 11, 10),
          level: DiagLevel.error,
          area: 'engine',
          message: 'second',
        ),
      ]);
      expect(out.indexOf('first'), lessThan(out.indexOf('second')));
      expect(out, contains('Entries:  2'));
    });
  });

  group('DiagnosticsLog', () {
    test('redacts at ingest and bounds the ring', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final log = container.read(diagnosticsProvider.notifier);
      List<DiagEntry> entries() => container.read(diagnosticsProvider);

      log.record(DiagLevel.error, 'x', 'pass = supersecret');
      expect(entries().single.message, isNot(contains('supersecret')));

      for (var i = 0; i < kDiagnosticsCapacity + 25; i++) {
        log.record(DiagLevel.info, 'x', 'event $i');
      }
      expect(entries(), hasLength(kDiagnosticsCapacity));
      // The oldest entries fell off the front; the newest is still there.
      expect(entries().last.message, 'event ${kDiagnosticsCapacity + 24}');

      log.clear();
      expect(entries(), isEmpty);
    });
  });
}

/// Gaps a security sweep found in the redactor, each one a shape that reached
/// the ring intact. Called from main() below the existing groups.
void redactionGapsClosed() {
  group('argv-shaped secrets', () {
    test('--rc-pass with a SPACE, which the k=v rule cannot see', () {
      // The engine client's own comment says the ring redacts rc credentials at
      // ingest "as a second line of defence" when -vv echoes them. For this
      // shape that was not true.
      expect(redactSensitive('--rc-pass hunter2'), isNot(contains('hunter2')));
      expect(
        redactSensitive(
          'rclone rcd --rc-user airclone --rc-pass s3cr3t --rc-serve',
        ),
        isNot(contains('s3cr3t')),
      );
    });

    test('other backend password flags too', () {
      expect(redactSensitive('--sftp-pass abc123'), isNot(contains('abc123')));
      expect(redactSensitive('--client-secret zzz'), isNot(contains('zzz')));
    });

    test('a flag followed by another flag is not eaten', () {
      final out = redactSensitive('--rc-pass --rc-serve');
      expect(out, contains('--rc-serve'));
    });
  });

  group('presigned URL signatures', () {
    test('the S3 signature is the credential', () {
      final out = redactSensitive(
        'https://b.s3.amazonaws.com/o?X-Amz-Credential=AKIA&X-Amz-Signature=deadbeefcafe',
      );
      expect(out, isNot(contains('deadbeefcafe')));
    });

    test('Azure SAS parameters', () {
      final out = redactSensitive(
        'https://a.blob.core.windows.net/c?sv=2021&sig=AbC123%3D&se=2026',
      );
      expect(out, isNot(contains('AbC123')));
    });

    test('the host survives, because that is the useful part', () {
      final out = redactSensitive(
        'https://b.s3.amazonaws.com/o?X-Amz-Signature=zzz',
      );
      expect(out, contains('b.s3.amazonaws.com'));
    });
  });

  group('private keys', () {
    test('a PEM block has no = and no keyword, so nothing else caught it', () {
      const pem =
          '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg\nkqhkiG9w0B\n-----END PRIVATE KEY-----';
      final out = redactSensitive('failed to read key: $pem');
      // Assert the PROPERTY, not the placeholder text: the generic `key = v`
      // rule runs after this one and rewrites the marker, which is cosmetic.
      // What matters is that no byte of the key survives.
      expect(out, isNot(contains('MIIEvQIBADANBg')));
      expect(out, isNot(contains('BEGIN')));
      expect(out, contains('redacted'));
    });

    test('an RSA-labelled block too', () {
      const pem =
          '-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----';
      expect(redactSensitive(pem), isNot(contains('AAAA')));
    });
  });
}
