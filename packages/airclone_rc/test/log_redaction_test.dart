import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

void main() {
  group('redactEngineLine', () {
    test('removes a literal session secret wherever it appears', () {
      const pass = 'p4ssw0rd-from-this-session';
      final out = redactEngineLine(
        'GET /operations/list with $pass and again $pass',
        sessionSecrets: const [pass],
      );
      expect(out, isNot(contains(pass)));
      expect(out, 'GET /operations/list with <redacted> and again <redacted>');
    });

    test('removes the Authorization header rclone echoes at -vv', () {
      final out = redactEngineLine(
        'DEBUG : HTTP REQUEST\r\nAuthorization: Basic YWlyY2xvbmU6c2VjcmV0\r\nAccept: */*',
        sessionSecrets: const [],
      );
      expect(out, contains('Authorization: Basic <redacted>'));
      expect(out, isNot(contains('YWlyY2xvbmU6c2VjcmV0')));
      // The rest of the line survives: a redactor that eats the message is a
      // redactor people turn off.
      expect(out, contains('Accept: */*'));
    });

    test(
      'keeps the auth scheme, because which auth failed is the useful half',
      () {
        expect(
          redactEngineLine('Authorization: Bearer abc.def.ghi'),
          'Authorization: Bearer <redacted>',
        );
      },
    );

    test('removes a secret-ish flag value in either argv shape', () {
      expect(
        redactEngineLine('rclone rcd --rc-pass hunter2 --rc-addr 127.0.0.1:0'),
        'rclone rcd --rc-pass <redacted> --rc-addr 127.0.0.1:0',
      );
      expect(
        redactEngineLine('--config-password=hunter2'),
        '--config-password=<redacted>',
      );
    });

    test('removes credentials embedded in a URL', () {
      expect(
        redactEngineLine(
          'failed to connect to https://bob:s3cret@example.com/x',
        ),
        'failed to connect to https://<credentials>@example.com/x',
      );
    });

    test('leaves an ordinary line alone', () {
      const line =
          'ERROR : papers/a.pdf: Failed to copy: googleapi: Error 403: rateLimitExceeded';
      expect(redactEngineLine(line, sessionSecrets: const ['unrelated']), line);
    });

    test('ignores a secret too short to be one', () {
      // A one-character "secret" would match half the alphabet in every line,
      // and redacting the message into uselessness protects nothing.
      expect(
        redactEngineLine('a normal sentence', sessionSecrets: const ['a', '']),
        'a normal sentence',
      );
    });
  });
}
