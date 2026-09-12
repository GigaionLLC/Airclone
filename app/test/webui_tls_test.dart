import 'dart:io';

import 'package:airclone/src/webui/webui_tls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('acl_tls'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('first run generates a usable certificate and key', () async {
    final m = await ensureTlsMaterial(dir.path);
    expect(File(m.certPath).existsSync(), isTrue);
    expect(File(m.keyPath).existsSync(), isTrue);
    expect(File(m.certPath).readAsStringSync(), contains('BEGIN CERTIFICATE'));
    expect(m.imported, isFalse);
    // The real test: dart:io must accept it, which is what actually serves.
    expect(() => m.toSecurityContext(), returnsNormally);
  });

  test('the certificate is REUSED, not minted again', () async {
    // A fresh certificate each start invalidates the exception the browser
    // stored, so every restart would look like a new attack.
    final first = await ensureTlsMaterial(dir.path);
    final firstPem = File(first.certPath).readAsStringSync();
    final second = await ensureTlsMaterial(dir.path);
    expect(File(second.certPath).readAsStringSync(), firstPem);
    expect(second.fingerprint, first.fingerprint);
  });

  test(
    'an imported pair wins, and does not destroy the generated one',
    () async {
      final generated = await ensureTlsMaterial(dir.path);
      final imp = Directory('${dir.path}/$kImportedDirName')..createSync();
      final other = generateSelfSigned();
      File('${imp.path}/$kCertFileName').writeAsStringSync(other.$1);
      File('${imp.path}/$kKeyFileName').writeAsStringSync(other.$2);

      final loaded = await ensureTlsMaterial(dir.path);
      expect(loaded.imported, isTrue);
      expect(loaded.fingerprint, isNot(generated.fingerprint));
      // The generated pair survives, so removing the import falls back.
      expect(File(generated.certPath).existsSync(), isTrue);
    },
  );

  test('a half-finished import is ignored rather than half-used', () async {
    await ensureTlsMaterial(dir.path);
    final imp = Directory('${dir.path}/$kImportedDirName')..createSync();
    File(
      '${imp.path}/$kCertFileName',
    ).writeAsStringSync(generateSelfSigned().$1);
    // Key missing: an automation mid-write must not take the server down.
    final loaded = await ensureTlsMaterial(dir.path);
    expect(loaded.imported, isFalse);
  });

  group('fingerprint', () {
    test('is over the DER, and shaped like a browser shows it', () {
      final pem = generateSelfSigned().$1;
      final fp = certificateFingerprint(pem);
      expect(fp, matches(RegExp(r'^([0-9a-f]{2}:){31}[0-9a-f]{2}$')));
    });

    test('ignores PEM whitespace, because that is not the certificate', () {
      final pem = generateSelfSigned().$1;
      expect(
        certificateFingerprint('$pem\n\n'),
        certificateFingerprint(pem.trimRight()),
      );
    });

    test('two certificates do not share one', () {
      expect(
        certificateFingerprint(generateSelfSigned().$1),
        isNot(certificateFingerprint(generateSelfSigned().$1)),
      );
    });
  });
}
