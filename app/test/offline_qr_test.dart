import 'dart:typed_data';

import 'package:airclone/src/state/config_io.dart'
    show Argon2Params, CorruptEnvelope, WrongPassphrase;
import 'package:airclone/src/state/offline_qr.dart';
import 'package:airclone/src/state/pairing_protocol.dart'
    show base45Decode, base45Encode;
import 'package:flutter_test/flutter_test.dart';

/// A deliberately CHEAP Argon2id so the round-trip tests don't pay the 64 MiB
/// production derive. The envelope header records these params, so open() re-
/// derives with them regardless — this is exactly what the `kdf` override is for.
const _cheap = Argon2Params(memory: 16, iterations: 1, parallelism: 1);

const _config = '''
[gdrive]
type = drive
token = {"access_token":"ya29.SECRET","refresh_token":"1//REFRESH"}

[s3backup]
type = s3
provider = AWS
access_key_id = AKIAEXAMPLE
secret_access_key = SUPERsecretVALUE
''';

void main() {
  group('offline QR round-trip', () {
    test(
      'build then open with the right code returns the exact config',
      () async {
        final payload = await buildOfflineQrPayload(
          _config,
          'K7WX-234M',
          kdf: _cheap,
        );
        expect(isOfflineQrPayload(payload), isTrue);
        expect(payload.startsWith(kOfflineQrPrefix), isTrue);
        final out = await openOfflineQrPayload(payload, 'K7WX-234M');
        expect(out, _config);
      },
    );

    test(
      'the code and the plaintext secrets never appear in the payload',
      () async {
        final payload = await buildOfflineQrPayload(
          _config,
          'K7WX-234M',
          kdf: _cheap,
        );
        expect(payload, isNot(contains('K7WX-234M')));
        expect(payload, isNot(contains('SUPERsecretVALUE')));
        expect(payload, isNot(contains('ya29.SECRET')));
      },
    );

    test('the whole payload stays inside the QR-alphanumeric charset', () async {
      final payload = await buildOfflineQrPayload(_config, 'pw', kdf: _cheap);
      // QR alphanumeric mode: 0-9 A-Z space $ % * + - . / :  — anything else would
      // force byte mode and bloat the QR. base45 + the uppercase prefix stay in it.
      expect(RegExp(r'^[0-9A-Z $%*+\-./:]+$').hasMatch(payload), isTrue);
    });
  });

  group('offline QR failure modes', () {
    test(
      'a wrong code fails with WrongPassphrase (not silent garbage)',
      () async {
        final payload = await buildOfflineQrPayload(
          _config,
          'right-code',
          kdf: _cheap,
        );
        expect(
          () => openOfflineQrPayload(payload, 'wrong-code'),
          throwsA(isA<WrongPassphrase>()),
        );
      },
    );

    test(
      'a tampered payload fails authentication (GCM), never opens',
      () async {
        final payload = await buildOfflineQrPayload(_config, 'pw', kdf: _cheap);
        // Flip one base45 char deep in the sealed body (past the prefix).
        final i = payload.length - 5;
        final ch = payload[i];
        final flipped = ch == 'A' ? 'B' : 'A';
        final tampered = payload.replaceRange(i, i + 1, flipped);
        expect(
          () => openOfflineQrPayload(tampered, 'pw'),
          throwsA(anyOf(isA<WrongPassphrase>(), isA<CorruptEnvelope>())),
        );
      },
    );

    test(
      'a QR demanding an OOM-sized Argon2id cost is refused before deriving',
      () async {
        // Build a normal payload, then tamper the envelope header's memory field to
        // an absurd value. openOfflineQrPayload must reject it as CorruptEnvelope
        // via the tight QR memory cap — BEFORE attempting the (huge) derive.
        final payload = await buildOfflineQrPayload(_config, 'pw', kdf: _cheap);
        final sealed = base45Decode(payload.substring(kOfflineQrPrefix.length));
        // Envelope layout: magic(5) | kdfId(1) | memory(4 LE @ offset 6) | …
        final bytes = Uint8List.fromList(sealed);
        ByteData.sublistView(
          bytes,
        ).setUint32(6, 512 * 1024, Endian.little); // 512 MiB
        final tampered = '$kOfflineQrPrefix${base45Encode(bytes)}';
        expect(
          () => openOfflineQrPayload(tampered, 'pw'),
          throwsA(isA<CorruptEnvelope>()),
        );
      },
    );

    test(
      'a QR demanding excessive Argon2id iterations is refused before deriving',
      () async {
        // Argon2 work scales as memory×iterations; capping memory alone leaves the
        // time axis open. A crafted iterations=255 (vs the t=3 we write) must be
        // rejected as CorruptEnvelope BEFORE the (expensive) derive runs.
        final payload = await buildOfflineQrPayload(_config, 'pw', kdf: _cheap);
        final sealed = base45Decode(payload.substring(kOfflineQrPrefix.length));
        final bytes = Uint8List.fromList(sealed);
        bytes[10] = 255; // iterations byte (offset 10)
        final tampered = '$kOfflineQrPrefix${base45Encode(bytes)}';
        expect(
          () => openOfflineQrPayload(tampered, 'pw'),
          throwsA(isA<CorruptEnvelope>()),
        );
      },
    );

    test(
      'a non-offline QR (e.g. the v3 LAN QR) is refused as NotAnOfflineQr',
      () async {
        expect(
          () => openOfflineQrPayload(
            'airclone-cfg:v3|https://192.168.1.5:443|AB|CD',
            'pw',
          ),
          throwsA(isA<NotAnOfflineQr>()),
        );
        expect(isOfflineQrPayload('airclone-cfg:v3|x'), isFalse);
      },
    );

    test(
      'a payload with a valid prefix but junk body is CorruptEnvelope/format',
      () async {
        expect(
          () => openOfflineQrPayload('${kOfflineQrPrefix}000000', 'pw'),
          throwsA(anyOf(isA<CorruptEnvelope>(), isA<FormatException>())),
        );
      },
    );
  });

  group('offline QR capacity', () {
    test(
      'an over-large config throws OfflineQrTooLarge (not a broken QR)',
      () async {
        // A big, POORLY-compressible config (unique high-entropy tokens) so gzip
        // can't squeeze it under the single-QR cap.
        final b = StringBuffer();
        for (var i = 0; i < 400; i++) {
          b.writeln('[remote$i]');
          b.writeln('type = s3');
          // pseudo-random-ish unique token per remote (varying, low redundancy)
          b.writeln(
            'secret_access_key = ${i * 2654435761 % 1000000}Zx${i}Qw${i * 7}',
          );
        }
        expect(
          () => buildOfflineQrPayload(b.toString(), 'pw', kdf: _cheap),
          throwsA(isA<OfflineQrTooLarge>()),
        );
      },
    );

    test(
      'gzip keeps a normal multi-remote config comfortably under the cap',
      () async {
        final payload = await buildOfflineQrPayload(_config, 'pw', kdf: _cheap);
        expect(payload.length, lessThan(kOfflineQrMaxPayloadChars));
      },
    );
  });

  // The REAL crypto path: the default offline-QR band (128 MiB, t=3). Slower, so
  // one test proves the actual derive works end-to-end and a realistic config fits.
  test(
    'production-params round-trip works and fits a scannable QR',
    () async {
      final payload = await buildOfflineQrPayload(_config, 'K7WX-234M');
      expect(payload.length, lessThan(kOfflineQrMaxPayloadChars));
      final out = await openOfflineQrPayload(payload, 'K7WX-234M');
      expect(out, _config);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
