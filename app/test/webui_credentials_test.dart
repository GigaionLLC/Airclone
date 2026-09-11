import 'dart:io';
import 'dart:math';

import 'package:airclone/src/webui/webui_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('airclone_webui_creds');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  String envPath() => '${tmp.path}${Platform.pathSeparator}$kWebUiEnvFileName';

  group('generation', () {
    test('uses the unambiguous alphabet and the full length', () {
      final creds = generateCredentials(random: Random(1));
      expect(creds.password.length, kGeneratedPasswordLength);
      for (final ch in creds.password.split('')) {
        expect(kPasswordAlphabet.contains(ch), isTrue, reason: ch);
      }
      // The characters a human confuses when reading a password off a screen.
      for (final ch in const ['0', 'O', '1', 'l', 'I']) {
        expect(creds.password.contains(ch), isFalse, reason: ch);
      }
    });

    test('two generations differ', () {
      expect(
        generateCredentials().password,
        isNot(generateCredentials().password),
      );
    });
  });

  group('env file parsing', () {
    test('ignores comments and blanks, keeps the value after the first =', () {
      final parsed = parseEnvFile('''
# a comment

$kWebUiUserEnv=someone

$kWebUiPasswordEnv=abc=def=ghi
''');
      expect(parsed[kWebUiUserEnv], 'someone');
      // A password containing "=" must survive intact.
      expect(parsed[kWebUiPasswordEnv], 'abc=def=ghi');
    });

    test('strips quotes an operator is likely to add by hand', () {
      final parsed = parseEnvFile('''
$kWebUiUserEnv="quoted"
$kWebUiPasswordEnv='single'
''');
      expect(parsed[kWebUiUserEnv], 'quoted');
      expect(parsed[kWebUiPasswordEnv], 'single');
    });

    test('round-trips what renderEnvFile writes', () {
      const creds = WebUiCredentials(username: 'airclone', password: 'p@ss=w0');
      final parsed = parseEnvFile(renderEnvFile(creds));
      expect(parsed[kWebUiUserEnv], creds.username);
      expect(parsed[kWebUiPasswordEnv], creds.password);
    });
  });

  group('verifyPassword', () {
    test('accepts only an exact match', () {
      expect(verifyPassword('secret', 'secret'), isTrue);
      expect(verifyPassword('secret', 'Secret'), isFalse);
      expect(verifyPassword('secret', 'secret '), isFalse);
      expect(verifyPassword('secret', ''), isFalse);
      expect(verifyPassword('', ''), isTrue);
    });

    test('a wrong guess of any length is still just wrong', () {
      // Hashing first is what removes the length oracle; this pins the
      // behaviour that makes that true.
      expect(verifyPassword('secret', 'a'), isFalse);
      expect(verifyPassword('secret', 'a' * 10000), isFalse);
    });
  });

  group('loadOrCreateCredentials', () {
    test('generates and persists on first run', () async {
      final result = await loadOrCreateCredentials(
        envFilePath: envPath(),
        environment: const {},
      );
      expect(result.source, WebUiCredentialSource.generated);
      expect(result.credentials.username, kDefaultWebUiUser);
      expect(result.credentials.password.length, kGeneratedPasswordLength);
      expect(File(envPath()).existsSync(), isTrue);
    });

    test('reuses the same credentials on the next run', () async {
      final first = await loadOrCreateCredentials(
        envFilePath: envPath(),
        environment: const {},
      );
      final second = await loadOrCreateCredentials(
        envFilePath: envPath(),
        environment: const {},
      );
      expect(second.source, WebUiCredentialSource.file);
      expect(second.credentials.password, first.credentials.password);
    });

    test('regenerates when the file is gone', () async {
      final first = await loadOrCreateCredentials(
        envFilePath: envPath(),
        environment: const {},
      );
      await File(envPath()).delete();
      final second = await loadOrCreateCredentials(
        envFilePath: envPath(),
        environment: const {},
      );
      expect(second.source, WebUiCredentialSource.generated);
      expect(second.credentials.password, isNot(first.credentials.password));
    });

    test('a file with no password is replaced, and says so', () async {
      await File(envPath()).writeAsString('$kWebUiUserEnv=someone\n');
      final result = await loadOrCreateCredentials(
        envFilePath: envPath(),
        environment: const {},
      );
      expect(result.source, WebUiCredentialSource.generated);
      // Silently issuing a new password looks exactly like "my password
      // stopped working", so the operator has to be told.
      expect(result.warning, isNotNull);
      expect(result.warning, contains('new password'));
    });

    test('the environment wins and nothing is written', () async {
      final result = await loadOrCreateCredentials(
        envFilePath: envPath(),
        environment: const {
          kWebUiUserEnv: 'ops',
          kWebUiPasswordEnv: 'from-the-environment',
        },
      );
      expect(result.source, WebUiCredentialSource.environment);
      expect(result.credentials.username, 'ops');
      expect(result.credentials.password, 'from-the-environment');
      // The entire point of the override is to keep a secret off this disk.
      expect(File(envPath()).existsSync(), isFalse);
    });

    test(
      'an env password with no username still gets the default one',
      () async {
        final result = await loadOrCreateCredentials(
          envFilePath: envPath(),
          environment: const {kWebUiPasswordEnv: 'only-a-password'},
        );
        expect(result.credentials.username, kDefaultWebUiUser);
        expect(result.source, WebUiCredentialSource.environment);
      },
    );

    test('an empty env password does not count as set', () async {
      final result = await loadOrCreateCredentials(
        envFilePath: envPath(),
        environment: const {kWebUiPasswordEnv: ''},
      );
      expect(result.source, WebUiCredentialSource.generated);
    });
  });
}
