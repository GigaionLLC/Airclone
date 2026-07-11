import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as pc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_io.dart';
import 'pairing_protocol.dart';

/// The PHONE RECEIVER for the QR/LAN "Send to phone" handoff
/// (dev/plans/config-portability-plan.md §5, v3 QR-pinned-TLS). This is the
/// network-facing half that consumes the pure protocol core (pairing_protocol.dart)
/// — it runs the authenticate-before-serve handshake over a TLS channel PINNED to
/// the cert fingerprint carried in the QR, decrypts the served config blob under
/// the session key derived from `salt ∥ code`, and hands the parsed remotes to the
/// MANDATORY import preview/merge wizard (never applying them directly).
///
/// Security invariants realised here (from the plan + its 2026-07-09 review):
///  - PIN-BEFORE-BODY: every request rides an [HttpClient] built over a
///    trust-empty [SecurityContext] (no system/user CA roots), so default chain
///    validation fails for EVERY cert and `badCertificateCallback` — which accepts
///    ONLY the exact pinned SHA-256(DER) — is the whole, UNCONDITIONAL trust
///    decision. A MITM's cert (even one that chains to a device-trusted root, e.g.
///    an enterprise/MDM or TLS-inspection CA on a managed device) fails the pin and
///    the connection never carries application bytes. Because the challenge request
///    precedes the fetch, a failed pin aborts BEFORE any fetch body is read.
///  - The session SALT never travels on the wire — it lives only in the QR and
///    feeds [deriveSessionKey] locally. Correlation to the session uses the
///    server-minted, wire-safe session id from the `/challenge` response.
///  - Per-CONNECTION challenge: each attempt fetches a fresh challenge and answers
///    its own; the phone proves knowledge of the derived key via
///    `HMAC(key, challenge)` ([proofFor]) so the ciphertext is served only to a
///    peer that knows the code — closing the offline brute-force oracle a bare
///    ciphertext + QR-salt would otherwise be.
///  - Failed proofs are counted GLOBALLY per session by the SERVER (3 strikes);
///    this side simply surfaces a proof rejection vs. a lockout distinctly so the
///    UI can say "wrong code" vs. "someone may be interfering on your network".
///  - Keys/proofs are per-session and [zeroize]d as soon as the attempt ends; the
///    code is a short-lived String (immutable — can't be wiped, kept transient).
///
/// The socket/TLS work is isolated behind [PairingTransport] so the orchestration
/// ([PairingReceiver.receive]) — derive → challenge → proof → fetch → decrypt →
/// parse → hand off — is unit-tested with a fake transport, no camera and no real
/// network. The one genuinely security-critical leaf that the production transport
/// adds, the pin comparison, is extracted as the pure [certFingerprintMatches] so
/// it too is asserted directly.

// --- Wire protocol -----------------------------------------------------------
//
// Two authenticated calls under the QR-advertised base URL, both over the pinned
// TLS channel. This is the canonical v3 pairing wire contract the desktop SENDER
// (pairing_sender.dart) must serve verbatim:
//
//   GET  <base>/challenge
//     200 → {"sessionId": "<hex>", "challenge": "<base64 32B>"}
//     The server mints the session id ONCE per session (stable, wire-safe — never
//     the salt) and a FRESH 32-byte challenge per request ([newChallenge]).
//
//   POST <base>/fetch   {"sessionId": "<hex>", "challenge": "<base64>",
//                        "proof": "<base64 32B>"}
//     200 → {"blob": "<base64 nonce∥ct∥mac>"}   the sealed config ([sealPairingBlob])
//     401/403 → proof rejected (wrong code); server increments its global fail count
//     429     → locked out (3 strikes) — surfaced as possible interference
//     202/409/425 → not ready yet (desktop is still waiting for the typed code);
//                   the caller may retry on a fresh connection/challenge
//
// `<base>` is the QR url with any trailing slash trimmed; endpoints are appended
// as `/challenge` and `/fetch`.

/// A parsed `/challenge` response: the wire-safe session correlation id and the
/// per-connection challenge to prove against. A record (immutable tuple) the
/// receiver destructures immediately.
typedef PairingChallenge = ({String sessionId, Uint8List challenge});

/// The outcome of a `/fetch` POST, modelled as a sealed hierarchy so the receiver
/// switch is exhaustive and each server status maps to one honest UI story.
sealed class PairingFetchResult {
  const PairingFetchResult();
}

/// The server authenticated the proof and served the sealed config [blob]
/// (`nonce ∥ ciphertext ∥ mac`, still encrypted under the session key).
class PairingBlobDelivered extends PairingFetchResult {
  const PairingBlobDelivered(this.blob);
  final Uint8List blob;
}

/// The server rejected the proof (a wrong pairing code derives a wrong key). One
/// of the server's global 3-strike attempts was consumed.
class PairingProofRejected extends PairingFetchResult {
  const PairingProofRejected();
}

/// The server has hit its global failure cap and refuses further attempts — the
/// session is dead. Persistent lockouts read as possible network interference,
/// not merely a mistyped code.
class PairingLockedOut extends PairingFetchResult {
  const PairingLockedOut();
}

/// The desktop hasn't accepted the typed code yet, so no key exists to verify a
/// proof against. Not an error — the caller retries on a fresh connection.
class PairingNotReady extends PairingFetchResult {
  const PairingNotReady();
}

// --- Errors ------------------------------------------------------------------

/// Why a receive attempt could not complete, so the sheet can render the right
/// honest message (and decide whether a retry makes sense — only [notReady] does).
enum PairingFailureKind {
  /// Couldn't reach/handshake the desktop (different Wi-Fi, server gone, timeout).
  unreachable,

  /// The presented TLS cert didn't match the pinned QR fingerprint — a MITM or a
  /// stale/overlay QR. Never proceed.
  pinMismatch,

  /// The desktop rejected the code (wrong code → wrong key).
  wrongCode,

  /// The session is locked (too many failed attempts) — possible interference.
  lockedOut,

  /// The desktop is still waiting for the code to be typed; retry shortly.
  notReady,

  /// The blob decrypted but wasn't a parseable config (should never happen on a
  /// well-behaved sender; treated as corruption, not "wrong code").
  corruptConfig,

  /// The server spoke something other than the v3 wire contract.
  protocol,
}

/// A typed, user-actionable receive failure. Carries a friendly [message] the
/// sheet shows verbatim and a [kind] it branches on (retry vs. terminal). Free of
/// any secret material by construction — never embeds the code, key, or blob.
class PairingReceiverError implements Exception {
  const PairingReceiverError(this.kind, this.message);
  final PairingFailureKind kind;
  final String message;
  @override
  String toString() => 'PairingReceiverError($kind): $message';
}

// --- Cert pinning (the production transport's one security-critical leaf) -----

/// True iff SHA-256 over the presented cert's DER equals the [pinnedSha256] from
/// the QR, compared in CONSTANT TIME. This is the entire trust decision for the
/// pinned channel: the client is built over a TRUST-EMPTY [SecurityContext]
/// ([PinnedHttpPairingTransport._pinnedClient]), so EVERY presented cert fails
/// default chain validation and `badCertificateCallback` is consulted
/// UNCONDITIONALLY — it MUST accept only the one fingerprint the QR committed to.
/// A length mismatch or any differing byte returns false; a plain `==` here would
/// be a timing oracle on the pin.
bool certFingerprintMatches(List<int> der, List<int> pinnedSha256) {
  final digest = pc.sha256.convert(der).bytes;
  return constantTimeBytesEqual(digest, pinnedSha256);
}

// --- Transport ---------------------------------------------------------------

/// The two network calls the handshake needs, isolated so the orchestration is
/// tested with a fake and only [PinnedHttpPairingTransport] touches sockets/TLS.
abstract interface class PairingTransport {
  /// Fetches a fresh challenge (+ the session id) from `<base>/challenge`. In the
  /// pinned transport this is the FIRST TLS handshake, so a pin failure surfaces
  /// here — before any `/fetch` body is ever requested.
  Future<PairingChallenge> requestChallenge();

  /// Posts the [proof] for [challenge] under session [sessionId] to `<base>/fetch`
  /// and classifies the reply into a [PairingFetchResult].
  Future<PairingFetchResult> fetchBlob({
    required String sessionId,
    required List<int> challenge,
    required List<int> proof,
  });

  /// Releases the underlying client. Always called once per attempt (in a
  /// `finally`), so a dead session never leaks a socket.
  Future<void> close();
}

/// The production [PairingTransport]: an [HttpClient] pinned to the QR's cert
/// fingerprint, speaking the JSON wire contract above. Constructed per attempt
/// (fresh client, fresh connection, fresh challenge) and closed in the receiver's
/// `finally`.
class PinnedHttpPairingTransport implements PairingTransport {
  PinnedHttpPairingTransport({
    required String baseUrl,
    required List<int> pinnedFingerprint,
    Duration timeout = const Duration(seconds: 12),
  }) : _base = _trimTrailingSlashes(baseUrl),
       _timeout = timeout,
       _client = _pinnedClient(pinnedFingerprint, timeout);

  final String _base;
  final Duration _timeout;
  final HttpClient _client;

  /// The largest response body we will buffer from the desktop. A pairing reply is
  /// a small JSON envelope — a session id + a 32-byte challenge, or a few-KB config
  /// blob — so 1 MiB is a generous ceiling. A pinned-but-compromised sender, or a
  /// MITM, streaming an unbounded body is refused before it can OOM the phone.
  static const int _maxResponseBytes = 1 << 20; // 1 MiB

  static String _trimTrailingSlashes(String url) =>
      url.replaceAll(RegExp(r'/+$'), '');

  static HttpClient _pinnedClient(List<int> pinned, Duration timeout) {
    // Build over a TRUST-EMPTY context (no system/user CA roots). With no trusted
    // roots EVERY server cert fails dart:io's default chain validation, so
    // `badCertificateCallback` runs UNCONDITIONALLY and the fingerprint check below
    // is the sole trust decision. A plain `HttpClient()` uses SecurityContext's
    // default (platform) root store, and dart:io consults badCertificateCallback
    // ONLY when built-in validation FAILS — so a MITM cert that chains to a
    // device-trusted root (an enterprise/MDM or TLS-inspection CA on a managed
    // device, the app's stated market) would be accepted WITHOUT the pin ever being
    // compared. This mirrors the sender's SecurityContext(withTrustedRoots: false)
    // (pairing_sender.dart) so the pin is no longer one-sided.
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false));
    c.connectionTimeout = timeout;
    // The ONLY accepted cert is the one whose DER hashes to the pinned QR
    // fingerprint. Everything else (a real CA cert, a MITM cert, a re-keyed
    // desktop) is refused, so no application bytes ever cross an unpinned channel.
    c.badCertificateCallback = (X509Certificate cert, String host, int port) =>
        certFingerprintMatches(cert.der, pinned);
    return c;
  }

  Uri _endpoint(String path) => Uri.parse('$_base/$path');

  @override
  Future<PairingChallenge> requestChallenge() async {
    try {
      final req = await _client.getUrl(_endpoint('challenge'));
      _refuseRedirects(req);
      final resp = await req.close().timeout(_timeout);
      if (resp.statusCode != 200) {
        throw PairingReceiverError(
          PairingFailureKind.protocol,
          'The computer answered unexpectedly (status ${resp.statusCode}).',
        );
      }
      final body = await _readCappedBody(resp).timeout(_timeout);
      final map = _asJsonMap(body);
      final sessionId = map['sessionId'];
      final challengeB64 = map['challenge'];
      if (sessionId is! String || challengeB64 is! String) {
        throw const PairingReceiverError(
          PairingFailureKind.protocol,
          "The computer's reply wasn't a valid pairing challenge.",
        );
      }
      return (
        sessionId: sessionId,
        challenge: Uint8List.fromList(base64.decode(challengeB64)),
      );
    } on PairingReceiverError {
      rethrow;
    } catch (e) {
      throw _mapTransportError(e);
    }
  }

  @override
  Future<PairingFetchResult> fetchBlob({
    required String sessionId,
    required List<int> challenge,
    required List<int> proof,
  }) async {
    try {
      final req = await _client.postUrl(_endpoint('fetch'));
      _refuseRedirects(req);
      req.headers.contentType = ContentType.json;
      req.add(
        utf8.encode(
          jsonEncode({
            'sessionId': sessionId,
            'challenge': base64.encode(challenge),
            'proof': base64.encode(proof),
          }),
        ),
      );
      final resp = await req.close().timeout(_timeout);
      switch (resp.statusCode) {
        case 200:
          final body = await _readCappedBody(resp).timeout(_timeout);
          final map = _asJsonMap(body);
          final blobB64 = map['blob'];
          if (blobB64 is! String) {
            throw const PairingReceiverError(
              PairingFailureKind.protocol,
              "The computer's reply didn't contain a config.",
            );
          }
          return PairingBlobDelivered(
            Uint8List.fromList(base64.decode(blobB64)),
          );
        case 401 || 403:
          await resp.drain<void>();
          return const PairingProofRejected();
        case 429:
          await resp.drain<void>();
          return const PairingLockedOut();
        case 202 || 409 || 425:
          await resp.drain<void>();
          return const PairingNotReady();
        default:
          await resp.drain<void>();
          throw PairingReceiverError(
            PairingFailureKind.protocol,
            'The computer answered unexpectedly (status ${resp.statusCode}).',
          );
      }
    } on PairingReceiverError {
      rethrow;
    } catch (e) {
      throw _mapTransportError(e);
    }
  }

  Map<String, dynamic> _asJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const PairingReceiverError(
        PairingFailureKind.protocol,
        "The computer's reply wasn't valid JSON.",
      );
    }
    return decoded;
  }

  /// Refuses to follow HTTP redirects on a pinned request. The v3 wire contract is
  /// a fixed two-endpoint protocol, so no 3xx is ever legitimate: an `https->http`
  /// redirect would drop TLS off the pinned channel entirely (the pin callback
  /// never fires for plaintext), and a cross-host redirect would escape the
  /// private-IPv4 check that only ran once on the base URL. With following off, a
  /// 3xx surfaces as a non-200 status and is treated as a protocol error, not
  /// chased off the pinned channel.
  void _refuseRedirects(HttpClientRequest req) {
    req.followRedirects = false;
    req.maxRedirects = 0;
  }

  /// Reads [resp]'s body into a UTF-8 String, aborting past [_maxResponseBytes]
  /// regardless of any declared Content-Length (a chunked reply carries none).
  /// Unlike `resp.transform(utf8.decoder).join()` this counts bytes as they arrive,
  /// so a pinned-but-malicious sender — or a MITM — can't stream an unbounded body
  /// and OOM the phone before any auth/decrypt decision matters. A legitimate
  /// config reply is a few KB, so anything past the ceiling is a protocol error.
  Future<String> _readCappedBody(HttpClientResponse resp) async {
    if (resp.contentLength > _maxResponseBytes) {
      throw const PairingReceiverError(
        PairingFailureKind.protocol,
        'The computer sent an unexpectedly large reply.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
      if (bytes.length > _maxResponseBytes) {
        throw const PairingReceiverError(
          PairingFailureKind.protocol,
          'The computer sent an unexpectedly large reply.',
        );
      }
    }
    return utf8.decode(bytes);
  }

  /// Maps a raw socket/TLS/timeout failure to a typed receiver error. A
  /// [HandshakeException]/[TlsException] means the cert was refused — i.e. the pin
  /// didn't match (or the channel is being tampered with); everything else is a
  /// plain reachability problem the UI blames on the network.
  PairingReceiverError _mapTransportError(Object e) {
    if (e is HandshakeException || e is TlsException) {
      return const PairingReceiverError(
        PairingFailureKind.pinMismatch,
        "The computer's security certificate didn't match the QR code. Scan a "
        'freshly generated code, or someone may be interfering with your '
        'network.',
      );
    }
    return const PairingReceiverError(
      PairingFailureKind.unreachable,
      "Couldn't reach the computer. Make sure both devices are on the same "
      'Wi-Fi and the code is still showing.',
    );
  }

  @override
  Future<void> close() async {
    _client.close(force: true);
  }
}

// --- Config parsing (decrypted blob -> model) --------------------------------

/// Parses a decrypted config blob (INI or `config dump` JSON, optionally BOM'd)
/// into the shared [ConfigModel], reusing config_io's public parsers. Mirrors the
/// sniff config_transfer_controller does for a picked file, so a QR-delivered
/// config lands in exactly the same model the file-import wizard reviews. Throws
/// [FormatException] on unparseable bytes (surfaced upstream as a corrupt config).
ConfigModel parsePairingConfigBytes(List<int> bytes) {
  final text = _decodeUtf8(bytes);
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{')) return parseDumpJson(text);
  return parseIni(text);
}

const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

String _decodeUtf8(List<int> bytes) {
  final body =
      (bytes.length >= 3 &&
          bytes[0] == _utf8Bom[0] &&
          bytes[1] == _utf8Bom[1] &&
          bytes[2] == _utf8Bom[2])
      ? bytes.sublist(3)
      : bytes;
  return utf8.decode(body);
}

// --- Receiver ----------------------------------------------------------------

/// Orchestrates ONE authenticated fetch attempt: derive the session key from the
/// QR salt + the phone-shown code, run the challenge/proof handshake over the
/// pinned transport, decrypt the served blob, parse it, and hand the resulting
/// [ConfigModel] to [onConfig] (the sheet then drives the MANDATORY preview/merge
/// wizard — this layer NEVER writes to the live config).
///
/// A single attempt by design: the desktop only has a key AFTER the user types the
/// code, so the first attempt commonly returns [PairingNotReady]; the sheet retries
/// on a fresh connection (new challenge) until a short deadline. Keeping the
/// attempt atomic makes the happy path and every failure mode trivially testable
/// with a fake transport, and keeps key/proof lifetimes tight — both are
/// [zeroize]d in the `finally`.
class PairingReceiver {
  const PairingReceiver();

  /// Runs one attempt for a validated [qr] using the phone-generated [code].
  /// [transportOverride] injects a fake in tests; production builds a
  /// [PinnedHttpPairingTransport] pinned to `qr.certFingerprint`.
  ///
  /// On success calls [onConfig] with the parsed remotes exactly once. Otherwise
  /// throws a typed [PairingReceiverError] — [PairingFailureKind.notReady] is the
  /// only one the caller should retry.
  Future<void> receive({
    required ParsedQrPayload qr,
    required String code,
    required void Function(ConfigModel config) onConfig,
    PairingTransport? transportOverride,
  }) async {
    final transport =
        transportOverride ??
        PinnedHttpPairingTransport(
          baseUrl: qr.url,
          pinnedFingerprint: qr.certFingerprint,
        );
    // HKDF over salt ∥ code — fast, so re-deriving per retry costs nothing and
    // lets us zeroize the key at the end of every attempt.
    final key = await deriveSessionKey(salt: qr.salt, code: code);
    Uint8List? proof;
    try {
      // Challenge first: in the pinned transport this is the handshake, so a pin
      // mismatch throws HERE and no /fetch body is ever requested.
      final challenge = await transport.requestChallenge();
      proof = proofFor(challenge.challenge, key);
      final result = await transport.fetchBlob(
        sessionId: challenge.sessionId,
        challenge: challenge.challenge,
        proof: proof,
      );
      switch (result) {
        case PairingBlobDelivered(:final blob):
          Uint8List clear;
          try {
            clear = await openPairingBlob(blob, key);
          } on WrongPairingKey {
            // The server served a blob but it doesn't open under our key. With a
            // matching code this can't happen; treat as a code mismatch.
            throw const PairingReceiverError(
              PairingFailureKind.wrongCode,
              "Couldn't decrypt the config — the code didn't match. Try again "
              'with a fresh QR code.',
            );
          } on CorruptPairingBlob {
            throw const PairingReceiverError(
              PairingFailureKind.corruptConfig,
              'The computer sent a config that looked corrupted.',
            );
          }
          ConfigModel model;
          try {
            model = parsePairingConfigBytes(clear);
          } on FormatException {
            throw const PairingReceiverError(
              PairingFailureKind.corruptConfig,
              "The computer's config couldn't be read.",
            );
          } finally {
            zeroize(clear); // decrypted config text — wipe once parsed
          }
          onConfig(model);
        case PairingProofRejected():
          throw const PairingReceiverError(
            PairingFailureKind.wrongCode,
            "The computer didn't accept that code. Check the code it's showing "
            'and try again.',
          );
        case PairingLockedOut():
          throw const PairingReceiverError(
            PairingFailureKind.lockedOut,
            'Too many attempts — the transfer was stopped. Start a new "Send to '
            'phone" on the computer. If this keeps happening, someone may be '
            'interfering with your network.',
          );
        case PairingNotReady():
          throw const PairingReceiverError(
            PairingFailureKind.notReady,
            'Waiting for you to type the code on the computer…',
          );
      }
    } finally {
      // Per-session secrets die with the attempt (plan §5): never persisted,
      // never logged, wiped as soon as the attempt ends.
      zeroize(key);
      if (proof != null) zeroize(proof);
      await transport.close();
    }
  }
}

/// The receiver as a plain service behind a [Provider] (it holds no state — a new
/// transport is built per attempt). Mirrors [configTransferControllerProvider]'s
/// shape; the scan sheet reads it to run the handshake.
final pairingReceiverProvider = Provider<PairingReceiver>(
  (ref) => const PairingReceiver(),
);
