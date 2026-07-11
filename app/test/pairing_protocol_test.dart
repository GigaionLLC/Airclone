import 'dart:convert';
import 'dart:typed_data';

import 'package:airclone/src/state/pairing_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exhaustive, pure-function coverage for the QR/LAN pairing protocol core
/// (dev/plans/config-portability-plan.md §5, v3 QR-pinned-TLS): Crockford base32
/// (round-trip, ambiguous-char folding, invalid-char reject), base45 (RFC 9285
/// round-trip, known vectors, odd-length + bad-char reject), HKDF session-key
/// derivation (determinism + wrong-code fails to open), AES-GCM blob sealing
/// (distinct ciphertext per seal + tamper/truncation fails), the challenge/proof
/// handshake (deterministic proof + constant-time verify), and QR framing
/// (accepts a private-host payload; rejects public host, wrong version, wrong
/// salt/fp length). Everything here is a leaf function — no sockets, no TLS, no
/// engine — so the security-critical crypto/encoding is asserted directly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --- Session material ------------------------------------------------------

  group('session material', () {
    test('newSessionSalt is 16 random bytes and varies per call', () {
      final a = newSessionSalt();
      final b = newSessionSalt();
      expect(a.length, 16);
      expect(b.length, 16);
      expect(a, isNot(equals(b))); // 128-bit random — collision is negligible
    });

    test('newSessionId is distinct from the salt and varies per call', () {
      final id = newSessionId();
      // A correlation token, safe to echo — not the salt, not derived from it.
      expect(id, isNotEmpty);
      expect(newSessionId(), isNot(equals(id)));
      // It is a short hex string, never the raw salt bytes.
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(id), isTrue);
    });

    test('newChallenge is 32 random bytes and varies per call', () {
      final a = newChallenge();
      final b = newChallenge();
      expect(a.length, 32);
      expect(a, isNot(equals(b)));
    });
  });

  // --- Crockford base32 pairing code -----------------------------------------

  group('pairing code (Crockford base32)', () {
    test('newPairingCode is 8 symbols shown grouped as XXXX-XXXX', () {
      final code = newPairingCode();
      expect(
        code,
        matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$')),
      );
      // …and normalises back to exactly 8 canonical symbols.
      expect(normalizePairingCode(code).length, 8);
    });

    test('newPairingCode never emits an excluded letter (I, L, O, U)', () {
      // Sample many codes; none may contain an ambiguous/excluded symbol.
      for (var i = 0; i < 200; i++) {
        final canonical = newPairingCode().replaceAll('-', '');
        expect(canonical.contains(RegExp('[ILOU]')), isFalse);
      }
    });

    test('formatPairingCode groups an 8-char code and is stable', () {
      expect(formatPairingCode('K7WX4PMB'), 'K7WX-4PMB');
      // Re-formatting an already-grouped code is idempotent.
      expect(formatPairingCode('K7WX-4PMB'), 'K7WX-4PMB');
    });

    test('normalize strips dashes/spaces and upper-cases', () {
      expect(normalizePairingCode('k7wx-4pmb'), 'K7WX4PMB');
      expect(normalizePairingCode('  k7 wx 4p mb '), 'K7WX4PMB');
    });

    test('Crockford decode folds O->0 and I/L->1 (never the reverse)', () {
      // Letters map TO digits; a real digit is left untouched.
      expect(normalizePairingCode('OIL'), '011');
      expect(normalizePairingCode('oil'), '011');
      expect(normalizePairingCode('0'), '0'); // 0 stays 0, does NOT become O
      expect(normalizePairingCode('l1I'), '111');
    });

    test('round-trips: fold(new code) is valid and stable under re-fold', () {
      final code = newPairingCode();
      final once = normalizePairingCode(code);
      expect(normalizePairingCode(once), once); // canonical form is a fixpoint
    });

    test('rejects invalid characters (U is excluded, punctuation)', () {
      // U is deliberately not in Crockford's alphabet and has no decode alias.
      expect(() => normalizePairingCode('ABCU'), throwsFormatException);
      expect(() => normalizePairingCode('AB!C'), throwsFormatException);
      expect(() => normalizePairingCode('K7WX4PM_'), throwsFormatException);
    });

    test('rejects an empty (or all-separator) code', () {
      expect(() => normalizePairingCode(''), throwsFormatException);
      expect(() => normalizePairingCode('----'), throwsFormatException);
    });
  });

  // --- base45 (RFC 9285) -----------------------------------------------------

  group('base45', () {
    test('known RFC 9285 vectors encode exactly', () {
      expect(base45Encode(utf8.encode('AB')), 'BB8');
      expect(base45Encode(utf8.encode('Hello!!')), '%69 VD92EX0');
      expect(base45Encode(utf8.encode('base-45')), 'UJCLQE7W581');
      expect(base45Encode(utf8.encode('ietf!')), 'QED8WEX0');
    });

    test('known vectors decode back to the original bytes', () {
      expect(base45Decode('BB8'), utf8.encode('AB'));
      expect(base45Decode('%69 VD92EX0'), utf8.encode('Hello!!'));
      expect(base45Decode('UJCLQE7W581'), utf8.encode('base-45'));
      expect(base45Decode('QED8WEX0'), utf8.encode('ietf!'));
    });

    test('round-trips arbitrary byte content, including boundary bytes', () {
      final cases = <List<int>>[
        const [],
        const [0],
        const [255],
        const [0, 0],
        const [255, 255],
        const [0, 255, 128, 1, 2, 3, 4],
        List<int>.generate(37, (i) => (i * 37 + 11) % 256), // odd length
        List<int>.generate(64, (i) => (255 - i) % 256), // even length
      ];
      for (final bytes in cases) {
        expect(
          base45Decode(base45Encode(bytes)),
          bytes,
          reason: 'round-trip failed for $bytes',
        );
      }
    });

    test('rejects a length that is 1 (mod 3) — a lone trailing symbol', () {
      // A valid encoding is length 0, 2, or 3 (mod 3 in {0,2}); 1 is impossible.
      expect(() => base45Decode('B'), throwsFormatException); // len 1
      expect(() => base45Decode('BB8B'), throwsFormatException); // len 4
    });

    test('rejects a character outside the RFC 9285 alphabet', () {
      // Lower-case and most punctuation are not base45 symbols.
      expect(() => base45Decode('ab8'), throwsFormatException);
      expect(() => base45Decode('B~8'), throwsFormatException);
    });

    test('rejects an overlong (non-canonical) group/tail', () {
      // 'GGW' decodes to a 3-symbol value > 0xFFFF; 'U6' to a tail > 0xFF.
      expect(() => base45Decode('GGW'), throwsFormatException);
      expect(() => base45Decode('U6'), throwsFormatException);
    });
  });

  // --- Session key derivation ------------------------------------------------

  group('deriveSessionKey (HKDF)', () {
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));

    test('is deterministic: same salt + code -> same 32-byte key', () async {
      final k1 = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
      final k2 = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
      expect(k1.length, 32);
      expect(k1, equals(k2));
    });

    test('normalises the code first: dashed/lower == canonical', () async {
      final canonical = await deriveSessionKey(salt: salt, code: 'K7WX4PMB');
      final dashed = await deriveSessionKey(salt: salt, code: 'k7wx-4pmb');
      expect(dashed, equals(canonical));
    });

    test('a different code yields a different key', () async {
      final k1 = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
      final k2 = await deriveSessionKey(salt: salt, code: 'K7WX-4PMC');
      expect(k1, isNot(equals(k2)));
    });

    test('a different salt yields a different key', () async {
      final other = Uint8List.fromList(List<int>.generate(16, (i) => 255 - i));
      final k1 = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
      final k2 = await deriveSessionKey(salt: other, code: 'K7WX-4PMB');
      expect(k1, isNot(equals(k2)));
    });

    test('an invalid code throws before any derivation', () async {
      await expectLater(
        () => deriveSessionKey(salt: salt, code: 'BAD!'),
        throwsFormatException,
      );
    });
  });

  // --- Blob sealing ----------------------------------------------------------

  group('sealPairingBlob / openPairingBlob', () {
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i * 2));
    final plaintext = utf8.encode('[drive]\ntype = drive\ntoken = secret==\n');

    test('seal -> open round-trips the plaintext under the same key', () async {
      final key = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
      final sealed = await sealPairingBlob(plaintext, key);
      expect(await openPairingBlob(sealed, key), equals(plaintext));
    });

    test('two seals of the same input differ (fresh random nonce)', () async {
      final key = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
      final a = await sealPairingBlob(plaintext, key);
      final b = await sealPairingBlob(plaintext, key);
      expect(a, isNot(equals(b)));
      // …yet both open to the same plaintext.
      expect(await openPairingBlob(a, key), equals(plaintext));
      expect(await openPairingBlob(b, key), equals(plaintext));
    });

    test('a wrong code (wrong key) fails to open -> WrongPairingKey', () async {
      final right = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
      final wrong = await deriveSessionKey(salt: salt, code: 'K7WX-4PMC');
      final sealed = await sealPairingBlob(plaintext, right);
      expect(
        () => openPairingBlob(sealed, wrong),
        throwsA(isA<WrongPairingKey>()),
      );
    });

    test('a flipped byte fails authentication -> WrongPairingKey', () async {
      final key = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
      final sealed = await sealPairingBlob(plaintext, key);
      final tampered = Uint8List.fromList(sealed);
      tampered[tampered.length - 1] ^= 0xFF; // corrupt the tag/ciphertext
      expect(
        () => openPairingBlob(tampered, key),
        throwsA(isA<WrongPairingKey>()),
      );
    });

    test(
      'a too-short blob is CorruptPairingBlob, not WrongPairingKey',
      () async {
        final key = await deriveSessionKey(salt: salt, code: 'K7WX-4PMB');
        // Shorter than nonce(12) + mac(16) — can't even be framed as a box.
        expect(
          () => openPairingBlob(Uint8List(10), key),
          throwsA(isA<CorruptPairingBlob>()),
        );
      },
    );
  });

  // --- Challenge / proof -----------------------------------------------------

  group('challenge / proof', () {
    test('proofFor is a deterministic 32-byte HMAC-SHA256', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final challenge = Uint8List.fromList(
        List<int>.generate(32, (i) => 31 - i),
      );
      final p1 = proofFor(challenge, key);
      final p2 = proofFor(challenge, key);
      expect(p1.length, 32);
      expect(p1, equals(p2));
    });

    test('verifyProof accepts a proof made with the matching key', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final challenge = newChallenge();
      final proof = proofFor(challenge, key);
      expect(verifyProof(key, challenge, proof), isTrue);
    });

    test('verifyProof rejects a wrong key, wrong challenge, wrong proof', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final wrongKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 2));
      final challenge = newChallenge();
      final proof = proofFor(challenge, key);
      // Wrong key on the verifier side.
      expect(verifyProof(wrongKey, challenge, proof), isFalse);
      // A proof for a different challenge.
      expect(verifyProof(key, newChallenge(), proof), isFalse);
      // A flipped proof byte.
      final bad = Uint8List.fromList(proof);
      bad[0] ^= 0xFF;
      expect(verifyProof(key, challenge, bad), isFalse);
    });

    test('constantTimeBytesEqual matches value equality (equal/unequal)', () {
      final a = Uint8List.fromList(const [1, 2, 3, 4]);
      final b = Uint8List.fromList(const [1, 2, 3, 4]);
      final c = Uint8List.fromList(const [1, 2, 3, 5]); // last byte differs
      expect(constantTimeBytesEqual(a, b), isTrue);
      expect(constantTimeBytesEqual(a, c), isFalse);
      // A difference in the FIRST byte must also be caught (no early accept).
      final d = Uint8List.fromList(const [9, 2, 3, 4]);
      expect(constantTimeBytesEqual(a, d), isFalse);
    });

    test('constantTimeBytesEqual returns false for unequal lengths', () {
      expect(
        constantTimeBytesEqual(const [1, 2, 3], const [1, 2, 3, 4]),
        isFalse,
      );
      expect(constantTimeBytesEqual(const [], const [0]), isFalse);
      expect(constantTimeBytesEqual(const [], const []), isTrue);
    });
  });

  // --- QR payload ------------------------------------------------------------

  group('QR payload', () {
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final fp = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

    test('encode -> parse round-trips a valid private-host payload', () {
      final qr = encodeQrPayload(
        url: 'https://192.168.1.42:8443/x',
        salt: salt,
        certFingerprint: fp,
      );
      expect(qr.startsWith('airclone-cfg:v3|'), isTrue);
      final parsed = parseQrPayload(qr);
      expect(parsed.url, 'https://192.168.1.42:8443/x');
      expect(parsed.salt, equals(salt));
      expect(parsed.certFingerprint, equals(fp));
    });

    test('accepts every private / link-local / loopback IPv4 range', () {
      for (final host in const [
        '10.0.0.1',
        '10.255.255.254',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.1',
        '169.254.10.20', // link-local
        '127.0.0.1', // loopback
      ]) {
        final qr = encodeQrPayload(
          url: 'https://$host:8443/',
          salt: salt,
          certFingerprint: fp,
        );
        expect(
          parseQrPayload(qr).url,
          'https://$host:8443/',
          reason: '$host should be accepted',
        );
      }
    });

    test('rejects a public host', () {
      final qr = encodeQrPayload(
        url: 'https://8.8.8.8:8443/',
        salt: salt,
        certFingerprint: fp,
      );
      expect(() => parseQrPayload(qr), throwsA(isA<QrPayloadError>()));
    });

    test('rejects near-miss non-private ranges (boundary correctness)', () {
      for (final host in const [
        '172.15.0.1', // just below 172.16
        '172.32.0.1', // just above 172.31
        '192.169.0.1', // not 192.168
        '11.0.0.1', // not 10.x
        '169.253.0.1', // not link-local
      ]) {
        final qr = encodeQrPayload(
          url: 'https://$host:8443/',
          salt: salt,
          certFingerprint: fp,
        );
        expect(
          () => parseQrPayload(qr),
          throwsA(isA<QrPayloadError>()),
          reason: '$host should be rejected',
        );
      }
    });

    test('rejects a leading-zero (octal-ambiguous) octet in the host', () {
      // A leading-zero octet is non-canonical: some platform resolvers read it as
      // OCTAL, so accepting '010.x' as decimal 10.x here would be a validator/
      // resolver differential that could steer the phone off the private range.
      for (final host in const [
        '010.0.0.1', // '010' — octal 8 to some resolvers, decimal 10 here
        '192.168.01.1',
        '172.016.0.1',
        '127.00.0.1',
      ]) {
        final qr = encodeQrPayload(
          url: 'https://$host:8443/',
          salt: salt,
          certFingerprint: fp,
        );
        expect(
          () => parseQrPayload(qr),
          throwsA(isA<QrPayloadError>()),
          reason: '$host should be rejected (non-canonical octet)',
        );
      }
    });

    test('rejects a bare hostname (unprovable as private) and IPv6', () {
      final host = encodeQrPayload(
        url: 'https://my-phone.local:8443/',
        salt: salt,
        certFingerprint: fp,
      );
      expect(() => parseQrPayload(host), throwsA(isA<QrPayloadError>()));
      final v6 = encodeQrPayload(
        url: 'https://[::1]:8443/',
        salt: salt,
        certFingerprint: fp,
      );
      expect(() => parseQrPayload(v6), throwsA(isA<QrPayloadError>()));
    });

    test('rejects a non-https scheme (v3 is TLS-pinned)', () {
      final qr = encodeQrPayload(
        url: 'http://192.168.1.42:8443/',
        salt: salt,
        certFingerprint: fp,
      );
      expect(() => parseQrPayload(qr), throwsA(isA<QrPayloadError>()));
    });

    test('rejects the wrong scheme/version prefix', () {
      // A v2 (keyed) QR, or any other prefix, must be refused — not coerced.
      final v2 =
          'airclone-cfg:v2|https://192.168.1.42:8443/|${base45Encode(salt)}|'
          '${base45Encode(fp)}';
      expect(() => parseQrPayload(v2), throwsA(isA<QrPayloadError>()));
      expect(() => parseQrPayload('garbage'), throwsA(isA<QrPayloadError>()));
    });

    test('rejects a wrong salt length', () {
      final shortSalt = Uint8List.fromList(List<int>.generate(15, (i) => i));
      final qr =
          'airclone-cfg:v3|https://192.168.1.42:8443/|${base45Encode(shortSalt)}|'
          '${base45Encode(fp)}';
      expect(() => parseQrPayload(qr), throwsA(isA<QrPayloadError>()));
    });

    test('rejects a wrong fingerprint length', () {
      final shortFp = Uint8List.fromList(List<int>.generate(31, (i) => i));
      final qr =
          'airclone-cfg:v3|https://192.168.1.42:8443/|${base45Encode(salt)}|'
          '${base45Encode(shortFp)}';
      expect(() => parseQrPayload(qr), throwsA(isA<QrPayloadError>()));
    });

    test('encodeQrPayload refuses to emit out-of-spec field lengths', () {
      expect(
        () => encodeQrPayload(
          url: 'https://192.168.1.42:8443/',
          salt: Uint8List(15),
          certFingerprint: fp,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => encodeQrPayload(
          url: 'https://192.168.1.42:8443/',
          salt: salt,
          certFingerprint: Uint8List(31),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // --- Hygiene ---------------------------------------------------------------

  group('zeroize', () {
    test('wipes a mutable byte buffer in place', () {
      final secret = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      zeroize(secret);
      expect(secret.every((b) => b == 0), isTrue);
    });

    test('is a no-op (no throw) on an unmodifiable list', () {
      // Must not throw when the list can't be written — best-effort hygiene.
      expect(() => zeroize(const [1, 2, 3]), returnsNormally);
    });
  });
}
