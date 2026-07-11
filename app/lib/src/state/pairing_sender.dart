import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pairing_protocol.dart';

/// The DESKTOP SENDER for the QR/LAN "Send to phone" handoff
/// (dev/plans/config-portability-plan.md §5, v3 QR-pinned-TLS). This is the most
/// security-critical service in the app: it stands up a one-shot,
/// authenticate-before-serve LAN endpoint over a per-session self-signed TLS cert
/// whose fingerprint rides in the QR, and only ever hands the (already-encrypted)
/// config blob to a peer that proves knowledge of the pairing code the phone
/// showed. It consumes the pure protocol core ([pairing_protocol.dart]) verbatim
/// and serves EXACTLY the wire contract the phone receiver ([pairing_receiver.dart])
/// speaks:
///
///   GET  /challenge
///     `200 → {"sessionId": "<hex>", "challenge": "<base64 32B>"}`
///   POST /fetch  {"sessionId","challenge","proof"}
///     `200 → {"blob": "<base64 nonce∥ct∥mac>"}`  (one-shot: the session then dies)
///     403 → wrong code (a global strike is counted; 3 kills the session)
///     429 → locked out (3 strikes reached — surfaced as possible interference)
///     425 → not ready (the desktop user hasn't typed the code yet — retry)
///     409 → unknown/used challenge (GET a fresh /challenge and retry)
///
/// Security invariants realised here (from the plan + its 2026-07-09 review):
///  - The QR-pinned TLS channel is the confidentiality substrate: the desktop
///    generates an EPHEMERAL self-signed cert per session; the phone pins exactly
///    its SHA-256(DER) (carried in the QR), so a sniffer sees nothing and a MITM
///    fails the pin. Only then is the short pairing code honest "anti-race
///    authorization" rather than an offline brute-force oracle.
///  - The session SALT (and the derived key) NEVER travel on the wire — the salt
///    lives only in the QR; correlation uses a SEPARATE random session id
///    ([newSessionId]) minted here and echoed back inside TLS.
///  - The KEY cannot be derived until the user types the code the phone shows, so
///    /challenge is served immediately but /fetch only SUCCEEDS once [armCode]
///    has run; before that every /fetch is a no-strike "not ready".
///  - Per-CONNECTION challenge, single-use: the ciphertext is served only to a
///    request that answers a fresh challenge WE issued, and that challenge is
///    consumed on use. No bearer tokens, no global "released" flag.
///  - Failed proofs are counted GLOBALLY per session (3 kills it) — never
///    per-connection, so parallel connections can't void the cap.
///  - The server binds to the SPECIFIC advertised LAN interface (NEVER 0.0.0.0)
///    on an ephemeral port, rejects non-private/non-loopback source addresses,
///    bounds outstanding challenges, and tears down on first success, lockout,
///    the 5-minute TTL, or dispose.
///  - Codes/salts/keys/blob are per-session, never persisted, never logged, and
///    [zeroize]d on teardown (the code is a short-lived immutable String).

// --- Ephemeral TLS identity --------------------------------------------------

/// A per-session self-signed TLS identity: the cert + its private key as PEM
/// (what a [SecurityContext] binds) plus the SHA-256 of the cert's DER (what
/// rides in the QR so the phone pins exactly this cert). All fields are plain
/// strings/bytes so an instance is trivially sendable across an isolate boundary.
@immutable
class EphemeralCert {
  const EphemeralCert({
    required this.certPem,
    required this.privateKeyPem,
    required this.sha256Fingerprint,
  });

  final String certPem;
  final String privateKeyPem;
  final Uint8List sha256Fingerprint;
}

/// A cert minting function — injectable so tests can supply a pre-generated cert
/// (real TLS, no per-test keygen) while production uses [generateEphemeralCert].
typedef CertGenerator = Future<EphemeralCert> Function();

/// Mints the ephemeral cert on a BACKGROUND isolate. RSA-2048 keygen is CPU-bound
/// and would jank the UI on the main isolate; the result is only PEM strings + a
/// digest, so hopping isolates is cheap. The default [CertGenerator].
Future<EphemeralCert> generateEphemeralCert() =>
    Isolate.run(generateEphemeralCertSync);

/// The pure, synchronous cert mint (also called directly by tests so they exercise
/// the real TLS path without an isolate hop). Generates an RSA-2048 keypair, wraps
/// it in a short-lived self-signed X.509 via `basic_utils`
/// (CryptoUtils.generateRSAKeyPair → X509Utils.generateRsaCsrPem →
/// X509Utils.generateSelfSignedCertificate), and returns the cert/key PEM plus the
/// cert DER's SHA-256. Validity is irrelevant to the pinned channel (the phone's
/// `badCertificateCallback` pins the fingerprint and bypasses chain/expiry checks),
/// so a 1-day cert is fine.
EphemeralCert generateEphemeralCertSync() {
  final pair = bu.CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final priv = pair.privateKey as bu.RSAPrivateKey;
  final pub = pair.publicKey as bu.RSAPublicKey;
  // A CSR is basic_utils' input to the self-signer; the DN is cosmetic (pinning,
  // not name validation, is the trust decision) so a fixed CN is fine.
  final csr = bu.X509Utils.generateRsaCsrPem(
    const {'CN': 'Airclone Pairing'},
    priv,
    pub,
  );
  final certPem = bu.X509Utils.generateSelfSignedCertificate(priv, csr, 1);
  final keyPem = bu.CryptoUtils.encodeRSAPrivateKeyToPem(priv);
  return EphemeralCert(
    certPem: certPem,
    privateKeyPem: keyPem,
    sha256Fingerprint: sha256OfCertPem(certPem),
  );
}

/// The SHA-256 over a cert PEM's DER body — the fingerprint the phone pins. Strips
/// the PEM armor + whitespace, base64-decodes to DER, and hashes it, so the result
/// equals `sha256(X509Certificate.der)` the phone computes from the presented cert.
Uint8List sha256OfCertPem(String certPem) {
  final b64 = certPem
      .replaceAll('-----BEGIN CERTIFICATE-----', '')
      .replaceAll('-----END CERTIFICATE-----', '')
      .replaceAll(RegExp(r'\s+'), '');
  final der = base64.decode(b64);
  return Uint8List.fromList(crypto.sha256.convert(der).bytes);
}

// --- LAN host discovery + source guard ---------------------------------------

/// A candidate LAN host to bind + advertise: a private IPv4 literal and the
/// interface it belongs to (for the "on a different network?" troubleshooting UI).
@immutable
class LanHost {
  const LanHost({required this.address, required this.interfaceName});

  final String address; // dotted-quad IPv4
  final String interfaceName;

  @override
  bool operator ==(Object other) =>
      other is LanHost &&
      other.address == address &&
      other.interfaceName == interfaceName;

  @override
  int get hashCode => Object.hash(address, interfaceName);

  @override
  String toString() => '$address ($interfaceName)';
}

/// True when [host] is a dotted-quad IPv4 in a private or link-local range:
/// `10/8`, `172.16/12`, `192.168/16`, `169.254/16` (link-local), or `127/8`
/// (loopback). Octets must be pure canonical decimal 0..255 — a leading `+`,
/// whitespace, a leading-zero (octal-ambiguous) octet, or an overlong octet is
/// rejected. Mirrors the phone-side guard in pairing_protocol.dart so the sender
/// and the QR validator agree on "private".
bool isPrivateIpv4(String host) {
  final octets = host.split('.');
  if (octets.length != 4) return false;
  final parts = <int>[];
  for (final o in octets) {
    if (o.isEmpty || o.length > 3) return false;
    // Reject a leading zero on a multi-digit octet ('010', '00'): several platform
    // resolvers read a leading-zero octet as OCTAL, so accepting it here (as
    // decimal 10) would be a validator/resolver differential — the guard sees 10.x
    // while a socket dials 8.x. A canonical dotted-quad has no leading zeros.
    if (o.length > 1 && o.codeUnitAt(0) == 0x30) return false;
    for (final unit in o.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false; // not 0-9
    }
    final n = int.parse(o);
    if (n > 255) return false;
    parts.add(n);
  }
  final a = parts[0];
  final b = parts[1];
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  if (a == 169 && b == 254) return true;
  if (a == 127) return true;
  return false;
}

/// Whether a request's SOURCE address is allowed to reach the pairing endpoint.
/// The server already binds to one private interface, but this is the
/// belt-and-suspenders check the plan requires: allow loopback (so the in-process
/// tests and same-machine tools work) and private/link-local IPv4; reject a public
/// IPv4 and every non-loopback IPv6. A hostile packet routed to the bound port
/// from off-subnet is refused before any handler logic runs.
///
/// SCOPE (deliberate): this admits ANY private/link-local range, not only the
/// bound interface's own subnet. A strictly-same-subnet check would need the
/// interface's netmask/prefix, which dart:io's [NetworkInterface] does not expose
/// in its public API — and the specific-interface bind (never 0.0.0.0) already
/// stops off-subnet peers from reaching the socket in practice. We therefore keep
/// the broader private-only guard rather than weaken to a mask we can't read; the
/// only residual gap is a multi-homed/forwarding host routing one private subnet
/// to the bound endpoint on another, which the specific bind already makes hard.
bool isAllowedPairingSource(InternetAddress addr) {
  if (addr.isLoopback) return true; // 127/8 and ::1
  if (addr.type == InternetAddressType.IPv4) return isPrivateIpv4(addr.address);
  return false;
}

/// Enumerates the machine's private IPv4 hosts, best-first (192.168 / 10 / 172
/// before link-local 169.254). Loopback is excluded — it's a valid BIND target
/// (used by tests) but never something to advertise to a phone. Empty when the
/// machine has no private IPv4 (e.g. no LAN); [PairingSender.start] then reports a
/// friendly "no local network" error unless the caller passed an explicit host.
Future<List<LanHost>> discoverLanHosts() async {
  final result = <LanHost>[];
  final ifaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: true,
  );
  for (final iface in ifaces) {
    for (final a in iface.addresses) {
      if (a.type != InternetAddressType.IPv4 || a.isLoopback) continue;
      if (isPrivateIpv4(a.address)) {
        result.add(LanHost(address: a.address, interfaceName: iface.name));
      }
    }
  }
  result.sort((x, y) => _hostRank(x.address).compareTo(_hostRank(y.address)));
  return result;
}

int _hostRank(String ip) {
  if (ip.startsWith('192.168.')) return 0;
  if (ip.startsWith('10.')) return 1;
  if (ip.startsWith('172.')) return 2;
  if (ip.startsWith('169.254.')) return 4; // link-local advertised last
  return 3;
}

// --- Errors + status ---------------------------------------------------------

/// A user-actionable failure standing up (or during) a pairing session — no LAN
/// found, a bind failure. Carries a friendly [message] the dialog surfaces inline.
class PairingSenderError implements Exception {
  const PairingSenderError(this.message);
  final String message;
  @override
  String toString() => 'PairingSenderError: $message';
}

/// Internal signal that a /fetch request body exceeded [PairingSender]'s hard cap
/// — caught in `_fetch` and answered with 413 rather than buffering an unbounded
/// request. Never surfaced to the UI; it exists only to unwind the capped read.
class _RequestBodyTooLarge implements Exception {
  const _RequestBodyTooLarge();
}

/// Where a live session is in its lifecycle, for the dialog's status line.
enum PairingPhase {
  /// Server up, QR shown, no phone has fetched a challenge yet.
  waiting,

  /// A phone has fetched at least one challenge (it scanned + connected).
  phoneConnected,

  /// The sealed config was served on an authenticated connection — done.
  delivered,

  /// 3 failed proofs — the session was killed (possible interference).
  lockedOut,

  /// The 5-minute TTL elapsed before a successful transfer.
  expired,

  /// An unexpected server error tore the session down.
  error,
}

/// An immutable snapshot of a session's state for the UI ([PairingSender.status]).
@immutable
class PairingStatus {
  const PairingStatus({
    required this.phase,
    required this.failedAttempts,
    required this.maxFailedAttempts,
    required this.codeArmed,
  });

  final PairingPhase phase;

  /// Failed proofs counted GLOBALLY across the session (0..[maxFailedAttempts]).
  final int failedAttempts;
  final int maxFailedAttempts;

  /// True once [PairingSender.armCode] has derived the session key (the user typed
  /// the code) — so a /fetch can actually be verified rather than parked.
  final bool codeArmed;

  @override
  bool operator ==(Object other) =>
      other is PairingStatus &&
      other.phase == phase &&
      other.failedAttempts == failedAttempts &&
      other.maxFailedAttempts == maxFailedAttempts &&
      other.codeArmed == codeArmed;

  @override
  int get hashCode =>
      Object.hash(phase, failedAttempts, maxFailedAttempts, codeArmed);
}

// --- Sender ------------------------------------------------------------------

/// A live "Send to phone" session: the bound TLS server + the QR payload + the
/// authenticate-before-serve state machine. Create via [PairingSender.start],
/// drive [armCode] when the user types the phone's code, watch [status], and
/// always [dispose] (the dialog does this in its `State.dispose`).
class PairingSender {
  PairingSender._({
    required this._server,
    required this.host,
    required this.candidateHosts,
    required this._salt,
    required this.sessionId,
    required this._cert,
    required List<int> this._configBlob,
    required this.maxConnections,
    required this.maxFailedAttempts,
  }) {
    url = 'https://${host.address}:${_server.port}';
    qrPayload = encodeQrPayload(
      url: url,
      salt: _salt,
      certFingerprint: _cert.sha256Fingerprint,
    );
    _status = ValueNotifier<PairingStatus>(_snapshot());
  }

  final HttpServer _server;

  /// The interface the server is actually bound to (its IPv4 is in [url]).
  final LanHost host;

  /// All discovered private IPv4 hosts (for "on a different network?" hints). May
  /// include or omit [host] depending on how the session was started.
  final List<LanHost> candidateHosts;

  final Uint8List _salt; // zeroized on teardown
  final EphemeralCert _cert;
  List<int>?
  _configBlob; // the plaintext config bytes; zeroized+nulled on teardown

  /// The wire-safe correlation id — echoed inside TLS, NEVER the salt.
  final String sessionId;

  final int maxConnections;
  final int maxFailedAttempts;

  /// The QR-advertised base URL (`https://<ip>:<port>`) — no key, no session id.
  late final String url;

  /// The exact v3 QR string (`airclone-cfg:v3|<url>|<salt>|<fingerprint>`).
  late final String qrPayload;

  StreamSubscription<HttpRequest>? _sub;
  Timer? _ttl;

  /// Challenges issued and not yet consumed, base64-keyed. Insertion-ordered so an
  /// over-cap set evicts its OLDEST entry — this bounds memory (a flood of GETs
  /// that never fetch can't grow it without bound) without ever rejecting a
  /// /challenge (which the phone treats as a protocol failure).
  final _outstanding = <String>{};

  Uint8List? _key; // derived by armCode; zeroized on teardown
  int _failures = 0;
  bool _closed = false;

  /// Set SYNCHRONOUSLY the instant the final strike lands — BEFORE the async
  /// `_reject(429)`/`_teardown()` that follow it yield. `_teardown` guards on
  /// `_closed` (so we cannot pre-set that without turning teardown into a no-op),
  /// so this is a separate latch a concurrent /fetch re-checks after its body-read
  /// await to refuse without evaluating another proof. Without it, front-loaded
  /// parallel POSTs would each land a guess during the reject/teardown window and
  /// push the GLOBAL strike count past its hard cap.
  bool _lockedOut = false;

  /// Handlers currently in flight — the REAL concurrent-connection cap. Bumped at
  /// the top of [_handle] and dropped in its `finally`; a request that arrives once
  /// [maxConnections] are already running is refused. `backlog:4` only sizes the OS
  /// accept queue, not established sockets, so without this counter parallel /fetch
  /// is uncapped and `maxConnections` would not match its name.
  int _inFlight = 0;

  bool _disposed = false;
  PairingPhase _phase = PairingPhase.waiting;

  late final ValueNotifier<PairingStatus> _status;

  /// The live session status for the UI to watch.
  ValueListenable<PairingStatus> get status => _status;

  /// The pinned SHA-256(DER) of the session cert — also carried in the QR.
  Uint8List get certFingerprint => _cert.sha256Fingerprint;

  /// The ephemeral port the server bound to.
  int get port => _server.port;

  /// Stands up a session: pick the LAN interface, mint an ephemeral cert, and bind
  /// a TLS server on THAT interface (never 0.0.0.0) on an ephemeral port. Serves
  /// /challenge immediately; /fetch cannot succeed until [armCode] runs.
  ///
  /// [host] overrides the auto-picked interface (tests pass loopback). [configBlob]
  /// is the ALREADY-PLAINTEXT config bytes to seal + serve (the pairing seal is the
  /// transport encryption); the caller owns building it (e.g. serialized scoped
  /// INI) and must not reuse it after the session ends (it is zeroized on teardown).
  static Future<PairingSender> start({
    required List<int> configBlob,
    LanHost? host,
    Duration ttl = const Duration(minutes: 5),
    int maxConnections = 8,
    int maxFailedAttempts = 3,
    CertGenerator generateCert = generateEphemeralCert,
  }) async {
    // Enumeration is only load-bearing when the caller didn't pin a host; a rare
    // failure must not abort a session that was handed an explicit interface.
    List<LanHost> candidates;
    try {
      candidates = await discoverLanHosts();
    } catch (_) {
      candidates = const [];
    }
    final chosen = host ?? (candidates.isNotEmpty ? candidates.first : null);
    if (chosen == null) {
      throw const PairingSenderError(
        'No local network connection was found. Connect this computer to the '
        'same Wi-Fi or LAN as your phone and try again.',
      );
    }
    final cert = await generateCert();
    final salt = newSessionSalt();
    final sessionId = newSessionId();
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(cert.certPem))
      ..usePrivateKeyBytes(utf8.encode(cert.privateKeyPem));
    final HttpServer server;
    try {
      server = await HttpServer.bindSecure(
        InternetAddress(chosen.address, type: InternetAddressType.IPv4),
        0, // ephemeral port — never a fixed/known one
        context,
        backlog: 4,
        shared: false,
      );
    } catch (_) {
      throw PairingSenderError(
        'Could not open a pairing connection on ${chosen.address}. '
        'Another app may be using the network, or a firewall blocked it.',
      );
    }
    final sender = PairingSender._(
      server: server,
      host: chosen,
      candidateHosts: candidates,
      salt: salt,
      sessionId: sessionId,
      cert: cert,
      configBlob: configBlob,
      maxConnections: maxConnections,
      maxFailedAttempts: maxFailedAttempts,
    );
    sender._listen(ttl);
    return sender;
  }

  void _listen(Duration ttl) {
    _sub = _server.listen(
      (req) => unawaited(_handle(req)),
      onError: (_) {},
      cancelOnError: false,
    );
    _ttl = Timer(ttl, () {
      if (_closed) return;
      _setPhase(PairingPhase.expired);
      unawaited(_teardown());
    });
  }

  /// Arms the session key from the pairing code the user read off the phone. Runs
  /// HKDF over `salt ∥ code`; a malformed code throws [FormatException] (the dialog
  /// shows "check the code") WITHOUT changing state. Re-callable so a desktop typo
  /// can be corrected — the prior key is zeroized and replaced, and the global
  /// strike count deliberately persists (a security property, not reset by re-arm).
  Future<void> armCode(String code) async {
    if (_closed) return;
    // Derive first (may throw on a bad code) — only mutate state on success.
    final key = await deriveSessionKey(salt: _salt, code: code);
    if (_closed) {
      zeroize(key);
      return;
    }
    final old = _key;
    _key = key;
    if (old != null) zeroize(old);
    _emit();
  }

  // --- Request handling -----------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    _inFlight++;
    try {
      // Real concurrent-connection cap: refuse a request that arrives while
      // maxConnections handlers are already running. This bounds established
      // sockets (not just the OS backlog) so parallel /fetch can neither pile up
      // unbounded work nor outnumber the global strike cap.
      if (_inFlight > maxConnections) {
        await _reject(
          req,
          HttpStatus.serviceUnavailable,
          'too many connections',
        );
        return;
      }
      final remote = req.connectionInfo?.remoteAddress;
      if (remote == null || !isAllowedPairingSource(remote)) {
        await _reject(req, HttpStatus.forbidden, 'source not allowed');
        return;
      }
      if (_closed) {
        await _reject(req, HttpStatus.gone, 'session closed');
        return;
      }
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/challenge') {
        await _challenge(req);
      } else if (req.method == 'POST' && path == '/fetch') {
        await _fetch(req);
      } else {
        await _reject(req, HttpStatus.notFound, 'not found');
      }
    } catch (_) {
      // Never leak internals; best-effort error close.
      try {
        await _reject(req, HttpStatus.internalServerError, 'error');
      } catch (_) {}
    } finally {
      _inFlight--;
    }
  }

  /// GET /challenge → mint a fresh single-use challenge and return it with the
  /// wire-safe session id. Always 200 while the session is alive (the phone treats
  /// a non-200 here as a protocol failure), with the outstanding set bounded by
  /// oldest-eviction rather than rejection.
  Future<void> _challenge(HttpRequest req) async {
    final challenge = newChallenge();
    final key = base64.encode(challenge);
    _outstanding.add(key);
    while (_outstanding.length > maxConnections) {
      _outstanding.remove(_outstanding.first); // evict oldest
    }
    if (_phase == PairingPhase.waiting) {
      _setPhase(PairingPhase.phoneConnected);
    }
    await _writeJson(req, HttpStatus.ok, {
      'sessionId': sessionId,
      'challenge': key,
    });
  }

  /// POST /fetch {sessionId, challenge, proof} → the authenticate-before-serve
  /// core. Before the code is armed every attempt is a no-strike "not ready"; once
  /// armed, a valid proof for an outstanding challenge delivers the sealed blob and
  /// tears the session down (one-shot), and an invalid proof burns one global
  /// strike (the 3rd kills the session).
  Future<void> _fetch(HttpRequest req) async {
    if (req.contentLength > _maxFetchBodyBytes) {
      await _reject(req, HttpStatus.badRequest, 'bad request');
      return;
    }
    final String body;
    try {
      body = await _readCappedRequestBody(req); // drains the request (capped)
    } on _RequestBodyTooLarge {
      await _reject(req, HttpStatus.requestEntityTooLarge, 'request too large');
      return;
    }
    // Re-check state AFTER the body-read await: a concurrent /fetch may have landed
    // the final strike (or delivered + torn the session down) while we were parked
    // on the body read. The lockout latch (_lockedOut / _failures) is set
    // SYNCHRONOUSLY before that request's async _reject/_teardown yield, so anything
    // that resumes here into a locked/closed session is refused WITHOUT evaluating
    // another proof — this keeps the GLOBAL 3-strike cap hard under parallel
    // connections (they can't amplify it during the reject/teardown window).
    if (_closed || _lockedOut || _failures >= maxFailedAttempts) {
      await _reject(req, 429 /* Too Many Requests */, 'locked out');
      return;
    }
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not an object');
      }
      data = decoded;
    } catch (_) {
      await _reject(req, HttpStatus.badRequest, 'bad request');
      return;
    }
    if (data['sessionId'] != sessionId) {
      await _reject(req, HttpStatus.notFound, 'unknown session');
      return;
    }
    final challenge = _tryBase64(data['challenge']);
    final proof = _tryBase64(data['proof']);
    if (challenge == null || proof == null) {
      await _reject(req, HttpStatus.badRequest, 'bad request');
      return;
    }
    final challengeKey = base64.encode(challenge);
    final key = _key;
    // Code not typed on the desktop yet: the server literally can't verify, so it
    // parks the phone in a no-strike retry (the challenge is NOT consumed, so the
    // very next poll after the user types the code can succeed).
    if (key == null) {
      await _writeJson(req, 425 /* Too Early */, const {'status': 'pending'});
      return;
    }
    // A challenge we never issued, or one already consumed — not a fresh proof, so
    // it burns no strike; the phone GETs a new /challenge and retries.
    if (!_outstanding.contains(challengeKey)) {
      await _reject(req, HttpStatus.conflict, 'unknown or used challenge');
      return;
    }
    // Single-use: consume BEFORE verifying so a replay can't retry the same one.
    _outstanding.remove(challengeKey);
    if (verifyProof(key, challenge, proof)) {
      // Committed to deliver — stop the TTL so it can't zeroize the blob mid-seal.
      _ttl?.cancel();
      final blob = _configBlob;
      if (blob == null) {
        await _reject(req, HttpStatus.gone, 'session closed');
        return;
      }
      final sealed = await sealPairingBlob(blob, key);
      _setPhase(PairingPhase.delivered);
      await _writeJson(req, HttpStatus.ok, {'blob': base64.encode(sealed)});
      await _teardown(); // one-shot: the session dies after a successful transfer
    } else {
      _failures++;
      if (_failures >= maxFailedAttempts) {
        // Latch the lockout SYNCHRONOUSLY, before the first await below yields, so
        // a concurrent /fetch that already passed its body-read await sees the
        // session as locked at the re-check above and refuses without landing a
        // further guess. _teardown is async (and guards on _closed, which it sets
        // only after its own first await), so relying on it alone leaves a window
        // where front-loaded parallel POSTs amplify the cap past 3.
        _lockedOut = true;
        _setPhase(PairingPhase.lockedOut);
        await _reject(req, 429 /* Too Many Requests */, 'locked out');
        await _teardown();
      } else {
        _emit(); // surface the incremented strike count
        await _reject(req, HttpStatus.forbidden, 'wrong code');
      }
    }
  }

  /// Hard ceiling on the /fetch request body. The body is a tiny fixed JSON
  /// envelope (sessionId + base64 challenge + base64 proof — a few hundred bytes),
  /// so 8 KiB is already generous. Enforced on the ACTUAL bytes read, not merely
  /// the declared Content-Length: a chunked / no-Content-Length request reports
  /// contentLength == -1, slips past the length check in [_fetch], and would
  /// otherwise stream unbounded into memory (a pre-auth LAN memory-exhaustion DoS).
  static const int _maxFetchBodyBytes = 8192;

  /// Reads [req]'s body into a String, aborting the moment it exceeds
  /// [_maxFetchBodyBytes]. Unlike `utf8.decoder.bind(req).join()`, this counts
  /// bytes as they arrive, so a chunked body with no Content-Length can't buffer
  /// without bound. Throws [_RequestBodyTooLarge] once the cap is passed (the
  /// caller answers 413) rather than accumulating the whole stream.
  Future<String> _readCappedRequestBody(HttpRequest req) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > _maxFetchBodyBytes) {
        throw const _RequestBodyTooLarge();
      }
    }
    return utf8.decode(bytes);
  }

  Uint8List? _tryBase64(Object? v) {
    if (v is! String) return null;
    try {
      return Uint8List.fromList(base64.decode(v));
    } catch (_) {
      return null;
    }
  }

  Future<void> _reject(HttpRequest req, int status, String message) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.text;
    req.response.write(message);
    await req.response.close();
  }

  Future<void> _writeJson(
    HttpRequest req,
    int status,
    Map<String, Object?> body,
  ) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  // --- Lifecycle ------------------------------------------------------------

  PairingStatus _snapshot() => PairingStatus(
    phase: _phase,
    failedAttempts: _failures,
    maxFailedAttempts: maxFailedAttempts,
    codeArmed: _key != null,
  );

  void _setPhase(PairingPhase p) {
    _phase = p;
    _emit();
  }

  void _emit() {
    if (_disposed) return;
    _status.value = _snapshot();
  }

  /// Tears down the socket + timers and wipes ALL secret material. Idempotent.
  /// Zeroizing [_configBlob] also wipes the caller's plaintext config bytes — by
  /// design (the plaintext must not linger); the caller must not reuse them.
  Future<void> _teardown() async {
    if (_closed) return;
    _closed = true;
    _ttl?.cancel();
    await _sub?.cancel();
    try {
      await _server.close(force: true);
    } catch (_) {}
    zeroize(_salt);
    final key = _key;
    if (key != null) zeroize(key);
    _key = null;
    final blob = _configBlob;
    if (blob != null) zeroize(blob);
    _configBlob = null;
    _outstanding.clear();
  }

  /// Ends the session and releases the status notifier. Idempotent — safe to call
  /// multiple times; the dialog calls it from `State.dispose`.
  Future<void> dispose() async {
    if (_disposed) return;
    await _teardown();
    _disposed = true;
    _status.dispose();
  }
}

// --- Provider ----------------------------------------------------------------

/// A tiny stateless service behind a [Provider] (mirrors
/// [configTransferControllerProvider]'s shape) so the "Send to phone" dialog has a
/// single, mockable seam to discover hosts and start a session. It holds no
/// state — each [start] returns a fresh, self-owned [PairingSender].
class PairingSenderService {
  const PairingSenderService();

  /// The machine's advertisable private IPv4 hosts, best-first.
  Future<List<LanHost>> discoverHosts() => discoverLanHosts();

  /// Stands up a session serving [configBlob] (already-plaintext config bytes).
  Future<PairingSender> start({required List<int> configBlob, LanHost? host}) =>
      PairingSender.start(configBlob: configBlob, host: host);
}

final pairingSenderProvider = Provider<PairingSenderService>(
  (ref) => const PairingSenderService(),
);
