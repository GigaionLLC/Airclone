import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Pure, injectable config-portability I/O — the shared seam under the
/// import/export wizards (dev/plans/config-portability-plan.md §3/§4) and the
/// QR/LAN handoff. Deliberately UI-free and side-effect-free: format sniffing,
/// INI/JSON <-> model conversion, the encrypted-export envelope, dependency
/// closure, and merge planning all live here so they can be exhaustively
/// unit-tested and reused by every source (file picker, QR, LAN) without
/// dragging in a widget or a running engine.
///
/// A parsed config is modelled as [ConfigModel]: remote name -> (key -> value),
/// insertion-ordered so a round-trip preserves file order.

/// A parsed rclone config: remote name -> (key -> value). A plain [Map] (not a
/// bespoke class) because that is exactly the shape `rclone config dump` and an
/// INI file describe, and callers routinely mutate a working copy before an
/// import. Insertion order is preserved (Dart's default `LinkedHashMap`), so
/// [serializeIni] round-trips a config in its original section order.
typedef ConfigModel = Map<String, Map<String, String>>;

/// The formats [detectConfigFormat] can tell apart from raw bytes.
///  - [rcloneIni]        a plaintext `rclone.conf` (INI).
///  - [rcloneEncrypted]  a config rclone itself encrypted (opens with the rclone
///                       CLI + its password); begins with rclone's magic line.
///  - [dumpJson]         `rclone config dump` output (a JSON object).
///  - [aircloneEnvelope] our own AES-256-GCM export envelope ([sealConfigEnvelope]).
///  - [unknown]          none of the above (binary garbage, empty, or prose).
enum ConfigFormat {
  rcloneIni,
  rcloneEncrypted,
  dumpJson,
  aircloneEnvelope,
  unknown,
}

// --- Magic markers -----------------------------------------------------------

/// Our envelope's versioned header magic (plan §4). The trailing `2` is the
/// format version — bumped from the original `ACFG1` when the envelope became
/// self-describing (KDF id + params in the header, header bound as GCM AAD). The
/// shared 4-byte [_magicPrefix] classifies any Airclone envelope; the full magic
/// pins the version so an old `ACFG1` file is recognised and rejected with a
/// clear "unsupported version" rather than mis-parsed. This is a pre-release
/// format change with no real exports in the wild, so ACFG1 is NOT re-openable.
final List<int> _magicAirclone = utf8.encode('ACFG2');

/// The version-independent 4-byte family marker every Airclone envelope starts
/// with, used only to CLASSIFY bytes as our envelope ([detectConfigFormat]); the
/// per-version [_magicAirclone] is what [openConfigEnvelope] actually validates.
final List<int> _magicPrefix = utf8.encode('ACFG');

/// rclone's own encrypted-config marker — the file starts with exactly this
/// line, followed by base64. Matched as bytes so a binary tail can't trip a
/// UTF-8 decode before we've classified it.
final List<int> _magicRcloneEnc = utf8.encode('RCLONE_ENCRYPT_V0:');

/// A UTF-8 byte-order mark. rclone never writes one, but an INI/JSON file
/// exported through some editors can carry it; stripped before the text checks.
const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// Classifies [bytes] into a [ConfigFormat] using the cheapest reliable signal
/// for each. Order matters: the two binary magics are checked FIRST (before any
/// UTF-8 decode) because an encrypted body is not valid text; then the text
/// formats. A payload that is neither our magic, rclone's magic, JSON, nor
/// INI-shaped — including bytes that aren't valid UTF-8 at all — is [unknown]
/// (the caller shows "unrecognised file" rather than mis-parsing).
ConfigFormat detectConfigFormat(List<int> bytes) {
  if (bytes.isEmpty) return ConfigFormat.unknown;
  // Our envelope is raw binary with no BOM — check the version-independent
  // family marker against the true start (a wrong-version ACFG file is still
  // classified as our envelope so the opener can report the version cleanly).
  if (_startsWith(bytes, _magicPrefix)) return ConfigFormat.aircloneEnvelope;
  // Tolerate a leading BOM only for the text-ish markers/decoding below.
  final body = _startsWith(bytes, _utf8Bom) ? bytes.sublist(3) : bytes;
  if (_startsWith(body, _magicRcloneEnc)) return ConfigFormat.rcloneEncrypted;

  String text;
  try {
    text = utf8.decode(body); // throws on malformed → not one of our text forms
  } on FormatException {
    return ConfigFormat.unknown;
  }
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) return ConfigFormat.unknown;
  if (trimmed.startsWith('{')) return ConfigFormat.dumpJson;
  if (_looksLikeIni(text)) return ConfigFormat.rcloneIni;
  return ConfigFormat.unknown;
}

/// INI heuristic: a `[section]` header line is the strong signal; a bare
/// `key = value` line is accepted as a fallback (a fragment with no header). A
/// file with neither is not treated as a config.
bool _looksLikeIni(String text) {
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final c = line[0];
    if (c == '#' || c == ';') continue; // comment
    if (c == '[' && line.endsWith(']') && line.length > 2) return true;
    if (line.contains('=')) return true;
  }
  return false;
}

// --- INI <-> model -----------------------------------------------------------

/// Parses rclone `.conf` INI [text] into a [ConfigModel]. Tolerant by design:
///  - blank lines and `#`/`;` comment lines are ignored;
///  - a value may itself contain `=` (OAuth token JSON, base64 padding) — only
///    the FIRST `=` splits key from value;
///  - a `[section]` with no keys yields a present-but-empty remote;
///  - keys appearing before any section header are dropped (rclone never emits
///    them, and there is no remote to attach them to).
///
/// Keys and section names are trimmed of surrounding whitespace to match how
/// rclone reads them. Insertion order (sections and keys) is preserved.
ConfigModel parseIni(String text) {
  final model = <String, Map<String, String>>{};
  Map<String, String>? current;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final c = line[0];
    if (c == '#' || c == ';') continue;
    if (c == '[' && line.endsWith(']')) {
      final name = line.substring(1, line.length - 1).trim();
      // putIfAbsent so a (malformed) repeated section merges rather than resets.
      current = model.putIfAbsent(name, () => <String, String>{});
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0 || current == null) continue;
    final key = line.substring(0, eq).trim();
    if (key.isEmpty) continue;
    current[key] = line.substring(eq + 1).trim();
  }
  return model;
}

/// Serializes a [ConfigModel] back to INI text in the model's current order
/// (stable: same input map → identical output). Each section is a `[name]`
/// header, its `key = value` pairs, then a blank separator line — the shape
/// rclone writes, and one [parseIni] reads back to an equal model.
String serializeIni(ConfigModel model) {
  final b = StringBuffer();
  for (final section in model.entries) {
    b.writeln('[${section.key}]');
    for (final kv in section.value.entries) {
      b.writeln('${kv.key} = ${kv.value}');
    }
    b.writeln();
  }
  return b.toString();
}

// --- config dump JSON --------------------------------------------------------

/// Parses `rclone config dump` JSON [text] into a [ConfigModel]. The dump is a
/// JSON object of remote-name -> object-of-string-values; every value is coerced
/// to a string (a null becomes `''`) so the model is uniform with [parseIni]'s.
/// Throws [FormatException] if [text] is not a JSON object (the caller sniffed
/// [ConfigFormat.dumpJson] but a truncated/garbage body still lands here).
ConfigModel parseDumpJson(String text) {
  final decoded = json.decode(text);
  if (decoded is! Map) {
    throw const FormatException('config dump is not a JSON object');
  }
  final model = <String, Map<String, String>>{};
  decoded.forEach((name, cfg) {
    final section = <String, String>{};
    if (cfg is Map) {
      cfg.forEach((k, v) => section['$k'] = v == null ? '' : '$v');
    }
    model['$name'] = section;
  });
  return model;
}

// --- Encrypted export envelope (plan §4) ------------------------------------

/// Thrown by [openConfigEnvelope] when the AES-GCM tag fails to verify — i.e. a
/// wrong passphrase (or a tampered ciphertext, indistinguishable by design).
class WrongPassphrase implements Exception {
  const WrongPassphrase([this.message = 'wrong passphrase']);
  final String message;
  @override
  String toString() => 'WrongPassphrase: $message';
}

/// Thrown by [openConfigEnvelope] when the bytes are not a well-formed Airclone
/// envelope at all (bad/absent magic, truncated header/body). Distinct from
/// [WrongPassphrase] so the UI can say "not an Airclone export" vs "wrong
/// password" rather than conflating the two.
class CorruptEnvelope implements Exception {
  const CorruptEnvelope([this.message = 'corrupt envelope']);
  final String message;
  @override
  String toString() => 'CorruptEnvelope: $message';
}

/// AES-256-GCM over an **Argon2id** key. DECOUPLED from `cache_crypto.dart`'s
/// PBKDF2-50k on purpose: the cache is a local obfuscation store, whereas this
/// envelope is a high-value, EXFILTRATABLE artifact (it protects OAuth tokens +
/// secrets and is designed to travel — file export today, LAN/QR handoff and
/// encrypted-blob profile-sync per the plan). 50k PBKDF2 is ~an order of
/// magnitude below current guidance and trivially GPU-brute-forced against a
/// weak passphrase offline; Argon2id (memory-hard, per plan §5) is the right bar
/// and the pinned `cryptography` 2.9 exposes it. Unlike the cache (a fixed app
/// salt over a varying secret), an export uses a fresh random salt per file so
/// the same passphrase never derives the same key across exports; the salt — and
/// the KDF id + params — travel in the header so [openConfigEnvelope] re-derives
/// the exact key even after the defaults are strengthened later.
final AesGcm _aes = AesGcm.with256bits();

/// The KDF parameters stored self-describingly in an ACFG2 header, so raising the
/// work factor later never invalidates an existing export (the header carries the
/// params it was sealed with). [memory] is Argon2id's cost in 1-KiB blocks.
@immutable
class Argon2Params {
  const Argon2Params({
    required this.memory,
    required this.iterations,
    required this.parallelism,
  });

  /// Cost in 1-KiB blocks (e.g. 65536 = 64 MiB).
  final int memory;
  final int iterations;
  final int parallelism;
}

/// The KDF-id byte written into the header. Only Argon2id is emitted; the byte
/// leaves room for a future KDF (or param family) without another format break.
const int _kKdfArgon2id = 1;

/// Production export KDF: Argon2id at m=64 MiB, t=3, p=1 — within the plan §5
/// band (m=64-256 MiB) and the lightest of it, chosen so the pure-Dart derive
/// stays tolerable on a phone while remaining memory-hard. Overridable per call
/// ([sealConfigEnvelope]'s `kdf`) so tests can seal cheaply; the header records
/// whatever was used, so open works regardless.
const Argon2Params _kExportArgon2 = Argon2Params(
  memory: 65536, // 64 MiB
  iterations: 3,
  parallelism: 1,
);

/// Upper bounds rejected as [CorruptEnvelope] before a derive, so a corrupt or
/// hostile header can't drive an OOM/hang (memory capped at 1 GiB).
const int _kMaxArgon2MemoryKiB = 1 << 20; // 1 GiB

/// AES-256-GCM needs a 32-byte key.
const int _kKeyLength = 32;

/// 16 random salt bytes per envelope (128 bits — ample for KDF salting).
const int _kSaltLength = 16;
const int _kNonceLength = 12; // AES-GCM standard nonce
const int _kMacLength = 16; // GCM tag

/// Fixed header length up to (but excluding) the variable-length salt:
///   magic `ACFG2` (5) | kdfId (1) | memory (4, uint32 LE) | iterations (1) |
///   parallelism (1) | saltLen (1)
const int _kHeaderFixed = 5 + 1 + 4 + 1 + 1 + 1;

final Random _rng = Random.secure();
List<int> _randomBytes(int n) =>
    List<int>.generate(n, (_) => _rng.nextInt(256));

/// Derives the AES key from [passphrase] with Argon2id under [p], salted by
/// [salt]. The passphrase is wrapped as the Argon2 "secret key" and the salt as
/// its nonce; the 32-byte output is the AES-256 key.
Future<SecretKey> _deriveExportKey(
  String passphrase,
  List<int> salt,
  Argon2Params p,
) {
  final argon2 = Argon2id(
    memory: p.memory,
    iterations: p.iterations,
    parallelism: p.parallelism,
    hashLength: _kKeyLength,
  );
  return argon2.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
}

/// Builds the self-describing header (also used verbatim as the GCM AAD, so the
/// whole framing — magic, version, KDF id + params, salt — is authenticated):
///   magic | kdfId | memory | iterations | parallelism | saltLen | salt
List<int> _buildEnvelopeHeader(Argon2Params p, List<int> salt) {
  final b = BytesBuilder(copy: false);
  b.add(_magicAirclone);
  b.addByte(_kKdfArgon2id);
  final mem = Uint8List(4);
  ByteData.sublistView(mem).setUint32(0, p.memory, Endian.little);
  b.add(mem);
  b.addByte(p.iterations);
  b.addByte(p.parallelism);
  b.addByte(salt.length);
  b.add(salt);
  return b.toBytes();
}

/// Seals [plaintext] (a config in any text form) into an Airclone encrypted
/// export under [passphrase]. Layout (ACFG2, self-describing):
///
///   magic `ACFG2` (5) | kdfId (1) | memory (4) | iterations (1) |
///   parallelism (1) | saltLen (1) | salt (saltLen) | nonce (12) | ct | mac (16)
///
/// The salt+nonce are random per call, so sealing the same plaintext twice
/// yields different bytes. The full header (through the salt) is bound as the
/// GCM AAD, so tampering the version/KDF params fails authentication. [kdf]
/// defaults to the production [_kExportArgon2] band (m=64 MiB, t=3, p=1) and is
/// overridable only so tests can seal cheaply — the header records whatever was
/// used, so [openConfigEnvelope] re-derives correctly either way.
Future<Uint8List> sealConfigEnvelope(
  String plaintext,
  String passphrase, {
  Argon2Params kdf = _kExportArgon2,
}) async {
  final salt = _randomBytes(_kSaltLength);
  final header = _buildEnvelopeHeader(kdf, salt);
  final key = await _deriveExportKey(passphrase, salt, kdf);
  final box = await _aes.encrypt(
    utf8.encode(plaintext),
    secretKey: key,
    aad: header,
  );
  final b = BytesBuilder(copy: false);
  b.add(header);
  b.add(box.concatenation()); // nonce | ciphertext | mac
  return b.toBytes();
}

/// Opens a blob produced by [sealConfigEnvelope], returning the plaintext.
/// Throws [CorruptEnvelope] when the bytes aren't a valid current-version
/// envelope (bad/old magic, unknown KDF, absurd params, truncated) and
/// [WrongPassphrase] when the passphrase (or the ciphertext/header) is wrong.
/// Both are typed so the caller can prompt "re-enter password" vs "this isn't an
/// Airclone export".
Future<String> openConfigEnvelope(List<int> bytes, String passphrase) async {
  if (bytes.length < _magicPrefix.length || !_startsWith(bytes, _magicPrefix)) {
    throw const CorruptEnvelope('not an Airclone config envelope');
  }
  // Version pin: only ACFG2 is understood (ACFG1 is a pre-release format with no
  // real exports — deliberately not re-openable).
  if (!_startsWith(bytes, _magicAirclone)) {
    throw const CorruptEnvelope('unsupported Airclone export version');
  }
  if (bytes.length < _kHeaderFixed) {
    throw const CorruptEnvelope('envelope is truncated');
  }
  final kdfId = bytes[5];
  if (kdfId != _kKdfArgon2id) {
    throw const CorruptEnvelope('unknown KDF in envelope header');
  }
  final memory = ByteData.sublistView(
    Uint8List.fromList(bytes.sublist(6, 10)),
  ).getUint32(0, Endian.little);
  final iterations = bytes[10];
  final parallelism = bytes[11];
  final saltLen = bytes[12];
  // Reject params that would OOM/hang or that Argon2id itself would assert on,
  // as corruption rather than letting a hostile file drive resource exhaustion.
  if (memory < 8 ||
      memory > _kMaxArgon2MemoryKiB ||
      iterations < 1 ||
      parallelism < 1 ||
      memory < 8 * parallelism) {
    throw const CorruptEnvelope('invalid KDF parameters in envelope header');
  }
  final boxStart = _kHeaderFixed + saltLen;
  // Need a full nonce+mac after the salt for the body to even be a valid box.
  if (bytes.length < boxStart + _kNonceLength + _kMacLength) {
    throw const CorruptEnvelope('envelope is truncated');
  }
  final salt = bytes.sublist(_kHeaderFixed, boxStart);
  final header = bytes.sublist(0, boxStart); // AAD = full header incl. salt
  final key = await _deriveExportKey(
    passphrase,
    salt,
    Argon2Params(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
    ),
  );
  SecretBox box;
  try {
    box = SecretBox.fromConcatenation(
      bytes.sublist(boxStart),
      nonceLength: _kNonceLength,
      macLength: _kMacLength,
    );
  } catch (_) {
    throw const CorruptEnvelope('envelope body is malformed');
  }
  try {
    final clear = await _aes.decrypt(box, secretKey: key, aad: header);
    return utf8.decode(clear);
  } on SecretBoxAuthenticationError {
    // GCM tag mismatch: wrong key (passphrase) or tampered bytes/header.
    throw const WrongPassphrase();
  } on FormatException {
    // Authenticated bytes that somehow aren't UTF-8 — treat as corruption.
    throw const CorruptEnvelope('decrypted content is not valid UTF-8');
  }
}

// --- Dependency closure (plan §4) -------------------------------------------

/// The config keys through which a wrapper remote points at a base remote.
/// crypt/alias/chunker/compress/hasher use `remote =`; `union` AND `combine` use
/// `upstreams =` (a space-separated list) — union entries are bare `remote:path`,
/// combine entries are `dir=remote:path` (the `dir=` label is stripped below).
/// Any other reference key rclone might add later is simply not followed (a
/// conservative miss, never a crash).
const String _kRemoteKey = 'remote';
const String _kUpstreamsKey = 'upstreams';

/// The remote name in a `name:path` reference [value], or `null` when [value]
/// has no remote prefix — an absolute/local path (`/data`, `./x`, `C:\dir`) or a
/// bare name with no colon. The name is everything before the first `:`; if that
/// segment contains a path separator it's a path, not a remote. Note that a
/// Windows drive like `C:` still parses to `C`, but [remoteDependencies] only
/// keeps names that are actually defined remotes, so such spurious prefixes are
/// inert in the closure.
String? remotePrefix(String value) {
  final i = value.indexOf(':');
  if (i <= 0) return null; // no colon, or leading colon
  final name = value.substring(0, i);
  if (name.contains('/') || name.contains('\\')) return null; // it's a path
  return name;
}

/// The set of remote names [cfg] directly references (via `remote`/`upstreams`).
/// Prefixes that aren't remote references (local paths) are dropped by
/// [remotePrefix]. Membership in the model is NOT checked here — [dependencyClosure]
/// does that so a dangling reference is tolerated rather than surfaced.
Set<String> remoteDependencies(Map<String, String> cfg) {
  final refs = <String>{};
  final single = cfg[_kRemoteKey];
  if (single != null) {
    final p = remotePrefix(single);
    if (p != null) refs.add(p);
  }
  final upstreams = cfg[_kUpstreamsKey];
  if (upstreams != null) {
    for (final entry in upstreams.split(RegExp(r'\s+'))) {
      if (entry.isEmpty) continue;
      // `combine` upstreams are `dir=remote:path`; strip the leading label so
      // the BASE (`remote`) is resolved, not the `dir=remote` mash that would
      // never match a model key. Only an `=` that precedes the first `:` is a
      // combine label — `union`'s bare `remote:path` (and any `=` inside a path)
      // is left intact.
      final eq = entry.indexOf('=');
      final colon = entry.indexOf(':');
      final ref = (eq >= 0 && (colon < 0 || eq < colon))
          ? entry.substring(eq + 1)
          : entry;
      final p = remotePrefix(ref);
      if (p != null) refs.add(p);
    }
  }
  return refs;
}

/// Expands [selected] to the full set of remotes that must travel together for a
/// scoped export to work on arrival: a crypt/alias/chunker/compress/hasher/union/
/// combine remote drags in the base(s) it points at, transitively (alias -> crypt ->
/// drive all come along). Only names present in [model] are added, so a
/// reference to a base that isn't in the config — or a Windows-drive-looking
/// path — is tolerated and simply not included. [selected] is returned as-is
/// (even entries not in [model]); the caller chose them.
Set<String> dependencyClosure(ConfigModel model, Set<String> selected) {
  final closure = <String>{...selected};
  final queue = <String>[...selected];
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    final cfg = model[name];
    if (cfg == null) continue; // selected/referenced but not in the model
    for (final dep in remoteDependencies(cfg)) {
      if (!model.containsKey(dep)) continue; // dangling base — tolerated
      if (closure.add(dep)) queue.add(dep); // add() is false if already present
    }
  }
  return closure;
}

// --- Merge planning (plan §3) -----------------------------------------------

/// One remote's fate in a planned merge-import. [name] is the incoming remote's
/// name and [type] its `type` (for the preview list, `''` if absent). On a
/// [collision] with an existing remote, [renamedTo] holds the non-colliding name
/// the merge will use (user-editable in the preview); otherwise [renamedTo] is
/// null and the remote imports under its own [name].
@immutable
class ImportDecision {
  const ImportDecision({
    required this.name,
    required this.type,
    required this.collision,
    this.renamedTo,
  });

  final String name;
  final String type;
  final bool collision;
  final String? renamedTo;

  @override
  bool operator ==(Object other) =>
      other is ImportDecision &&
      other.name == name &&
      other.type == type &&
      other.collision == collision &&
      other.renamedTo == renamedTo;

  @override
  int get hashCode => Object.hash(name, type, collision, renamedTo);

  @override
  String toString() =>
      'ImportDecision($name, type: $type, collision: $collision, '
      'renamedTo: $renamedTo)';
}

/// Plans a merge of [incoming] onto [existing], one [ImportDecision] per incoming
/// remote (in incoming order). A name already in [existing] collides and is
/// assigned a `-imported` suffix (`foo` -> `foo-imported`), bumping to
/// `-imported-2`, `-imported-3`, … until the name is free. "Free" means it
/// clashes with neither an existing remote, another incoming remote, nor a name
/// already handed to an earlier decision in this same plan — so two colliding
/// remotes never get the same rename.
List<ImportDecision> planImport(ConfigModel existing, ConfigModel incoming) {
  // Seed the taken set with everything that could clash before renames start.
  final taken = <String>{...existing.keys, ...incoming.keys};
  final decisions = <ImportDecision>[];
  for (final entry in incoming.entries) {
    final name = entry.key;
    final type = entry.value['type'] ?? '';
    final collision = existing.containsKey(name);
    String? renamedTo;
    if (collision) {
      var candidate = '$name-imported';
      var n = 2;
      while (taken.contains(candidate)) {
        candidate = '$name-imported-$n';
        n++;
      }
      taken.add(candidate);
      renamedTo = candidate;
    }
    decisions.add(
      ImportDecision(
        name: name,
        type: type,
        collision: collision,
        renamedTo: renamedTo,
      ),
    );
  }
  return decisions;
}
