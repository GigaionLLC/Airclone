/// Verifying a minisign signature, in Dart.
///
/// Airclone can only offer to install a build it downloaded if it can prove the
/// build is the one this project released. On Windows and macOS the operating
/// system has an opinion about that - Authenticode, Developer ID - but Linux has
/// nothing of the kind, and neither has a plain `.zip`. A signature over the
/// release's checksum manifest is what covers every package equally.
///
/// minisign because it is small enough to implement correctly here: an Ed25519
/// signature, a two-byte algorithm tag and an eight-byte key id, in four lines
/// of text. No key servers, no web of trust, no ASN.1.
///
///     untrusted comment: <anything at all, NOT covered by a signature>
///     base64( "ED" | key id (8) | signature (64) )
///     trusted comment: <text, covered by the global signature>
///     base64( global signature (64) )
///
/// TWO signatures, and both matter. The first covers the payload. The second
/// covers `signature | trusted comment`, which is what makes the trusted comment
/// worth its name - and it is where the release tag goes, so a genuine but OLD
/// manifest replayed by a stale mirror can be refused by a client that knows
/// which version it is looking for. A verifier that skipped the global signature
/// would accept an attacker's comment on a real signature.
///
/// `ED` is the prehashed variant (BLAKE2b-512 of the payload, then Ed25519) and
/// is what minisign has written by default since 0.10. `Ed` signs the payload
/// directly; it is accepted for small files like the manifest, because refusing
/// it would only mean a release signed with an old minisign could not be checked
/// at all.
///
/// EVERY failure is a refusal, never an exception escaping to a caller: a
/// verifier that throws on a malformed signature is a verifier that someone
/// wraps in a `catch` and turns into a pass.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show immutable;

/// Why a signature was refused. The reason is for the log and for a maintainer;
/// the UI says one thing whatever the reason, because to a user they all mean
/// "this download cannot be trusted".
enum MinisignRefusal {
  /// Not four lines, or a line is not where the format says it is.
  malformed,

  /// The base64 did not decode, or decoded to the wrong number of bytes.
  badEncoding,

  /// An algorithm this build does not implement.
  unknownAlgorithm,

  /// Signed by a key this build does not trust.
  wrongKey,

  /// The signature does not match the payload.
  payloadMismatch,

  /// The payload signature is good but the trusted comment is not covered by
  /// the global signature - so the comment was altered after signing.
  commentMismatch,
}

/// A public key, as it appears on line 2 of a `.pub` file.
@immutable
class MinisignPublicKey {
  const MinisignPublicKey({required this.keyId, required this.bytes});

  /// The 8-byte key id, which must match the signature's.
  final Uint8List keyId;

  /// The 32-byte Ed25519 public key.
  final Uint8List bytes;

  /// Parses the base64 line. Returns null rather than throwing: a build
  /// configured with a malformed key must refuse updates, not crash at startup.
  static MinisignPublicKey? parse(String base64Line) {
    final raw = _decode(base64Line.trim());
    if (raw == null || raw.length != 42) return null;
    if (raw[0] != 0x45 || raw[1] != 0x64) return null; // "Ed"
    return MinisignPublicKey(
      keyId: Uint8List.sublistView(raw, 2, 10),
      bytes: Uint8List.sublistView(raw, 10, 42),
    );
  }
}

/// A parsed signature file.
@immutable
class MinisignSignature {
  const MinisignSignature({
    required this.prehashed,
    required this.keyId,
    required this.signature,
    required this.trustedComment,
    required this.globalSignature,
  });

  /// True for `ED` (BLAKE2b-512 first), false for `Ed` (sign the payload).
  final bool prehashed;
  final Uint8List keyId;
  final Uint8List signature;

  /// The text after `trusted comment: `, which the global signature covers.
  final String trustedComment;
  final Uint8List globalSignature;
}

/// The outcome of [verifyMinisign]: either a trusted comment, or a reason.
@immutable
class MinisignResult {
  const MinisignResult.trusted(this.trustedComment) : refusal = null;
  const MinisignResult.refused(this.refusal) : trustedComment = null;

  /// Null when refused.
  final String? trustedComment;

  /// Null when trusted.
  final MinisignRefusal? refusal;

  bool get ok => refusal == null;
}

/// Parses a signature file. Null means it was not a signature file.
MinisignSignature? parseMinisignSignature(String text) {
  final lines = const LineSplitter().convert(text);
  // Trailing blank lines are ordinary in a file a shell wrote.
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  if (lines.length != 4) return null;
  if (!lines[0].startsWith('untrusted comment:')) return null;
  if (!lines[2].startsWith('trusted comment:')) return null;

  final sig = _decode(lines[1].trim());
  if (sig == null || sig.length != 74) return null;
  final alg = String.fromCharCodes(sig.sublist(0, 2));
  final prehashed = alg == 'ED';
  if (!prehashed && alg != 'Ed') return null;

  final global = _decode(lines[3].trim());
  if (global == null || global.length != 64) return null;

  return MinisignSignature(
    prehashed: prehashed,
    keyId: Uint8List.sublistView(sig, 2, 10),
    signature: Uint8List.sublistView(sig, 10, 74),
    trustedComment: lines[2].substring('trusted comment:'.length).trim(),
    globalSignature: global,
  );
}

/// Verifies [payload] against [signatureText], which must be signed by one of
/// [trusted].
///
/// [trusted] takes more than one key so a key can be ROTATED: during the
/// changeover a release is signed by both, and a client that knows either can
/// still update. An empty list refuses everything, which is the right behaviour
/// for a fork that has not set a key of its own.
Future<MinisignResult> verifyMinisign({
  required List<int> payload,
  required String signatureText,
  required List<MinisignPublicKey> trusted,
}) async {
  final sig = parseMinisignSignature(signatureText);
  if (sig == null) {
    return const MinisignResult.refused(MinisignRefusal.malformed);
  }

  final key = trusted.where((k) => _sameBytes(k.keyId, sig.keyId)).firstOrNull;
  if (key == null) {
    return const MinisignResult.refused(MinisignRefusal.wrongKey);
  }

  final signed = sig.prehashed
      ? await _blake2b512(payload)
      : Uint8List.fromList(payload);

  if (!await _ed25519Verify(signed, sig.signature, key.bytes)) {
    return const MinisignResult.refused(MinisignRefusal.payloadMismatch);
  }

  // The global signature covers signature | trusted comment. Without this check
  // the comment is attacker-controlled text on a genuine signature, and the
  // version binding built on top of it would be worthless.
  final globalPayload = Uint8List.fromList([
    ...sig.signature,
    ...utf8.encode(sig.trustedComment),
  ]);
  if (!await _ed25519Verify(globalPayload, sig.globalSignature, key.bytes)) {
    return const MinisignResult.refused(MinisignRefusal.commentMismatch);
  }
  return MinisignResult.trusted(sig.trustedComment);
}

/// `Ed25519.verify` THROWS on a wrong-length key or signature instead of
/// returning false, so every call goes through here: a malformed input is a
/// refusal like any other, and a refusal must never look like an error the
/// caller can shrug off.
Future<bool> _ed25519Verify(
  List<int> message,
  List<int> signature,
  List<int> publicKey,
) async {
  try {
    return await Ed25519().verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

Future<Uint8List> _blake2b512(List<int> data) async {
  final hash = await Blake2b(hashLengthInBytes: 64).hash(data);
  return Uint8List.fromList(hash.bytes);
}

Uint8List? _decode(String s) {
  try {
    return base64.decode(s);
  } catch (_) {
    return null;
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
