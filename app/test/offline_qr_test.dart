import 'dart:typed_data';

import 'package:airclone/src/state/config_io.dart'
    show Argon2Params, CorruptEnvelope, WrongPassphrase;
import 'package:airclone/src/state/offline_qr.dart';
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

  group('multi-QR (a config too big for one QR, split across several)', () {
    // A config too big for one QR — unique high-entropy tokens defeat gzip.
    String bigConfig(int n) {
      final b = StringBuffer();
      for (var i = 0; i < n; i++) {
        b.writeln('[remote$i]');
        b.writeln('type = s3');
        b.writeln(
          'secret_access_key = ${i * 2654435761 % 1000000}Zx${i}Qw${i * 7}',
        );
      }
      return b.toString();
    }

    test('a small config still yields ONE classic single-QR payload', () async {
      final payloads = await buildOfflineQrPayloads(_config, 'pw', kdf: _cheap);
      expect(payloads.length, 1);
      expect(isOfflineQrPayload(payloads.single), isTrue);
      expect(isOfflineQrChunk(payloads.single), isFalse);
    });

    test(
      'a large config splits into >1 chunk and round-trips (any order)',
      () async {
        final cfg = bigConfig(160);
        final payloads = await buildOfflineQrPayloads(
          cfg,
          'K7WX-234M',
          kdf: _cheap,
          id: 'AB12',
        );
        expect(payloads.length, greaterThan(1));
        final total = payloads.length;
        final indices = <int>{};
        for (final p in payloads) {
          expect(isOfflineQrChunk(p), isTrue);
          // Each chunk QR stays scannable + in the QR-alphanumeric charset.
          expect(p.length, lessThanOrEqualTo(kOfflineQrMaxPayloadChars));
          expect(RegExp(r'^[0-9A-Z $%*+\-./:]+$').hasMatch(p), isTrue);
          final ch = parseOfflineQrChunk(p)!;
          expect(ch.id, 'AB12');
          expect(ch.total, total);
          indices.add(ch.index);
        }
        expect(indices, {for (var i = 0; i < total; i++) i});

        // Accumulate in REVERSE scan order — assembly is index-based, not order.
        final collected = <int, String>{};
        for (final p in payloads.reversed) {
          final ch = parseOfflineQrChunk(p)!;
          collected[ch.index] = ch.body;
        }
        final assembled = assembleOfflineQrPayload(collected, total)!;
        expect(await openOfflineQrPayload(assembled, 'K7WX-234M'), cfg);
      },
    );

    test('assemble returns null until every chunk is collected', () async {
      final payloads = await buildOfflineQrPayloads(
        bigConfig(160),
        'pw',
        kdf: _cheap,
      );
      final total = payloads.length;
      final partial = <int, String>{};
      for (final p in payloads.take(total - 1)) {
        final ch = parseOfflineQrChunk(p)!;
        partial[ch.index] = ch.body;
      }
      expect(assembleOfflineQrPayload(partial, total), isNull);
    });

    test('parseOfflineQrChunk rejects malformed / out-of-range chunks', () {
      // <prefix><id:4><index:2><total:2><body>
      expect(
        parseOfflineQrChunk('${kOfflineQrPrefix}xyz'),
        isNull,
      ); // wrong scheme
      expect(
        parseOfflineQrChunk('${kOfflineQrMultiPrefix}AB'),
        isNull,
      ); // short
      expect(
        parseOfflineQrChunk('${kOfflineQrMultiPrefix}AB120203'),
        isNull,
      ); // no body
      expect(
        parseOfflineQrChunk('${kOfflineQrMultiPrefix}AB120500body'),
        isNull,
      ); // total 00
      expect(
        parseOfflineQrChunk('${kOfflineQrMultiPrefix}AB120303body'),
        isNull,
      ); // idx>=total
      final ok = parseOfflineQrChunk('${kOfflineQrMultiPrefix}AB120203body');
      expect(ok, isNotNull);
      expect(ok!.index, 2);
      expect(ok.total, 3);
      expect(ok.body, 'body');
    });
  });

  // The REAL crypto path: the default offline-QR band (128 MiB, t=3). Slower, so
  // one test proves the actual derive works end-to-end and a realistic config fits.
  test('production-params round-trip works and fits a scannable QR', () async {
    final payload = await buildOfflineQrPayload(_config, 'K7WX-234M');
    expect(payload.length, lessThan(kOfflineQrMaxPayloadChars));
    final out = await openOfflineQrPayload(payload, 'K7WX-234M');
    expect(out, _config);
  }, timeout: const Timeout(Duration(minutes: 2)));

  // base45 + the unlock-code generator moved into offline_qr.dart when the LAN
  // pairing_protocol.dart was deleted; these keep their direct coverage.
  group('base45 codec (RFC 9285)', () {
    test('round-trips arbitrary bytes', () {
      for (final bytes in <List<int>>[
        [],
        [0],
        [255],
        [0, 0],
        [255, 255],
        [1, 2, 3, 4, 5],
        List<int>.generate(64, (i) => (i * 37) & 0xFF),
      ]) {
        final enc = base45Encode(bytes);
        expect(
          base45Decode(enc),
          Uint8List.fromList(bytes),
          reason: 'len ${bytes.length}',
        );
      }
    });

    test('stays within the QR-alphanumeric charset', () {
      const alnum = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
      final enc = base45Encode(List<int>.generate(50, (i) => (i * 5) & 0xFF));
      for (final ch in enc.split('')) {
        expect(alnum.contains(ch), isTrue, reason: 'char "$ch"');
      }
    });

    test('rejects an out-of-alphabet symbol', () {
      expect(() => base45Decode('AB!'), throwsFormatException);
    });

    test('rejects a length that cannot frame bytes (len % 3 == 1)', () {
      expect(() => base45Decode('0000'), throwsFormatException);
    });

    test('rejects an overlong (non-canonical) group', () {
      expect(() => base45Decode(':::'), throwsFormatException);
    });
  });

  group('unlock code generator', () {
    final shape = RegExp(r'^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$');
    test('newPairingCode mints 8 Crockford symbols as XXXX-XXXX', () {
      for (var i = 0; i < 50; i++) {
        final code = newPairingCode();
        expect(shape.hasMatch(code), isTrue, reason: code);
      }
    });

    test('formatPairingCode groups into dash-separated blocks of four', () {
      expect(formatPairingCode('K7WX4PMB'), 'K7WX-4PMB');
      expect(formatPairingCode('K7WX-4PMB'), 'K7WX-4PMB'); // idempotent
      expect(formatPairingCode('ABC'), 'ABC');
      expect(formatPairingCode('ABCDE'), 'ABCD-E');
    });
  });
}
