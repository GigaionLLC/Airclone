import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:airclone/src/state/config_io.dart';
import 'package:airclone/src/state/pairing_protocol.dart';
import 'package:airclone/src/state/pairing_receiver.dart';
import 'package:airclone/src/state/pairing_sender.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

/// State-machine + guard coverage for the DESKTOP SENDER of the QR/LAN "Send to
/// phone" handoff (dev/plans/config-portability-plan.md §5, v3 QR-pinned-TLS).
///
/// The pure crypto/encoding is already exhaustively covered in
/// pairing_protocol_test.dart; here we drive the REAL [PairingSender] server
/// in-process over localhost TLS — pinning its generated cert fingerprint with an
/// [HttpClient.badCertificateCallback] exactly as the phone does — and assert the
/// SERVER behaviour the security model rests on:
///  - a correct proof returns a blob that [openPairingBlob] decrypts to the config;
///  - /fetch before the code is armed is a no-strike "not ready" (425) that leaves
///    the challenge usable, so it delivers once the code is typed;
///  - a wrong code is a 403 that burns exactly one GLOBAL strike;
///  - three failed proofs lock the session (429) and tear it down;
///  - the session is one-shot — it stops serving after a delivery;
///  - a mismatched session id is refused without a strike;
///  - the QR pins THIS session (url + salt + cert fingerprint);
///  - the source-address guard accepts loopback/private and rejects public.
/// Plus one true end-to-end test through the real [PairingReceiver] transport, so
/// the two halves of the wire contract are proven to fit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding installs an HttpOverrides that fails every HttpClient
  // request with 400 (to catch accidental network in widget tests). This suite
  // deliberately drives a REAL in-process TLS server over loopback, so null out
  // that override and let HttpClient make genuine localhost connections.
  setUp(() => HttpOverrides.global = null);

  // One real ephemeral RSA cert, minted once and reused across the servers below
  // (each test still pins it): exercises the genuine TLS path without paying
  // keygen per test.
  late EphemeralCert cert;
  setUpAll(() {
    cert = generateEphemeralCertSync();
  });

  // The plaintext config the sender seals + serves. A fresh COPY is handed to each
  // session because teardown zeroizes the sender's copy — this reference stays
  // intact for the post-decrypt comparison.
  final configBytes = utf8.encode('[drive]\ntype = drive\ntoken = secret==\n');
  const loopback = LanHost(address: '127.0.0.1', interfaceName: 'lo');
  const rightCode = 'K7WX-4PMB';
  const wrongCode = 'K7WX-4PMC';

  Future<PairingSender> startSender() => PairingSender.start(
    configBlob: List<int>.from(configBytes),
    host: loopback,
    generateCert: () async => cert,
    maxConnections: 4,
    maxFailedAttempts: 3,
  );

  // An HttpClient that trusts ONLY the cert whose DER hashes to [fp] — the phone's
  // pin-before-body trust decision, replicated for the tests.
  HttpClient pinnedClient(Uint8List fp) {
    final client = HttpClient();
    client.badCertificateCallback = (X509Certificate c, String host, int port) {
      final got = crypto.sha256.convert(c.der).bytes;
      if (got.length != fp.length) return false;
      var diff = 0;
      for (var i = 0; i < fp.length; i++) {
        diff |= got[i] ^ fp[i];
      }
      return diff == 0;
    };
    return client;
  }

  Future<String> bodyOf(HttpClientResponse resp) =>
      resp.transform(utf8.decoder).join();

  Uint8List blobFrom(String jsonBody) {
    final map = jsonDecode(jsonBody) as Map<String, dynamic>;
    return Uint8List.fromList(base64.decode(map['blob'] as String));
  }

  Future<({String sessionId, Uint8List challenge})> getChallenge(
    PairingSender s,
    HttpClient client,
  ) async {
    final req = await client.getUrl(
      Uri.parse('https://127.0.0.1:${s.port}/challenge'),
    );
    final resp = await req.close();
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      throw StateError('challenge status ${resp.statusCode}');
    }
    final map = jsonDecode(await bodyOf(resp)) as Map<String, dynamic>;
    return (
      sessionId: map['sessionId'] as String,
      challenge: Uint8List.fromList(base64.decode(map['challenge'] as String)),
    );
  }

  Future<HttpClientResponse> postFetch(
    PairingSender s,
    HttpClient client, {
    required String sessionId,
    required List<int> challenge,
    required List<int> proof,
  }) async {
    final req = await client.postUrl(
      Uri.parse('https://127.0.0.1:${s.port}/fetch'),
    );
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({
        'sessionId': sessionId,
        'challenge': base64.encode(challenge),
        'proof': base64.encode(proof),
      }),
    );
    return req.close();
  }

  group('happy path', () {
    test(
      'a correct proof delivers a blob that decrypts to the sent config',
      () async {
        final sender = await startSender();
        addTearDown(sender.dispose);
        final client = pinnedClient(sender.certFingerprint);
        addTearDown(() => client.close(force: true));

        final qr = parseQrPayload(sender.qrPayload);
        await sender.armCode(rightCode);
        final key = await deriveSessionKey(salt: qr.salt, code: rightCode);

        final ch = await getChallenge(sender, client);
        final resp = await postFetch(
          sender,
          client,
          sessionId: ch.sessionId,
          challenge: ch.challenge,
          proof: proofFor(ch.challenge, key),
        );
        expect(resp.statusCode, 200);
        final blob = blobFrom(await bodyOf(resp));
        expect(await openPairingBlob(blob, key), equals(configBytes));
        expect(sender.status.value.phase, PairingPhase.delivered);
      },
    );

    test('the QR pins this session: url, salt, and cert fingerprint', () async {
      final sender = await startSender();
      addTearDown(sender.dispose);
      final parsed = parseQrPayload(sender.qrPayload);
      expect(parsed.url, sender.url);
      expect(parsed.url, 'https://127.0.0.1:${sender.port}');
      expect(parsed.certFingerprint, equals(sender.certFingerprint));
      expect(parsed.salt.length, 16);
    });
  });

  group('authenticate-before-serve', () {
    test('/fetch before the code is armed is a no-strike 425, and the same '
        'challenge still delivers once the code is typed', () async {
      final sender = await startSender();
      addTearDown(sender.dispose);
      final client = pinnedClient(sender.certFingerprint);
      addTearDown(() => client.close(force: true));

      final qr = parseQrPayload(sender.qrPayload);
      final key = await deriveSessionKey(salt: qr.salt, code: rightCode);
      final ch = await getChallenge(sender, client);
      final proof = proofFor(ch.challenge, key);

      // Not armed yet → 425 pending; no strike, challenge NOT consumed.
      final r1 = await postFetch(
        sender,
        client,
        sessionId: ch.sessionId,
        challenge: ch.challenge,
        proof: proof,
      );
      expect(r1.statusCode, 425);
      await r1.drain<void>();
      expect(sender.status.value.failedAttempts, 0);
      expect(sender.status.value.codeArmed, isFalse);

      // Type the (correct) code and retry the SAME challenge+proof → delivered.
      await sender.armCode(rightCode);
      final r2 = await postFetch(
        sender,
        client,
        sessionId: ch.sessionId,
        challenge: ch.challenge,
        proof: proof,
      );
      expect(r2.statusCode, 200);
      final blob = blobFrom(await bodyOf(r2));
      expect(await openPairingBlob(blob, key), equals(configBytes));
      expect(sender.status.value.phase, PairingPhase.delivered);
    });

    test(
      'a wrong code fails with 403 and burns exactly one global strike',
      () async {
        final sender = await startSender();
        addTearDown(sender.dispose);
        final client = pinnedClient(sender.certFingerprint);
        addTearDown(() => client.close(force: true));

        final qr = parseQrPayload(sender.qrPayload);
        await sender.armCode(rightCode); // desktop typed the right code…
        final wrongKey = await deriveSessionKey(salt: qr.salt, code: wrongCode);

        final ch = await getChallenge(sender, client);
        final resp = await postFetch(
          sender,
          client,
          sessionId: ch.sessionId,
          challenge: ch.challenge,
          proof: proofFor(
            ch.challenge,
            wrongKey,
          ), // …but the proof is for another
        );
        expect(resp.statusCode, 403);
        await resp.drain<void>();
        expect(sender.status.value.failedAttempts, 1);
        expect(sender.status.value.phase, PairingPhase.phoneConnected);
      },
    );

    test('a used/unknown challenge is a no-strike 409', () async {
      final sender = await startSender();
      addTearDown(sender.dispose);
      final client = pinnedClient(sender.certFingerprint);
      addTearDown(() => client.close(force: true));

      final qr = parseQrPayload(sender.qrPayload);
      await sender.armCode(rightCode);
      final key = await deriveSessionKey(salt: qr.salt, code: rightCode);
      // A challenge we never issued (fabricated) → 409, not a strike.
      final fake = newChallenge();
      final resp = await postFetch(
        sender,
        client,
        sessionId: sender.sessionId,
        challenge: fake,
        proof: proofFor(fake, key),
      );
      expect(resp.statusCode, 409);
      await resp.drain<void>();
      expect(sender.status.value.failedAttempts, 0);
    });

    test('an oversized /fetch body is refused without a strike (DoS cap)', () async {
      final sender = await startSender();
      addTearDown(sender.dispose);
      final client = pinnedClient(sender.certFingerprint);
      addTearDown(() => client.close(force: true));
      await sender.armCode(rightCode);

      int? status;
      try {
        final req = await client.postUrl(
          Uri.parse('https://127.0.0.1:${sender.port}/fetch'),
        );
        req.headers.contentType = ContentType.json;
        // > 8 KiB, sent without setting contentLength (chunked) so it bypasses any
        // declared-length guard — the streaming cap must still refuse it.
        req.add(List<int>.filled(9000, 0x20));
        final resp = await req.close();
        status = resp.statusCode;
        await resp.drain<void>();
      } catch (_) {
        // The server may close the connection as it rejects the oversized upload
        // mid-stream; that too is a refusal, not a processed request.
        status = null;
      }
      // Either a 4xx rejection or a dropped connection — never accepted/evaluated.
      if (status != null) {
        expect(status, anyOf(400, 413));
      }
      // An oversized body is refused BEFORE any proof evaluation, so it never
      // burns a global strike and the session stays alive.
      expect(sender.status.value.failedAttempts, 0);
    });

    test('a mismatched sessionId is refused (404) without a strike', () async {
      final sender = await startSender();
      addTearDown(sender.dispose);
      final client = pinnedClient(sender.certFingerprint);
      addTearDown(() => client.close(force: true));

      final qr = parseQrPayload(sender.qrPayload);
      await sender.armCode(rightCode);
      final key = await deriveSessionKey(salt: qr.salt, code: rightCode);
      final ch = await getChallenge(sender, client);
      final resp = await postFetch(
        sender,
        client,
        sessionId: 'deadbeefdeadbeef', // not this session
        challenge: ch.challenge,
        proof: proofFor(ch.challenge, key),
      );
      expect(resp.statusCode, 404);
      await resp.drain<void>();
      expect(sender.status.value.failedAttempts, 0);
    });
  });

  group('lockout + one-shot teardown', () {
    test(
      'three failed proofs lock the session (429) and tear it down',
      () async {
        final sender = await startSender();
        addTearDown(sender.dispose);
        final client = pinnedClient(sender.certFingerprint);
        addTearDown(() => client.close(force: true));

        final qr = parseQrPayload(sender.qrPayload);
        await sender.armCode(rightCode);
        final wrongKey = await deriveSessionKey(salt: qr.salt, code: wrongCode);

        int? lastStatus;
        for (var i = 0; i < 3; i++) {
          final ch = await getChallenge(sender, client);
          final resp = await postFetch(
            sender,
            client,
            sessionId: ch.sessionId,
            challenge: ch.challenge,
            proof: proofFor(ch.challenge, wrongKey),
          );
          lastStatus = resp.statusCode;
          await resp.drain<void>();
        }
        expect(lastStatus, 429); // the third strike is the lockout
        expect(sender.status.value.phase, PairingPhase.lockedOut);
        expect(sender.status.value.failedAttempts, 3);

        // Torn down: a further challenge can't be reached at all.
        await expectLater(getChallenge(sender, client), throwsA(anything));
      },
    );

    test('front-loaded concurrent wrong proofs never exceed the global 3-strike '
        'cap', () async {
      // maxConnections high enough that the connection cap does not itself
      // pre-empt the race — we are isolating the GLOBAL 3-strike invariant under
      // concurrency, the property the plan names as load-bearing.
      final sender = await PairingSender.start(
        configBlob: List<int>.from(configBytes),
        host: loopback,
        generateCert: () async => cert,
        maxConnections: 8,
        maxFailedAttempts: 3,
      );
      addTearDown(sender.dispose);
      final client = pinnedClient(sender.certFingerprint);
      addTearDown(() => client.close(force: true));

      final qr = parseQrPayload(sender.qrPayload);
      await sender.armCode(rightCode);
      final wrongKey = await deriveSessionKey(salt: qr.salt, code: wrongCode);

      // Front-load N > maxFailedAttempts distinct challenges, THEN fire every
      // wrong-proof /fetch at once so they all pass the pre-body `_closed` check
      // and suspend at the body read together — the exact interleaving that used
      // to let late resumers land extra guesses during the async reject/teardown
      // window (up to ~maxConnections instead of a hard 3).
      const n = 6;
      final challenges = <({String sessionId, Uint8List challenge})>[];
      for (var i = 0; i < n; i++) {
        challenges.add(await getChallenge(sender, client));
      }
      // Capture a status OR a post-teardown connection error per request, so a
      // socket dropped once the session dies doesn't fail Future.wait.
      Future<int?> fire(({String sessionId, Uint8List challenge}) ch) async {
        try {
          final resp = await postFetch(
            sender,
            client,
            sessionId: ch.sessionId,
            challenge: ch.challenge,
            proof: proofFor(ch.challenge, wrongKey),
          );
          final code = resp.statusCode;
          await resp.drain<void>();
          return code;
        } catch (_) {
          return null; // connection refused/reset after teardown — no strike
        }
      }

      final results = await Future.wait([
        for (final ch in challenges) fire(ch),
      ]);

      // The load-bearing invariant: the GLOBAL strike count is HARD-capped at 3
      // no matter how many wrong proofs raced in (before the fix it reached up to
      // ~maxConnections).
      expect(sender.status.value.failedAttempts, 3);
      expect(sender.status.value.phase, PairingPhase.lockedOut);
      // Only an evaluated wrong proof returns 403; at most (cap - 1) of them can
      // precede the 429 lockout, so no more than two 403s are ever observable —
      // every later resumer is refused (429) WITHOUT a further verifyProof.
      final rejected403 = results.where((s) => s == 403).length;
      expect(rejected403, lessThanOrEqualTo(sender.maxFailedAttempts - 1));
    });

    test(
      'the session is one-shot: it stops serving after a delivery',
      () async {
        final sender = await startSender();
        addTearDown(sender.dispose);
        final client = pinnedClient(sender.certFingerprint);
        addTearDown(() => client.close(force: true));

        final qr = parseQrPayload(sender.qrPayload);
        await sender.armCode(rightCode);
        final key = await deriveSessionKey(salt: qr.salt, code: rightCode);
        final ch = await getChallenge(sender, client);
        final r = await postFetch(
          sender,
          client,
          sessionId: ch.sessionId,
          challenge: ch.challenge,
          proof: proofFor(ch.challenge, key),
        );
        expect(r.statusCode, 200);
        await r.drain<void>();
        expect(sender.status.value.phase, PairingPhase.delivered);

        // A fresh pinned client can no longer reach the torn-down server.
        final probe = pinnedClient(sender.certFingerprint);
        addTearDown(() => probe.close(force: true));
        await expectLater(getChallenge(sender, probe), throwsA(anything));
      },
    );
  });

  group('source-address guard (pure)', () {
    test(
      'allows loopback + private/link-local; rejects public + near-miss',
      () {
        expect(isAllowedPairingSource(InternetAddress('127.0.0.1')), isTrue);
        expect(isAllowedPairingSource(InternetAddress('::1')), isTrue);
        expect(isAllowedPairingSource(InternetAddress('10.1.2.3')), isTrue);
        expect(isAllowedPairingSource(InternetAddress('172.16.0.9')), isTrue);
        expect(isAllowedPairingSource(InternetAddress('192.168.1.5')), isTrue);
        expect(isAllowedPairingSource(InternetAddress('169.254.9.9')), isTrue);
        expect(isAllowedPairingSource(InternetAddress('8.8.8.8')), isFalse);
        expect(isAllowedPairingSource(InternetAddress('172.32.0.1')), isFalse);
        expect(isAllowedPairingSource(InternetAddress('11.0.0.1')), isFalse);
      },
    );

    test('isPrivateIpv4 boundary correctness', () {
      for (final ok in const [
        '10.0.0.0',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.0.1',
        '169.254.1.1',
        '127.0.0.1',
      ]) {
        expect(isPrivateIpv4(ok), isTrue, reason: ok);
      }
      for (final no in const [
        '172.15.0.1',
        '172.32.0.1',
        '192.169.0.1',
        '11.0.0.1',
        '169.253.0.1',
        '8.8.8.8',
        '1.1.1.1',
        '192.168.1', // too few octets
        '192.168.1.256', // out of range
        '010.0.0.1', // leading-zero octet (octal-ambiguous, non-canonical)
        '192.168.01.1', // leading-zero octet
        '127.00.0.1', // leading-zero octet
      ]) {
        expect(isPrivateIpv4(no), isFalse, reason: no);
      }
    });
  });

  group('interop with the real phone receiver', () {
    test(
      'PairingReceiver fetches + decrypts + parses the served config',
      () async {
        final sender = await startSender();
        addTearDown(sender.dispose);
        await sender.armCode(
          rightCode,
        ); // arm first so the single attempt succeeds

        final qr = parseQrPayload(sender.qrPayload);
        ConfigModel? received;
        await const PairingReceiver().receive(
          qr: qr,
          code: rightCode,
          onConfig: (m) => received = m,
        );
        expect(received, isNotNull);
        expect(received!.containsKey('drive'), isTrue);
        expect(received!['drive']?['type'], 'drive');
        expect(sender.status.value.phase, PairingPhase.delivered);
      },
    );

    test(
      'PairingReceiver with a wrong code is rejected and strikes once',
      () async {
        final sender = await startSender();
        addTearDown(sender.dispose);
        await sender.armCode(rightCode);

        final qr = parseQrPayload(sender.qrPayload);
        await expectLater(
          const PairingReceiver().receive(
            qr: qr,
            code: wrongCode,
            onConfig: (_) {},
          ),
          throwsA(isA<PairingReceiverError>()),
        );
        expect(sender.status.value.failedAttempts, 1);
        expect(sender.status.value.phase, PairingPhase.phoneConnected);
      },
    );

    test('the real pinned transport enforces the pin: a non-matching fingerprint '
        'is rejected as pinMismatch, never delivered', () async {
      // Drives the PRODUCTION PinnedHttpPairingTransport (built over
      // SecurityContext(withTrustedRoots: false)) against the real TLS server.
      // The happy path — a MATCHING fingerprint delivering + decrypting — is the
      // interop test above, so this proves the complementary half: a cert whose
      // DER fingerprint does not match the pin is refused at the handshake. With
      // no trusted roots EVERY cert fails default validation, so the fingerprint
      // callback is the sole, unconditional trust decision and can never be
      // silently skipped (the trusted-root bypass the fix closes).
      final sender = await startSender();
      addTearDown(sender.dispose);
      await sender.armCode(rightCode);

      final qr = parseQrPayload(sender.qrPayload);
      // Pin a DIFFERENT fingerprint than the server's real cert (flip a byte).
      final wrongFp = Uint8List.fromList(qr.certFingerprint);
      wrongFp[0] ^= 0xFF;
      final tamperedQr = (url: qr.url, salt: qr.salt, certFingerprint: wrongFp);

      await expectLater(
        const PairingReceiver().receive(
          qr: tamperedQr,
          code: rightCode,
          onConfig: (_) {},
        ),
        throwsA(
          isA<PairingReceiverError>().having(
            (e) => e.kind,
            'kind',
            PairingFailureKind.pinMismatch,
          ),
        ),
      );
      // The pin aborted at the handshake — no /fetch body, nothing delivered.
      expect(sender.status.value.phase, isNot(PairingPhase.delivered));
    });
  });
}
