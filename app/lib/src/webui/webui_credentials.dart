/// The Web UI's login credentials: generated on first launch, kept in an env
/// file, reused on every later run.
///
/// The rule, in full: if the env file exists and parses, those credentials are
/// used. If it is missing, unreadable or malformed, a **fresh** pair is
/// generated and written. There is no third state and no "no password" state —
/// a Web UI with no login is shell access on a TCP port (rclone's own words for
/// its rc API, which this ultimately fronts), so it is not offered, not even
/// behind a flag.
///
/// Anything in the process environment wins over the file, and suppresses
/// writing one at all. That is the escape hatch for a real deployment —
/// systemd `Environment=`, a Docker `-e`, a secrets mount — where a credential
/// on disk is the thing you were trying to avoid.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Environment variable (and env-file key) for the username.
const String kWebUiUserEnv = 'AIRCLONE_WEBUI_USER';

/// Environment variable (and env-file key) for the password.
const String kWebUiPasswordEnv = 'AIRCLONE_WEBUI_PASSWORD';

/// The filename inside the app-support directory.
const String kWebUiEnvFileName = 'webui.env';

/// The default username. Not a secret and not meant to be one — the password
/// carries all the entropy, and a predictable username saves the operator from
/// having to look up two things to log in.
const String kDefaultWebUiUser = 'airclone';

/// Generated-password length. 24 characters from a 54-symbol alphabet is a
/// little over 138 bits, which is far past the point where online guessing —
/// already throttled — is the weakest link.
const int kGeneratedPasswordLength = 24;

/// Alphabet for generated passwords: no `0`/`O`, no `1`/`l`/`I`, and no
/// punctuation. This password gets copied out of a terminal, read off a screen
/// and occasionally typed on a phone, and an ambiguous glyph costs far more in
/// practice than the ~3 bits of entropy that excluding them costs.
const String kPasswordAlphabet =
    'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

/// A username/password pair for the Web UI.
class WebUiCredentials {
  const WebUiCredentials({required this.username, required this.password});

  final String username;
  final String password;

  /// Whether both halves are non-empty. An env file that sets one and not the
  /// other is treated as malformed rather than half-honoured.
  bool get isComplete => username.isNotEmpty && password.isNotEmpty;
}

/// Where the credentials this run is using actually came from. Surfaced in the
/// GUI and the startup log so an operator is never guessing which password is
/// live — the commonest support question this feature can produce.
enum WebUiCredentialSource {
  /// Read from the process environment; nothing was written to disk.
  environment,

  /// Read from an existing env file.
  file,

  /// Freshly generated and written to the env file.
  generated,
}

/// Credentials plus where they came from.
class WebUiCredentialResult {
  const WebUiCredentialResult(this.credentials, this.source, {this.warning});

  final WebUiCredentials credentials;
  final WebUiCredentialSource source;

  /// A non-fatal problem worth telling the operator about — most importantly
  /// "your env file was unreadable so these are NEW credentials", which
  /// otherwise looks like the password mysteriously stopped working.
  final String? warning;
}

/// Generates a fresh credential pair.
///
/// [random] must be a CSPRNG in production; it is injectable only so tests can
/// be deterministic. The default is [Random.secure].
WebUiCredentials generateCredentials({
  Random? random,
  String username = kDefaultWebUiUser,
  int length = kGeneratedPasswordLength,
}) {
  final rnd = random ?? Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.write(kPasswordAlphabet[rnd.nextInt(kPasswordAlphabet.length)]);
  }
  return WebUiCredentials(username: username, password: buf.toString());
}

/// Parses `KEY=VALUE` lines, ignoring blanks and `#` comments.
///
/// Values may be wrapped in single or double quotes — an operator editing this
/// by hand will quote a password sooner or later, and silently authenticating
/// against a password that includes the quote marks is a miserable thing to
/// debug. Everything after the first `=` is the value, so a password containing
/// `=` survives.
Map<String, String> parseEnvFile(String contents) {
  final out = <String, String>{};
  for (final raw in const LineSplitter().convert(contents)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    if (key.isNotEmpty) out[key] = value;
  }
  return out;
}

/// Renders the env file written on first launch.
///
/// The comment block is load-bearing documentation: this file is the only place
/// the password exists, and the person who finds it months later needs to know
/// both that deleting it is safe and that it is a credential.
String renderEnvFile(WebUiCredentials credentials, {DateTime? now}) {
  final stamp = (now ?? DateTime.now()).toUtc().toIso8601String();
  return '''
# Airclone Web UI credentials — generated $stamp
#
# These are the username and password for the Airclone Web UI. They were
# generated on first launch and are reused every run.
#
# TREAT THIS FILE AS A PASSWORD. Anyone who can read it can sign in to the Web
# UI and reach every remote this Airclone is configured for.
#
# To rotate the credentials: delete this file. A new pair is generated the next
# time the Web UI starts. (Nothing else in Airclone depends on these values.)
#
# To supply them from outside instead — systemd Environment=, docker -e, a
# secrets mount — set $kWebUiUserEnv and $kWebUiPasswordEnv in the
# environment. Those win over this file, and no file is written.
$kWebUiUserEnv=${credentials.username}
$kWebUiPasswordEnv=${credentials.password}
''';
}

/// Constant-time password comparison.
///
/// Both sides are SHA-256'd first and the fixed-width digests compared with a
/// running OR. Hashing is what makes it safe against a *length* oracle too: a
/// plain byte loop over the raw strings returns faster for a short guess, which
/// tells a remote attacker how long the password is. Digests are always 32
/// bytes, so every comparison does identical work.
bool verifyPassword(String expected, String supplied) {
  final a = sha256.convert(utf8.encode(expected)).bytes;
  final b = sha256.convert(utf8.encode(supplied)).bytes;
  if (a.length != b.length) return false; // unreachable; SHA-256 is fixed-width
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Reads the credentials for this run, generating and persisting them if needed.
///
/// [environment] is passed in rather than read from `Platform.environment` so
/// the precedence rule is testable. [envFilePath] is the absolute path to
/// `webui.env`.
Future<WebUiCredentialResult> loadOrCreateCredentials({
  required String envFilePath,
  required Map<String, String> environment,
  Random? random,
}) async {
  final envUser = environment[kWebUiUserEnv]?.trim();
  final envPass = environment[kWebUiPasswordEnv];
  if (envPass != null && envPass.isNotEmpty) {
    return WebUiCredentialResult(
      WebUiCredentials(
        username: (envUser == null || envUser.isEmpty)
            ? kDefaultWebUiUser
            : envUser,
        password: envPass,
      ),
      WebUiCredentialSource.environment,
    );
  }

  final file = File(envFilePath);
  String? warning;
  if (await file.exists()) {
    try {
      final parsed = parseEnvFile(await file.readAsString());
      final creds = WebUiCredentials(
        username: (parsed[kWebUiUserEnv] ?? '').trim().isEmpty
            ? kDefaultWebUiUser
            : parsed[kWebUiUserEnv]!.trim(),
        password: parsed[kWebUiPasswordEnv] ?? '',
      );
      if (creds.isComplete) {
        return WebUiCredentialResult(creds, WebUiCredentialSource.file);
      }
      warning =
          'The Web UI credentials file had no usable password, so a new '
          'password was generated. The old one no longer works.';
    } on IOException catch (e) {
      warning =
          'The Web UI credentials file could not be read ($e), so a new '
          'password was generated. The old one no longer works.';
    }
  }

  final created = generateCredentials(random: random);
  final writeWarning = await _writeEnvFile(file, created);
  return WebUiCredentialResult(
    created,
    WebUiCredentialSource.generated,
    warning: warning ?? writeWarning,
  );
}

/// Writes [credentials] to [file], restricting it to this user where the OS
/// lets us. Returns a warning string when the write failed.
///
/// A failed write is NOT fatal: the server still starts with the generated
/// password, which the operator can read from the log. It just will not survive
/// a restart — so say so rather than letting them discover it later.
Future<String?> _writeEnvFile(File file, WebUiCredentials credentials) async {
  try {
    await file.parent.create(recursive: true);
    // RESTRICT THE FILE BEFORE THE PASSWORD IS IN IT. Creating it, writing the
    // credentials and chmod'ing afterwards leaves a window at the process
    // umask, and this file is the password to a service that reaches every
    // remote this Airclone is configured for. Same ordering as webui_tls.dart,
    // which had the same bug.
    await file.create();
    if (!Platform.isWindows) {
      try {
        // dart:io has no chmod. Best-effort: on failure the file keeps the
        // process umask, which on a normal system is already not world-readable.
        await Process.run('chmod', ['600', file.path]);
      } on ProcessException {
        // No chmod on PATH. Nothing to do, and not worth alarming anyone over.
      }
    }
    await file.writeAsString(renderEnvFile(credentials), flush: true);
  } on IOException catch (e) {
    return 'The Web UI credentials could not be saved ($e). They will work for '
        'this run, but a new password will be generated next time.';
  }
  return null;
}
