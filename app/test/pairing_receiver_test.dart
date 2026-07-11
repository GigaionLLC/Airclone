import 'dart:convert';
import 'dart:typed_data';

import 'package:airclone/src/state/config_io.dart';
import 'package:airclone/src/state/pairing_protocol.dart';
import 'package:airclone/src/state/pairing_receiver.dart';
import 'package:crypto/crypto.dart' as pc;
import 'package:flutter_test/flutter_test.dart';

/// Coverage for the PHONE RECEIVER orchestration (dev/plans/config-portability-
/// plan.md §5, v3 QR-pinned-TLS) — the pure, network-free parts driven through a
/// FAKE [PairingTransport]: the happy path (challenge → correct proof → sealed
/// blob → decrypted → parsed model handed to `onConfig`), the pin gate
/// ([certFingerprintMatches] + a handshake failure aborting BEFORE any fetch body
/// is used), every non-success server outcome mapping to a typed error, a
/// wrong-code blob failing to open, and the QR front door rejecting bad payloads
/// so a fetch is never even reachable. No camera, no sockets, no TLS.

/// A scriptable [PairingTransport] that records what the receiver sent so the
/// handshake wiring can be asserted directly.
class _FakeTransport implements PairingTransport {
  _FakeTransport({required this.challenge, this.onFetch, this.challengeError});

  /// Returned from [requestChallenge] (unless [challengeError] is set).
  final PairingChallenge challenge;

  /// When non-null, [requestChallenge] throws this instead of returning —
  /// simulating a TLS handshake / pin failure on the first connection.
  final Object? challengeError;

  /// The scripted `/fetch` reply, given exactly what the receiver posted.
  final Future<PairingFetchResult> Function({
    required String sessionId,
    required List<int> challenge,
    required List<int> proof,
  })?
  onFetch;

  int challengeCalls = 0;
  int fetchCalls = 0;
  int closeCalls = 0;
  List<int>? receivedProof;
  String? receivedSessionId;
  List<int>? receivedChallenge;

  /// The ACTUAL proof buffer the receiver handed us, kept by reference (NOT
  /// copied) so a test can observe the receiver zeroizing it in its `finally`.
  List<int>? rawProofRef;

  @override
  Future<PairingChallenge> requestChallenge() async {
    challengeCalls++;
    final err = challengeError;
    if (err != null) throw err;
    return challenge;
  }

  @override
  Future<PairingFetchResult> fetchBlob({
    required String sessionId,
    required List<int> challenge,
    required List<int> proof,
  }) async {
    fetchCalls++;
    receivedSessionId = sessionId;
    // COPY the byte fields: the receiver zeroizes the proof buffer in its
    // `finally`, so capturing the reference would leave us asserting against all
    // zeros. A copy is also what the real transport effectively does (it base64-
    // encodes them onto the wire).
    receivedChallenge = Uint8List.fromList(challenge);
    receivedProof = Uint8List.fromList(proof);
    rawProofRef = proof; // reference, to observe post-run zeroization
    return onFetch!(sessionId: sessionId, challenge: challenge, proof: proof);
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

/// Builds a validated payload the way the sheet does — through the real
/// encode/parse — so the record the receiver consumes is exactly what a scanned
/// v3 QR yields.
ParsedQrPayload _payload({
  String url = 'https://192.168.1.10:8443',
  Uint8List? salt,
  Uint8List? fp,
}) => parseQrPayload(
  encodeQrPayload(
    url: url,
    salt: salt ?? Uint8List.fromList(List<int>.generate(16, (i) => i + 3)),
    certFingerprint: fp ?? Uint8List.fromList(List<int>.generate(32, (i) => i)),
  ),
);

const _code = 'K7WX-4PMB';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const receiver = PairingReceiver();

  // --- Cert pinning (pure) ---------------------------------------------------

  group('certFingerprintMatches', () {
    final der = Uint8List.fromList(
      List<int>.generate(120, (i) => (i * 7 + 5) % 256),
    );

    test('accepts a cert whose SHA-256(DER) equals the pinned fingerprint', () {
      final pinned = sha256OfForTest(der);
      expect(certFingerprintMatches(der, pinned), isTrue);
    });

    test('rejects a one-bit-off fingerprint', () {
      final pinned = sha256OfForTest(der);
      pinned[0] ^= 0x01;
      expect(certFingerprintMatches(der, pinned), isFalse);
    });

    test('rejects a different cert entirely', () {
      final pinned = sha256OfForTest(der);
      final otherDer = Uint8List.fromList(der.reversed.toList());
      expect(certFingerprintMatches(otherDer, pinned), isFalse);
    });

    test('rejects a wrong-length fingerprint', () {
      final short = sha256OfForTest(der).sublist(0, 31);
      expect(certFingerprintMatches(der, short), isFalse);
    });
  });

  // --- Happy path ------------------------------------------------------------

  group('receive (happy path)', () {
    test(
      'challenge -> correct proof -> sealed blob -> parsed model -> onConfig',
      () async {
        final qr = _payload();
        // The desktop derives the SAME key from salt ∥ code and seals the config
        // under it; the receiver must derive an identical key to open it.
        final key = await deriveSessionKey(salt: qr.salt, code: _code);
        const ini =
            '[drive]\n'
            'type = drive\n'
            'token = {"access_token":"secret"}\n\n'
            '[backup]\n'
            'type = s3\n'
            'endpoint = https://s3.example.com\n';
        final sealed = await sealPairingBlob(utf8.encode(ini), key);

        final challengeBytes = Uint8List.fromList(
          List<int>.generate(32, (i) => 200 - i),
        );
        final transport = _FakeTransport(
          challenge: (sessionId: 'sess-abc', challenge: challengeBytes),
          onFetch:
              ({
                required sessionId,
                required challenge,
                required proof,
              }) async => PairingBlobDelivered(sealed),
        );

        ConfigModel? handed;
        await receiver.receive(
          qr: qr,
          code: _code,
          onConfig: (m) => handed = m,
          transportOverride: transport,
        );

        // The config reached the (mandatory-preview) callback, fully parsed.
        expect(handed, isNotNull);
        expect(handed!.keys, containsAll(['drive', 'backup']));
        expect(handed!['drive']!['type'], 'drive');
        expect(handed!['backup']!['type'], 's3');
        expect(handed!['backup']!['endpoint'], 'https://s3.example.com');

        // The handshake was wired correctly: exactly one challenge, one fetch,
        // and the posted proof is HMAC(key, challenge) for THIS challenge.
        expect(transport.challengeCalls, 1);
        expect(transport.fetchCalls, 1);
        expect(transport.receivedSessionId, 'sess-abc');
        expect(transport.receivedProof, equals(proofFor(challengeBytes, key)));
        // The transport is always released.
        expect(transport.closeCalls, 1);
      },
    );

    test(
      'zeroizes the derived proof buffer after the transfer (plan §5)',
      () async {
        final qr = _payload();
        final key = await deriveSessionKey(salt: qr.salt, code: _code);
        final sealed = await sealPairingBlob(
          utf8.encode('[r]\ntype = drive\n'),
          key,
        );
        final transport = _FakeTransport(
          challenge: (sessionId: 's', challenge: newChallenge()),
          onFetch:
              ({
                required sessionId,
                required challenge,
                required proof,
              }) async => PairingBlobDelivered(sealed),
        );
        await receiver.receive(
          qr: qr,
          code: _code,
          onConfig: (_) {},
          transportOverride: transport,
        );
        // The per-session proof (derived from the key) is wiped in the `finally`.
        expect(transport.rawProofRef, isNotNull);
        expect(transport.rawProofRef!.every((b) => b == 0), isTrue);
      },
    );

    test('normalises a lower-case / undashed code to the same key', () async {
      final qr = _payload();
      final key = await deriveSessionKey(salt: qr.salt, code: _code);
      final sealed = await sealPairingBlob(
        utf8.encode('[r]\ntype = drive\n'),
        key,
      );
      final transport = _FakeTransport(
        challenge: (sessionId: 's', challenge: newChallenge()),
        onFetch:
            ({required sessionId, required challenge, required proof}) async =>
                PairingBlobDelivered(sealed),
      );
      ConfigModel? handed;
      await receiver.receive(
        qr: qr,
        code: 'k7wx4pmb', // lower-case, no dash — same canonical code
        onConfig: (m) => handed = m,
        transportOverride: transport,
      );
      expect(handed!['r']!['type'], 'drive');
    });
  });

  // --- Pin mismatch: abort before any fetch body is used ---------------------

  group('pin mismatch', () {
    test(
      'a handshake/pin failure aborts before /fetch is ever called',
      () async {
        final qr = _payload();
        var fetchTouched = false;
        final transport = _FakeTransport(
          challenge: (sessionId: 'unused', challenge: Uint8List(32)),
          // The pinned transport throws at the handshake; model that as the
          // challenge (first connection) failing with a pin error.
          challengeError: const PairingReceiverError(
            PairingFailureKind.pinMismatch,
            'cert did not match pin',
          ),
          onFetch:
              ({required sessionId, required challenge, required proof}) async {
                fetchTouched = true;
                return const PairingNotReady();
              },
        );

        ConfigModel? handed;
        await expectLater(
          () => receiver.receive(
            qr: qr,
            code: _code,
            onConfig: (m) => handed = m,
            transportOverride: transport,
          ),
          throwsA(
            isA<PairingReceiverError>().having(
              (e) => e.kind,
              'kind',
              PairingFailureKind.pinMismatch,
            ),
          ),
        );
        // No fetch body was requested, no config handed off — the pin gate is
        // strictly before the fetch.
        expect(transport.fetchCalls, 0);
        expect(fetchTouched, isFalse);
        expect(handed, isNull);
        // …and the transport was still released.
        expect(transport.closeCalls, 1);
      },
    );
  });

  // --- Non-success server outcomes -> typed errors ---------------------------

  group('server outcomes map to typed errors', () {
    Future<void> expectKind(
      PairingFetchResult reply,
      PairingFailureKind kind,
    ) async {
      final qr = _payload();
      final transport = _FakeTransport(
        challenge: (sessionId: 's', challenge: newChallenge()),
        onFetch:
            ({required sessionId, required challenge, required proof}) async =>
                reply,
      );
      var handed = false;
      await expectLater(
        () => receiver.receive(
          qr: qr,
          code: _code,
          onConfig: (_) => handed = true,
          transportOverride: transport,
        ),
        throwsA(
          isA<PairingReceiverError>().having((e) => e.kind, 'kind', kind),
        ),
      );
      expect(handed, isFalse);
      expect(transport.closeCalls, 1);
    }

    test('proof rejected -> wrongCode', () async {
      await expectKind(
        const PairingProofRejected(),
        PairingFailureKind.wrongCode,
      );
    });

    test('locked out -> lockedOut', () async {
      await expectKind(const PairingLockedOut(), PairingFailureKind.lockedOut);
    });

    test('not ready -> notReady (the only retryable kind)', () async {
      await expectKind(const PairingNotReady(), PairingFailureKind.notReady);
    });
  });

  // --- Wrong code: a blob that doesn't open under our key --------------------

  group('wrong code', () {
    test(
      'a blob sealed under a different code fails to open -> wrongCode',
      () async {
        final qr = _payload();
        // Desktop sealed under a DIFFERENT code than the phone is using.
        final wrongKey = await deriveSessionKey(
          salt: qr.salt,
          code: 'K7WX-4PMC',
        );
        final sealed = await sealPairingBlob(
          utf8.encode('[r]\ntype = drive\n'),
          wrongKey,
        );
        final transport = _FakeTransport(
          challenge: (sessionId: 's', challenge: newChallenge()),
          onFetch:
              ({
                required sessionId,
                required challenge,
                required proof,
              }) async => PairingBlobDelivered(sealed),
        );
        var handed = false;
        await expectLater(
          () => receiver.receive(
            qr: qr,
            code: _code, // K7WX-4PMB — derives a key that can't open the blob
            onConfig: (_) => handed = true,
            transportOverride: transport,
          ),
          throwsA(
            isA<PairingReceiverError>().having(
              (e) => e.kind,
              'kind',
              PairingFailureKind.wrongCode,
            ),
          ),
        );
        expect(handed, isFalse);
      },
    );
  });

  // --- QR front door: bad payloads never reach a fetch -----------------------

  group('parseQrPayload rejections surface as typed errors', () {
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final fp = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('a public host is refused (no ParsedQrPayload, so no fetch)', () {
      final qr =
          'airclone-cfg:v3|https://8.8.8.8:8443/|${base45Encode(salt)}|'
          '${base45Encode(fp)}';
      expect(() => parseQrPayload(qr), throwsA(isA<QrPayloadError>()));
    });

    test('a wrong version (v2) is refused', () {
      final qr =
          'airclone-cfg:v2|https://192.168.1.10:8443/|${base45Encode(salt)}|'
          '${base45Encode(fp)}';
      expect(() => parseQrPayload(qr), throwsA(isA<QrPayloadError>()));
    });

    test('a wrong salt length is refused', () {
      final shortSalt = Uint8List.fromList(List<int>.generate(15, (i) => i));
      final qr =
          'airclone-cfg:v3|https://192.168.1.10:8443/|'
          '${base45Encode(shortSalt)}|${base45Encode(fp)}';
      expect(() => parseQrPayload(qr), throwsA(isA<QrPayloadError>()));
    });

    test('a non-https (non-pinned) scheme is refused', () {
      final qr =
          'airclone-cfg:v3|http://192.168.1.10:8443/|${base45Encode(salt)}|'
          '${base45Encode(fp)}';
      expect(() => parseQrPayload(qr), throwsA(isA<QrPayloadError>()));
    });
  });

  // --- parsePairingConfigBytes ----------------------------------------------

  group('parsePairingConfigBytes', () {
    test('parses INI', () {
      final m = parsePairingConfigBytes(utf8.encode('[drive]\ntype = drive\n'));
      expect(m['drive']!['type'], 'drive');
    });

    test('parses config-dump JSON', () {
      final m = parsePairingConfigBytes(
        utf8.encode('{"drive":{"type":"drive"}}'),
      );
      expect(m['drive']!['type'], 'drive');
    });

    test('tolerates a leading UTF-8 BOM', () {
      final m = parsePairingConfigBytes([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('[r]\ntype = s3\n'),
      ]);
      expect(m['r']!['type'], 's3');
    });
  });
}

/// SHA-256 helper for the pin tests, using the same `crypto` package the
/// production [certFingerprintMatches] computes its digest with.
Uint8List sha256OfForTest(List<int> bytes) =>
    Uint8List.fromList(pc.sha256.convert(bytes).bytes);
