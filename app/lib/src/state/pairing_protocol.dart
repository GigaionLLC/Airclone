import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as pc;
import 'package:cryptography/cryptography.dart';

/// The PURE, network-free protocol core for the QR/LAN "Send to phone" handoff
/// (dev/plans/config-portability-plan.md §5, v3 QR-pinned-TLS). Deliberately
/// UI-free, socket-free, and TLS-free: this is only the crypto + encoding seam a
/// later agent wires to an HttpServer/scanner. Keeping it a leaf of pure
/// functions is what lets the security-critical bits — the KDF, the
/// challenge/proof, the QR framing — be exhaustively unit-tested with no engine,
/// no camera, and no network.
///
/// Security invariants baked in here (from the plan + its 2026-07-09 review):
///  - The session SALT (and anything derived from it) NEVER travels on the wire.
///    Correlation between the two channels uses a SEPARATE random [newSessionId],
///    which is the only token safe to echo.
///  - The pairing CODE is short and human, so the whole scheme leans on the
///    QR-pinned TLS channel: without the wire being confidential a QR photo
///    (salt) + a cleartext transcript would be an offline brute-force oracle on
///    the code. This layer therefore never puts the code, the salt, a proof, or a
///    derived key anywhere they could be logged.
///  - Proofs are compared in CONSTANT TIME ([constantTimeBytesEqual]); a naive
///    early-return compare would leak the HMAC byte-by-byte.
///  - Codes/salts/keys are per-session and must never be persisted or logged;
///    callers should [zeroize] the mutable byte material as soon as a session
///    ends (Dart strings are immutable and cannot be wiped — keep code strings
///    short-lived instead).
///
/// The wider protocol (who counts failed proofs, the 3-strikes-per-SESSION cap,
/// the one-shot server, the interface binding) lives in the server/scanner layer
/// that consumes this file; the primitives here are what that layer is built on.

// --- Alphabets ---------------------------------------------------------------

/// Crockford's base32 symbol alphabet (encode side): the digits plus the
/// uppercase letters with the four ambiguous ones removed — `I`, `L`, `O`, `U`.
/// `I`/`L` collide with `1`, `O` with `0`, and `U` is dropped to avoid accidental
/// obscenities. Exactly 32 symbols, so one symbol carries 5 bits.
const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// RFC 9285 base45 alphabet, in value order (index == symbol value). Chosen for
/// the QR fields because it maps cleanly onto QR "alphanumeric" mode — every one
/// of these 45 symbols is directly representable there — so a base45 field is
/// materially denser in a QR than base64 would be. The `$` is escaped for Dart;
/// the space at index 36 is a literal space (a valid QR alphanumeric symbol).
const String _base45 = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

/// Reverse lookup for base45 decode: symbol code-unit -> value. Built once so
/// [base45Decode] is a table lookup rather than an `indexOf` scan per char.
final Map<int, int> _base45Decode = {
  for (var i = 0; i < _base45.length; i++) _base45.codeUnitAt(i): i,
};

/// The fixed HKDF `info` binding the derived key to THIS protocol + version, so a
/// key derived here can never be confused with one from another Airclone feature
/// (domain separation). Bumped in lockstep with the QR scheme version (`v3`).
final List<int> _kPairingInfo = utf8.encode('airclone-pairing-v3');

/// The exact QR scheme prefix. A parsed payload MUST match this verbatim — a `v2`
/// (keyed) QR or any other scheme is refused, never best-effort parsed.
const String _kQrPrefix = 'airclone-cfg:v3';

/// Wire lengths the QR framing pins: a 128-bit session salt and a SHA-256 cert
/// fingerprint. Enforced on both encode and decode so a truncated/overlong field
/// can never be silently accepted.
const int _kSaltLength = 16;
const int _kFingerprintLength = 32;

/// AES-GCM standard nonce (96-bit) and tag (128-bit) sizes, used to frame a
/// sealed blob as `nonce ∥ ciphertext ∥ mac`.
const int _kNonceLength = 12;
const int _kMacLength = 16;

/// Derived AES-256 session key length.
const int _kKeyLength = 32;

// --- Randomness --------------------------------------------------------------

/// The one CSPRNG for every secret this file mints (salt, session id, code,
/// challenge). `Random.secure()` is mandatory — a predictable PRNG here would let
/// an attacker guess the code/salt/challenge and defeat the whole handoff.
final Random _rng = Random.secure();

Uint8List _randomBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rng.nextInt(256);
  }
  return b;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// --- Session material (plan §5, steps 1–2) -----------------------------------

/// A fresh 128-bit session salt. Rides in the QR ([encodeQrPayload]) and feeds
/// the KDF ([deriveSessionKey]) alongside the code — but is NEVER echoed on the
/// wire itself: correlation uses [newSessionId], not this. Random per session.
Uint8List newSessionSalt() => _randomBytes(_kSaltLength);

/// A short random correlation id — the ONLY token safe to send in the clear to
/// match a connection to a session. Deliberately DISTINCT from (and independent
/// of) the salt, so leaking the id on the wire tells an attacker nothing about
/// the salt or the derived key. 64 bits of hex is ample to make collisions and
/// guessing a non-issue for a 5-minute one-shot session.
String newSessionId() => _hex(_randomBytes(8));

/// A fresh 8-symbol Crockford-base32 pairing code, returned in the grouped
/// `XXXX-XXXX` display form the phone shows and the user re-types on the desktop
/// (e.g. `K7WX-4PMB`). 8 symbols ≈ 40 bits of entropy — the plan's ≥8-char floor.
/// Feed it straight back through [deriveSessionKey]/[normalizePairingCode]; the
/// grouping dash is stripped there.
String newPairingCode() {
  final symbols = List<String>.generate(
    8,
    (_) => _crockford[_rng.nextInt(_crockford.length)],
  );
  return formatPairingCode(symbols.join());
}

/// Groups a pairing code into dash-separated blocks of four for display
/// (`K7WX4PMB` -> `K7WX-4PMB`). Idempotent-ish: any dashes/spaces already present
/// are normalised out first, so re-formatting a formatted code is stable. Purely
/// cosmetic — [normalizePairingCode] undoes it before any key derivation.
String formatPairingCode(String code) {
  final canonical = code.replaceAll('-', '').replaceAll(' ', '');
  final groups = <String>[];
  for (var i = 0; i < canonical.length; i += 4) {
    groups.add(canonical.substring(i, min(i + 4, canonical.length)));
  }
  return groups.join('-');
}

/// Canonicalises a user-typed pairing code to the exact string both sides hash,
/// applying Crockford's DECODE-side normalisation precisely:
///  - grouping dashes and spaces are stripped;
///  - letters are upper-cased;
///  - the ambiguous inputs are folded to their canonical symbol — `O`/`o` -> `0`,
///    `I`/`i`/`L`/`l` -> `1` (Crockford maps the letters TO the digits, never the
///    reverse: `0` stays `0`, it does not become `O`);
///  - any remaining character outside the Crockford alphabet (including `U`, which
///    Crockford excludes entirely) is REJECTED with a [FormatException] rather
///    than silently dropped — a mistyped code must fail loudly, not derive a
///    different key.
///
/// The result is the undashed, upper-case canonical form (its length is whatever
/// the input carried; [newPairingCode] mints 8). Throws on an empty result.
String normalizePairingCode(String input) {
  final buf = StringBuffer();
  for (final rune in input.runes) {
    var ch = String.fromCharCode(rune);
    if (ch == '-' || ch == ' ') continue; // grouping separators
    ch = ch.toUpperCase();
    // Crockford decode aliases. Order doesn't matter — these inputs are distinct.
    if (ch == 'O') {
      ch = '0';
    } else if (ch == 'I' || ch == 'L') {
      ch = '1';
    }
    if (!_crockford.contains(ch)) {
      throw FormatException('invalid pairing-code character: "$ch"', input);
    }
    buf.write(ch);
  }
  final canonical = buf.toString();
  if (canonical.isEmpty) {
    throw const FormatException('empty pairing code');
  }
  return canonical;
}

// --- Key derivation & blob sealing (plan §5, steps 3–4) ----------------------

final AesGcm _aes = AesGcm.with256bits();

/// Thrown by [openPairingBlob] when the GCM tag fails to verify — i.e. the key is
/// wrong (a mistyped code derives a different key) or the ciphertext/nonce/tag was
/// tampered with. Indistinguishable by design (authenticated encryption), so a
/// single typed error covers both; the caller reports "couldn't decrypt — check
/// the code" rather than leaking which.
class WrongPairingKey implements Exception {
  const WrongPairingKey([this.message = 'wrong pairing key']);
  final String message;
  @override
  String toString() => 'WrongPairingKey: $message';
}

/// Thrown by [openPairingBlob] when the bytes are not even a well-formed sealed
/// blob (too short to hold a nonce + tag, malformed framing). Distinct from
/// [WrongPairingKey] so the UI can tell "this isn't an Airclone transfer" apart
/// from "the code is wrong".
class CorruptPairingBlob implements Exception {
  const CorruptPairingBlob([this.message = 'corrupt pairing blob']);
  final String message;
  @override
  String toString() => 'CorruptPairingBlob: $message';
}

/// Derives the 32-byte AES-256 session key both sides agree on, via
/// `HKDF-HMAC-SHA256` over `salt ∥ utf8(normalizedCode)` with the fixed
/// [_kPairingInfo] (`airclone-pairing-v3`) as HKDF `info`. The code is run through
/// [normalizePairingCode] first, so a dashed/mixed-case/ambiguous-char rendering
/// of the same code derives the same key (and an invalid code throws before any
/// crypto). Deterministic: identical `salt`+`code` always yield the identical key,
/// and any change to either yields a different key — which is exactly what makes a
/// wrong code fail to open the blob.
///
/// Note on strength: HKDF is a fast KDF, appropriate here ONLY because the wire is
/// the QR-pinned TLS channel (a sniffer sees nothing to brute-force). The plan is
/// explicit that if that channel is ever dropped, this MUST be swapped for
/// Argon2id over the same input — HKDF alone would not resist an offline attack on
/// the short code.
Future<Uint8List> deriveSessionKey({
  required List<int> salt,
  required String code,
}) async {
  final normalized = normalizePairingCode(code);
  final ikm = <int>[...salt, ...utf8.encode(normalized)];
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _kKeyLength);
  final derived = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    info: _kPairingInfo,
  );
  final bytes = await derived.extractBytes();
  return Uint8List.fromList(bytes);
}

/// Seals [plaintext] (the config blob that will be served) under [key] with
/// AES-256-GCM and a FRESH random 96-bit nonce, returning `nonce ∥ ciphertext ∥
/// mac`. Because the nonce is random per call, sealing the same plaintext twice
/// yields different bytes — never a reused nonce for the same key.
Future<Uint8List> sealPairingBlob(List<int> plaintext, List<int> key) async {
  final box = await _aes.encrypt(plaintext, secretKey: SecretKey(key));
  return Uint8List.fromList(box.concatenation()); // nonce | ciphertext | mac
}

/// Opens a blob produced by [sealPairingBlob] under [key], returning the raw
/// plaintext bytes. Throws [CorruptPairingBlob] when [bytes] can't even be framed
/// as `nonce ∥ ct ∥ mac` (too short / malformed) and [WrongPairingKey] when the
/// authentication tag fails (wrong key or tampered bytes). Returns raw bytes, not
/// a decoded String — the config blob is handed on verbatim to the import wizard.
Future<Uint8List> openPairingBlob(List<int> bytes, List<int> key) async {
  SecretBox box;
  try {
    box = SecretBox.fromConcatenation(
      bytes,
      nonceLength: _kNonceLength,
      macLength: _kMacLength,
    );
  } catch (_) {
    throw const CorruptPairingBlob('blob is too short or malformed');
  }
  try {
    final clear = await _aes.decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw const WrongPairingKey();
  }
}

// --- Challenge / proof: authenticate-before-serve (plan §5, step 5) ----------

/// A fresh 256-bit challenge, minted PER CONNECTION by the server. The connection
/// must answer its OWN challenge (via [proofFor]) before the ciphertext is
/// served — there are no bearer tokens and no global "released" flag, so an
/// attacker can't ride a legitimate proof. Random and single-use.
Uint8List newChallenge() => _randomBytes(32);

/// The proof for [challenge] under the session [key]: `HMAC-SHA256(key,
/// challenge)`, 32 bytes. Deterministic (same challenge+key -> same proof), so the
/// server recomputes the expected value and compares. Uses `package:crypto`'s
/// synchronous HMAC so proving/verifying stays allocation-light and easy to reason
/// about; the key here is the [deriveSessionKey] output, never the raw code.
Uint8List proofFor(List<int> challenge, List<int> key) {
  final mac = pc.Hmac(pc.sha256, key);
  return Uint8List.fromList(mac.convert(challenge).bytes);
}

/// Verifies a [presentedProof] for [challenge] against the locally-known
/// [expectedKey]: recompute the expected proof and compare in CONSTANT TIME. The
/// comparison never early-returns on the first differing byte, so it leaks no
/// timing signal about how much of the proof was correct — the difference between
/// this and a naive `==` is the whole point of a challenge/proof handshake. A
/// wrong key, a wrong challenge, or a truncated proof all return false; the caller
/// counts those failures GLOBALLY per session (3 kills it).
bool verifyProof(
  List<int> expectedKey,
  List<int> challenge,
  List<int> presentedProof,
) {
  final expected = proofFor(challenge, expectedKey);
  return constantTimeBytesEqual(expected, presentedProof);
}

/// Constant-time byte-sequence equality. Folds a length mismatch into the
/// accumulator (so unequal lengths return false) and ALWAYS walks the full
/// overlap without short-circuiting, so its running time depends only on the
/// input lengths, not on how many bytes match. This is the equality used for every
/// MAC/proof comparison in the handoff; a plain `==`/`listEquals` here would be a
/// timing oracle on the secret.
bool constantTimeBytesEqual(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

// --- QR payload framing (plan §5, step 4) ------------------------------------

/// A parsed, VALIDATED QR payload. A record (not a class) because it is a plain
/// immutable tuple the scanner destructures immediately; every field has already
/// passed [parseQrPayload]'s checks, so the salt is exactly 16 bytes and the
/// fingerprint exactly 32.
typedef ParsedQrPayload = ({
  String url,
  Uint8List salt,
  Uint8List certFingerprint,
});

/// Thrown by [parseQrPayload] for any SEMANTIC rejection — wrong scheme/version, a
/// non-private URL host, or a salt/fingerprint of the wrong length. Typed (and
/// distinct from the [FormatException] a malformed base45 field raises) so the UI
/// can be honest about WHY a scan was refused (a swapped/public-host QR reads as
/// tampering, not a scanner glitch).
class QrPayloadError implements Exception {
  const QrPayloadError(this.message);
  final String message;
  @override
  String toString() => 'QrPayloadError: $message';
}

/// Renders the exact v3 QR string:
///
///   `airclone-cfg:v3|<url>|<base45 salt>|<base45 certFingerprint>`
///
/// The QR carries NO key and NO payload — only the LAN URL, the session salt, and
/// the pinned-TLS cert fingerprint. [salt] must be 16 bytes and [certFingerprint]
/// 32 (a SHA-256 digest); an out-of-spec length is an [ArgumentError] here so a
/// malformed QR can never be emitted in the first place.
String encodeQrPayload({
  required String url,
  required List<int> salt,
  required List<int> certFingerprint,
}) {
  if (salt.length != _kSaltLength) {
    throw ArgumentError.value(salt.length, 'salt.length', 'must be 16 bytes');
  }
  if (certFingerprint.length != _kFingerprintLength) {
    throw ArgumentError.value(
      certFingerprint.length,
      'certFingerprint.length',
      'must be 32 bytes (SHA-256)',
    );
  }
  return '$_kQrPrefix|$url|${base45Encode(salt)}|'
      '${base45Encode(certFingerprint)}';
}

/// Parses and VALIDATES a scanned QR string back into a [ParsedQrPayload], or
/// throws. The checks are the phone-side half of the two-channel security model,
/// so each is strict:
///  - the scheme/version prefix must equal `airclone-cfg:v3` exactly (a `v2` or
///    unknown QR is refused, not coerced);
///  - the URL must parse to an `https` origin whose host is a PRIVATE or
///    link-local IPv4 literal (`10.`/`172.16–31.`/`192.168.`/`169.254.`/`127.`) —
///    a public host, a bare hostname, or a non-TLS scheme is rejected so an
///    overlay QR can't point the phone at an attacker's server;
///  - the salt must decode to exactly 16 bytes and the fingerprint to exactly 32.
/// A field that isn't valid base45 raises the underlying [FormatException]; every
/// semantic failure raises [QrPayloadError].
ParsedQrPayload parseQrPayload(String payload) {
  final parts = payload.split('|');
  if (parts.length != 4) {
    throw const QrPayloadError('not a v3 Airclone transfer QR');
  }
  if (parts[0] != _kQrPrefix) {
    throw QrPayloadError('unsupported QR scheme/version: "${parts[0]}"');
  }
  final url = parts[1];
  _requirePrivateHttpsUrl(url);
  final salt = base45Decode(parts[2]);
  if (salt.length != _kSaltLength) {
    throw QrPayloadError('salt is ${salt.length} bytes, expected 16');
  }
  final fp = base45Decode(parts[3]);
  if (fp.length != _kFingerprintLength) {
    throw QrPayloadError('fingerprint is ${fp.length} bytes, expected 32');
  }
  return (url: url, salt: salt, certFingerprint: fp);
}

/// Enforces that [url] is an `https` origin bound to a private/link-local IPv4
/// host. Throws [QrPayloadError] otherwise. The scheme is pinned to `https`
/// because the v3 design is TLS-pinned (the fingerprint field only makes sense
/// over TLS); the host is pinned to the private ranges because a QR must never be
/// able to steer the phone onto a routable/public address.
void _requirePrivateHttpsUrl(String url) {
  Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    throw const QrPayloadError('malformed transfer URL');
  }
  if (uri.scheme != 'https') {
    throw QrPayloadError('transfer URL must be https, got "${uri.scheme}"');
  }
  final host = uri.host;
  if (host.isEmpty || !_isPrivateIpv4(host)) {
    throw QrPayloadError('transfer URL host "$host" is not a private address');
  }
}

/// True when [host] is a dotted-quad IPv4 literal in a private or link-local
/// range: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`
/// (link-local), or `127.0.0.0/8` (loopback). Anything else — a public IPv4, a
/// hostname (which can't be proven private without a network lookup this pure
/// layer won't do), or an IPv6 literal — is not private here and is rejected by
/// the caller.
bool _isPrivateIpv4(String host) {
  final octets = host.split('.');
  if (octets.length != 4) return false;
  final parts = <int>[];
  for (final o in octets) {
    // Reject empty / non-decimal / out-of-range / non-canonical octets. A leading
    // '+' or whitespace is refused (int.parse would otherwise be lenient about
    // some of these); we require pure digits in 0..255.
    if (o.isEmpty || o.length > 3) return false;
    // Reject a leading-zero octet (e.g. `010`): it's octal-ambiguous, and a
    // validator/OS-resolver differential on `010.0.0.1` could let a public host
    // masquerade as private. Canonical decimal only.
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

// --- base45 (RFC 9285) -------------------------------------------------------

/// Encodes [input] bytes to a base45 string (RFC 9285). Two input bytes become a
/// 16-bit value written as THREE base45 symbols (least-significant symbol first);
/// a trailing odd byte becomes TWO symbols. Pure inverse of [base45Decode].
String base45Encode(List<int> input) {
  final out = StringBuffer();
  var i = 0;
  // Whole 2-byte groups -> 3 symbols each.
  for (; i + 1 < input.length; i += 2) {
    final x = (input[i] << 8) + input[i + 1]; // 0..65535
    final c = x % 45;
    final d = (x ~/ 45) % 45;
    final e = x ~/ (45 * 45);
    out
      ..write(_base45[c])
      ..write(_base45[d])
      ..write(_base45[e]);
  }
  // A single trailing byte -> 2 symbols.
  if (i < input.length) {
    final x = input[i]; // 0..255
    final c = x % 45;
    final d = x ~/ 45;
    out
      ..write(_base45[c])
      ..write(_base45[d]);
  }
  return out.toString();
}

/// Decodes a base45 string ([input]) back to bytes (RFC 9285), the exact inverse
/// of [base45Encode]. Throws [FormatException] on:
///  - any symbol outside the RFC 9285 alphabet;
///  - a length that is `≡ 1 (mod 3)` (a lone trailing symbol can't encode a byte);
///  - a 3-symbol group whose value exceeds `0xFFFF`, or a 2-symbol tail whose
///    value exceeds `0xFF` (an overlong, non-canonical encoding).
Uint8List base45Decode(String input) {
  final vals = <int>[];
  for (final unit in input.codeUnits) {
    final v = _base45Decode[unit];
    if (v == null) {
      throw FormatException('invalid base45 character', input);
    }
    vals.add(v);
  }
  final remainder = vals.length % 3;
  if (remainder == 1) {
    throw FormatException('invalid base45 length (${vals.length})', input);
  }
  final out = <int>[];
  var i = 0;
  for (; i + 3 <= vals.length; i += 3) {
    final x = vals[i] + vals[i + 1] * 45 + vals[i + 2] * 45 * 45;
    if (x > 0xFFFF) {
      throw FormatException('base45 group out of range', input);
    }
    out.add((x >> 8) & 0xFF);
    out.add(x & 0xFF);
  }
  if (remainder == 2) {
    final x = vals[i] + vals[i + 1] * 45;
    if (x > 0xFF) {
      throw FormatException('base45 tail out of range', input);
    }
    out.add(x);
  }
  return Uint8List.fromList(out);
}

// --- Hygiene -----------------------------------------------------------------

/// Best-effort wipe of mutable secret bytes (a derived key, salt, challenge, or
/// proof) once a session ends. Overwrites every element with zero in place, so a
/// later heap inspection can't recover it. Only works on growable/fixed byte lists
/// (a `Uint8List` or a mutable `List<int>`); an unmodifiable list is left as-is.
/// Note the hard limit: the pairing CODE is a Dart String and is immutable — it
/// cannot be zeroized, so callers keep code strings as short-lived as possible.
void zeroize(List<int> bytes) {
  try {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  } catch (_) {
    // An unmodifiable list — nothing we can wipe; ignore.
  }
}
