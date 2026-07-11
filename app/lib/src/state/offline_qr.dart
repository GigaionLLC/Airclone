import 'dart:convert';
import 'dart:io' show gzip;

import 'config_io.dart'
    show
        Argon2Params,
        CorruptEnvelope,
        openConfigEnvelopeBytes,
        sealConfigEnvelopeBytes;
import 'pairing_protocol.dart' show base45Decode, base45Encode;

/// The OFFLINE, self-contained config QR (dev/plans/config-portability-plan.md §5,
/// user-requested 2026-07). Unlike the LAN pairing QR (`airclone-cfg:v3|url|salt|
/// fp`, which only carries a URL the phone fetches the config from over Wi-Fi),
/// this QR carries the WHOLE config, gzip-compressed then sealed with the existing
/// AES-256-GCM-over-Argon2id export envelope ([sealConfigEnvelopeBytes]). The
/// unlock CODE never travels in the QR — it is entered out-of-band on both sides,
/// so a thief needs BOTH the QR photo AND the code. Because a static QR is an
/// offline artifact, the memory-hard Argon2id KDF (not the LAN path's fast HKDF)
/// is what makes brute-forcing the code from a photographed QR costly.
///
/// Layout: `AIRCLONE-CFG-Q1:<base45( ACFG2-envelope( gzip(configText), code ) )>`.
/// The envelope is byte-for-byte the same format the file/Send-to-phone export
/// uses, so its versioned header, typed errors, and crypto are all reused.
///
/// The prefix and separator are deliberately kept inside the QR "alphanumeric"
/// charset (0-9 A-Z space $%*+-./:) — the SAME 45 symbols base45 uses — so the
/// entire payload encodes in QR alphanumeric mode (~5.5 bits/char) rather than
/// falling back to byte mode (8 bits/char) which a lowercase prefix or a `|`
/// separator would force, inflating the QR by ~45%. The payload is parsed by the
/// fixed prefix LENGTH (not by searching for a separator), so a `:` inside the
/// base45 body is never ambiguous.

/// Scheme prefix (uppercase, QR-alphanumeric, `:`-terminated) — a parsed payload
/// must start with this verbatim (a v3 LAN QR or any other scheme is refused).
const String kOfflineQrPrefix = 'AIRCLONE-CFG-Q1:';

/// The largest base45 payload we will emit. base45 is ~1.5x the sealed byte
/// length; ~1900 chars is roughly a version-33 QR at medium error correction —
/// still reliably scannable off a screen when shown large. A config that exceeds
/// this can't fit one offline QR (send fewer remotes, or use the Wi-Fi path).
const int kOfflineQrMaxPayloadChars = 1900;

/// The Argon2id memory ceiling accepted when OPENING a scanned QR — an untrusted
/// artifact. Refuses a hostile QR that sets a device-OOMing cost while accepting
/// what we seal at ([kOfflineQrSealKdf], 128 MiB).
const int kMaxOfflineQrArgon2MemoryKiB = 131072; // 128 MiB

/// The Argon2id band the offline QR SEALS at — HEAVIER than the file export's
/// 64 MiB. A photographed QR is a static offline brute-force oracle (it embeds the
/// salt + ciphertext, with no expiry, rate limit, or server), so each guess must
/// cost more. 128 MiB is the max the open path accepts; the ACFG2 header is
/// self-describing, so raising this never breaks an older reader.
const Argon2Params kOfflineQrSealKdf = Argon2Params(
  memory: 131072, // 128 MiB
  iterations: 3,
  parallelism: 1,
);

/// Thrown by [buildOfflineQrPayload] when the sealed config is too large for a
/// single scannable QR. Carries the sizes so the UI can say by how much.
class OfflineQrTooLarge implements Exception {
  const OfflineQrTooLarge(this.payloadChars, this.limit);
  final int payloadChars;
  final int limit;
  @override
  String toString() => 'OfflineQrTooLarge($payloadChars > $limit chars)';
}

/// Thrown by [openOfflineQrPayload] when the scanned string isn't an offline
/// Airclone config QR at all (wrong/absent scheme) — distinct from a wrong code
/// ([WrongPassphrase]) or a malformed envelope ([CorruptEnvelope]) so the scanner
/// can tell "that's not the right QR" from "wrong code".
class NotAnOfflineQr implements Exception {
  const NotAnOfflineQr([this.message = 'not an offline Airclone config QR']);
  final String message;
  @override
  String toString() => 'NotAnOfflineQr: $message';
}

/// Cheap prefix check for scan routing — true when [raw] looks like an offline
/// config QR (so the scanner branches to the code-prompt flow instead of the LAN
/// pairing flow). Full validation happens in [openOfflineQrPayload].
bool isOfflineQrPayload(String raw) => raw.startsWith(kOfflineQrPrefix);

/// Builds the offline QR payload for [configText] under [code]:
/// `gzip(configText)` → [sealConfigEnvelopeBytes] → [base45Encode] → prefixed.
/// [kdf] overrides the Argon2id cost (tests seal cheaply). Throws
/// [OfflineQrTooLarge] when the result won't fit one scannable QR.
Future<String> buildOfflineQrPayload(
  String configText,
  String code, {
  Argon2Params? kdf,
}) async {
  final compressed = gzip.encode(utf8.encode(configText));
  // Seal at the heavier QR band by default; [kdf] override lets tests seal cheaply.
  final sealed = await sealConfigEnvelopeBytes(
    compressed,
    code,
    kdf: kdf ?? kOfflineQrSealKdf,
  );
  final payload = '$kOfflineQrPrefix${base45Encode(sealed)}';
  if (payload.length > kOfflineQrMaxPayloadChars) {
    throw OfflineQrTooLarge(payload.length, kOfflineQrMaxPayloadChars);
  }
  return payload;
}

/// Parses + decrypts an offline QR [payload] under [code], returning the config
/// text. Throws [NotAnOfflineQr] (wrong scheme), [WrongPassphrase] (wrong code or
/// tampered bytes), [CorruptEnvelope] (malformed envelope / bad gzip / non-UTF-8),
/// or [FormatException] (invalid base45).
Future<String> openOfflineQrPayload(String payload, String code) async {
  if (!payload.startsWith(kOfflineQrPrefix)) {
    throw const NotAnOfflineQr();
  }
  // Parse by the fixed prefix LENGTH — a `:` inside the base45 body is not a
  // delimiter, so there is nothing to mis-split.
  final sealed = base45Decode(payload.substring(kOfflineQrPrefix.length));
  // openConfigEnvelopeBytes throws WrongPassphrase / CorruptEnvelope. Cap the
  // Argon2id cost the (untrusted) QR can demand so it can't OOM the scanner.
  final compressed = await openConfigEnvelopeBytes(
    sealed,
    code,
    maxMemoryKiB: kMaxOfflineQrArgon2MemoryKiB,
  );
  final List<int> clear;
  try {
    clear = gzip.decode(compressed);
  } catch (_) {
    // Authenticated bytes that don't gunzip means a format we didn't write.
    throw const CorruptEnvelope('offline QR payload could not be decompressed');
  }
  try {
    return utf8.decode(clear);
  } on FormatException {
    throw const CorruptEnvelope('offline QR content is not valid UTF-8');
  }
}
