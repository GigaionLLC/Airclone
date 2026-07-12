import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' show Random;

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

// ── Multi-QR (a config too big for one QR, split across several) ──────────────
//
// The config is sealed ONCE (one Argon2id KDF, one code, one GCM tag over
// everything) and its base45 payload is split into chunk-QRs — encryption is
// per-transfer, chunking is only transport framing. Each chunk QR is:
//   AIRCLONE-CFG-Q1M:<id:4><index:2><total:2><base45-slice>
// The header after the prefix is FIXED WIDTH so a base45 slice (which reuses the
// same alphanumeric charset) is never mis-split. <id> tags one export so a
// scanner can reject a chunk from a different one; index/total are 0-based /
// count, zero-padded decimal. Everything stays in the QR-alphanumeric charset.

/// Multi-QR chunk scheme prefix (uppercase, QR-alphanumeric, `:`-terminated).
const String kOfflineQrMultiPrefix = 'AIRCLONE-CFG-Q1M:';

/// Fixed header widths after [kOfflineQrMultiPrefix]: id, index, total.
const int _qrIdLen = 4;
const int _qrNumLen = 2;
const int _qrHeaderLen = _qrIdLen + _qrNumLen + _qrNumLen; // 8

/// base45 chars carried per chunk — a modest, very reliably-scannable QR, well
/// under the single-QR ceiling ([kOfflineQrMaxPayloadChars]).
const int kOfflineQrChunkChars = 1400;

/// Hard cap on chunks — a config that would need more is refused (with
/// [OfflineQrTooLarge]) rather than asking the user to scan dozens of codes.
/// MUST stay <= 99: index/total are written as [_qrNumLen]=2 fixed digits, and
/// the parser reads them from fixed offsets — a 3-digit count would desync every
/// header. [buildOfflineQrPayloads] asserts this.
const int kMaxOfflineQrChunks = 24;

/// One parsed multi-QR chunk (its grouping [id], position, and base45 [body]).
class OfflineQrChunk {
  const OfflineQrChunk({
    required this.id,
    required this.index,
    required this.total,
    required this.body,
  });
  final String id;
  final int index;
  final int total;
  final String body;
}

/// True when [raw] is one chunk of a MULTI-QR offline config (vs the single-QR
/// [kOfflineQrPrefix] or a LAN pairing QR).
bool isOfflineQrChunk(String raw) => raw.startsWith(kOfflineQrMultiPrefix);

/// Parses a multi-QR chunk; null if it isn't a well-formed chunk (wrong scheme,
/// short header, non-numeric or out-of-range index/total, empty body).
OfflineQrChunk? parseOfflineQrChunk(String raw) {
  if (!raw.startsWith(kOfflineQrMultiPrefix)) return null;
  final rest = raw.substring(kOfflineQrMultiPrefix.length);
  if (rest.length <= _qrHeaderLen) return null;
  final id = rest.substring(0, _qrIdLen);
  final index = int.tryParse(rest.substring(_qrIdLen, _qrIdLen + _qrNumLen));
  final total = int.tryParse(
    rest.substring(_qrIdLen + _qrNumLen, _qrHeaderLen),
  );
  final body = rest.substring(_qrHeaderLen);
  if (index == null || total == null) return null;
  if (total < 1 || total > kMaxOfflineQrChunks) return null;
  if (index < 0 || index >= total) return null;
  if (body.isEmpty) return null;
  return OfflineQrChunk(id: id, index: index, total: total, body: body);
}

/// Builds the offline QR payload(s) for [configText] under [code]. Returns ONE
/// element (the classic single-QR form) when it fits, else the config sealed
/// once and split into `<total>` chunk-QRs. Throws [OfflineQrTooLarge] only when
/// it would need more than [kMaxOfflineQrChunks]. [id] is a test seam.
Future<List<String>> buildOfflineQrPayloads(
  String configText,
  String code, {
  Argon2Params? kdf,
  String? id,
}) async {
  // The 2-digit fixed-width index/total header can't encode >99 chunks.
  assert(
    kMaxOfflineQrChunks <= 99,
    'raise _qrNumLen before the chunk cap > 99',
  );
  final compressed = gzip.encode(utf8.encode(configText));
  final sealed = await sealConfigEnvelopeBytes(
    compressed,
    code,
    kdf: kdf ?? kOfflineQrSealKdf,
  );
  final body = base45Encode(sealed);
  final single = '$kOfflineQrPrefix$body';
  if (single.length <= kOfflineQrMaxPayloadChars) return [single];

  final total = (body.length / kOfflineQrChunkChars).ceil();
  if (total > kMaxOfflineQrChunks) {
    throw OfflineQrTooLarge(
      single.length,
      kMaxOfflineQrChunks * kOfflineQrChunkChars,
    );
  }
  final theId = id ?? _randomQrId();
  final out = <String>[];
  for (var i = 0; i < total; i++) {
    final start = i * kOfflineQrChunkChars;
    final end = start + kOfflineQrChunkChars;
    final slice = body.substring(start, end < body.length ? end : body.length);
    out.add(
      '$kOfflineQrMultiPrefix$theId'
      '${i.toString().padLeft(_qrNumLen, '0')}'
      '${total.toString().padLeft(_qrNumLen, '0')}'
      '$slice',
    );
  }
  return out;
}

/// Reassembles collected chunk bodies (index → base45 slice) back into the
/// single-QR payload string, ready for [openOfflineQrPayload]. Returns null
/// unless exactly [total] contiguous chunks (0..total-1) are present.
String? assembleOfflineQrPayload(Map<int, String> chunks, int total) {
  if (total < 1 || chunks.length != total) return null;
  final buf = StringBuffer(kOfflineQrPrefix);
  for (var i = 0; i < total; i++) {
    final slice = chunks[i];
    if (slice == null) return null;
    buf.write(slice);
  }
  return buf.toString();
}

String _randomQrId() {
  const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final r = Random();
  return List.generate(
    _qrIdLen,
    (_) => alphabet[r.nextInt(alphabet.length)],
  ).join();
}
