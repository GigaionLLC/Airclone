/// TLS material for the Web UI server.
///
/// **Why the Web UI is HTTPS only.** Browsers no longer treat plain HTTP as a
/// neutral choice: Chrome's HTTPS-First upgrades or interstitials it, and the
/// features a modern page expects are increasingly gated on a secure context.
/// An HTTP-only LAN service is already a degraded experience, so there is no
/// plain listener at all — not a redirect, not an opt-in.
///
/// **Why self-signed is acceptable here, and why the warning is not hidden.**
/// Nobody can issue a publicly-trusted certificate for a machine on someone's
/// home network, so the first visit shows a browser warning. That warning is
/// EXPECTED and the UI says so, alongside the certificate's fingerprint, so the
/// operator can check that the thing they are trusting is the thing they
/// started. Dressing it up would teach people to click through security
/// warnings, which is a worse outcome than the warning itself.
///
/// **Why the certificate is stored rather than minted per start.** A fresh
/// certificate every launch invalidates the exception the browser just stored,
/// so every restart would look like a new attack. Generated once, reused, and
/// replaceable — see [kImportedDirName].
library;

import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// Files an operator can drop in to replace the generated pair, for anyone
/// automating certificate renewal from outside Airclone.
const String kImportedDirName = 'imported';

const String kCertFileName = 'cert.pem';
const String kKeyFileName = 'key.pem';

/// A certificate and its private key, on disk, with the fingerprint to show the
/// operator.
class WebUiTlsMaterial {
  const WebUiTlsMaterial({
    required this.certPath,
    required this.keyPath,
    required this.fingerprint,
    required this.imported,
  });

  final String certPath;
  final String keyPath;

  /// Lower-case, colon-separated SHA-256 of the certificate's DER bytes — the
  /// same value a browser shows, so the two can be compared by eye.
  final String fingerprint;

  /// True when this came from [kImportedDirName] rather than being generated.
  final bool imported;

  SecurityContext toSecurityContext() => SecurityContext()
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);
}

/// SHA-256 over the DER inside a PEM certificate, formatted as a browser shows
/// it.
///
/// Over the DER, not over the PEM text: the PEM's line wrapping and trailing
/// newline are not part of the certificate, and hashing them would produce a
/// value that matches nothing a browser will ever display.
String certificateFingerprint(String certPem) {
  // LineSplitter, not a split on a newline literal: a PEM written on Windows
  // carries a trailing CR that base64 rejects, and that surfaces as a
  // FormatException a long way from its cause.
  final body = StringBuffer();
  for (final line in const LineSplitter().convert(certPem)) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('-----')) continue;
    body.write(t);
  }
  final der = base64.decode(body.toString());
  final digest = sha256.convert(der).bytes;
  return [
    for (final b in digest) b.toRadixString(16).padLeft(2, '0'),
  ].join(':');
}

/// Loads the certificate to serve with, generating one on first run.
///
/// An imported pair wins over the generated one, and neither is ever
/// overwritten by the other: if an import is removed, the generated pair is
/// still there to fall back to.
Future<WebUiTlsMaterial> ensureTlsMaterial(String dir) async {
  final imported = Directory('$dir/$kImportedDirName');
  final importedCert = File('${imported.path}/$kCertFileName');
  final importedKey = File('${imported.path}/$kKeyFileName');
  if (await importedCert.exists() && await importedKey.exists()) {
    return WebUiTlsMaterial(
      certPath: importedCert.path,
      keyPath: importedKey.path,
      fingerprint: certificateFingerprint(await importedCert.readAsString()),
      imported: true,
    );
  }

  final cert = File('$dir/$kCertFileName');
  final key = File('$dir/$kKeyFileName');
  if (!await cert.exists() || !await key.exists()) {
    await Directory(dir).create(recursive: true);
    final generated = generateSelfSigned();
    await cert.writeAsString(generated.$1);
    // TIGHTEN THE KEY'S PERMISSIONS BEFORE ITS CONTENT EXISTS, not after.
    // Creating it, writing the key, and then chmod'ing leaves a window - short,
    // but real on a multi-user machine - where the private key sits on disk at
    // whatever the umask allowed. So: create it empty, restrict it, then write.
    await key.create();
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', key.path]);
      } catch (_) {
        // Not fatal: the file is already under the app's own data directory.
        // Windows has no chmod and inherits that directory's ACL instead.
      }
    }
    await key.writeAsString(generated.$2);
  }
  return WebUiTlsMaterial(
    certPath: cert.path,
    keyPath: key.path,
    fingerprint: certificateFingerprint(await cert.readAsString()),
    imported: false,
  );
}

/// Generates a self-signed certificate and its key, as (certPem, keyPem).
///
/// The SANs cover the names a browser will actually be pointed at on a LAN box.
/// A certificate without a matching SAN is rejected outright by every modern
/// browser — CN alone has not been accepted for years — so this is not
/// decoration.
(String, String) generateSelfSigned({List<String>? extraSans}) {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final priv = pair.privateKey as RSAPrivateKey;
  final pub = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem({'CN': 'Airclone Web UI'}, priv, pub);
  final sans = <String>{'localhost', '127.0.0.1', '::1', ...?extraSans};
  final certPem = X509Utils.generateSelfSignedCertificate(
    pair.privateKey,
    csr,
    // Two years. Long enough not to be a chore, short enough that a key which
    // leaked stops being useful within a plausible lifetime of the install.
    730,
    sans: sans.toList(),
  );
  return (certPem, CryptoUtils.encodeRSAPrivateKeyToPem(priv));
}
