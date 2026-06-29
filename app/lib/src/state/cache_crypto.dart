import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The rclone config password (or null). Set by the engine controller once the
/// engine is up; **never persisted**. When non-null, the on-disk cache is bound
/// to it — so without the config password the cached blobs are unreadable.
final cachePassphraseProvider = StateProvider<String?>((ref) => null);

/// Encrypts the on-disk preview cache at rest (AES-256-GCM, key via
/// PBKDF2-HMAC-SHA256).
///
/// Key source:
///  - **Config password** when the rclone config is encrypted (so the cache is
///    useless without it — coherent with the remotes themselves).
///  - **Hash of the remote name** otherwise. The name is not secret, so this is
///    deliberate *obfuscation only* (stops casual browsing of the cache folder),
///    chosen because an un-encrypted config offers no real secret to bind to.
///
/// Failures degrade safely: a wrong-key/corrupt blob decrypts to `null` (the
/// caller regenerates) and a seal failure simply skips the disk write.
class CacheCrypto {
  CacheCrypto(this._ref);
  final Ref _ref;

  static final _aes = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 50000,
    bits: 256,
  );

  /// Fixed app salt — the secret (password / name) is what varies, not the salt.
  static final List<int> _salt = utf8.encode('airclone::cache::v1');

  final _keys = <String, SecretKey>{};

  Future<SecretKey> _keyFor(String remoteSecret) async {
    final pw = _ref.read(cachePassphraseProvider);
    final secret = (pw != null && pw.isNotEmpty)
        ? 'pw:$pw'
        : 'rn:$remoteSecret';
    final cached = _keys[secret];
    if (cached != null) return cached;
    final key = await _kdf.deriveKeyFromPassword(
      password: secret,
      nonce: _salt,
    );
    _keys[secret] = key;
    return key;
  }

  /// Encrypt [plain] into a self-describing blob (nonce | ciphertext | mac).
  Future<Uint8List> seal(Uint8List plain, String remoteSecret) async {
    final key = await _keyFor(remoteSecret);
    final box = await _aes.encrypt(plain, secretKey: key);
    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypt a [blob] produced by [seal]; `null` if the key is wrong or the blob
  /// is corrupt.
  Future<Uint8List?> open(Uint8List blob, String remoteSecret) async {
    try {
      final key = await _keyFor(remoteSecret);
      final box = SecretBox.fromConcatenation(
        blob,
        nonceLength: 12,
        macLength: 16,
      );
      final clear = await _aes.decrypt(box, secretKey: key);
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }
}

final cacheCryptoProvider = Provider<CacheCrypto>((ref) => CacheCrypto(ref));

/// When true, thumbnails/previews are kept in RAM only — nothing is written to
/// disk. Highest privacy; re-scrolling regenerates and nothing persists.
class CacheMemoryOnly extends Notifier<bool> {
  static const _key = 'cache_memory_only';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getBool(_key) ?? false;
    } catch (_) {
      // keep default
    }
  }

  Future<void> set(bool v) async {
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {
      // best-effort
    }
  }
}

final cacheMemoryOnlyProvider = NotifierProvider<CacheMemoryOnly, bool>(
  CacheMemoryOnly.new,
);

/// The cache directories Airclone writes (thumbnails + folder previews).
const List<String> _cacheDirNames = [
  'airclone_thumbs',
  'airclone_folderthumbs',
];

/// Total bytes currently used by the on-disk caches.
Future<int> diskCacheSize() async {
  var total = 0;
  Directory base;
  try {
    base = await getApplicationCacheDirectory();
  } catch (_) {
    base = await getTemporaryDirectory();
  }
  for (final name in _cacheDirNames) {
    try {
      final dir = Directory('${base.path}/$name');
      if (await dir.exists()) {
        await for (final f in dir.list()) {
          if (f is File) {
            try {
              total += await f.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
  return total;
}

/// Deletes the on-disk thumbnail + folder-preview caches. Returns bytes freed.
Future<int> clearDiskCaches() async {
  final before = await diskCacheSize();
  Directory base;
  try {
    base = await getApplicationCacheDirectory();
  } catch (_) {
    base = await getTemporaryDirectory();
  }
  for (final name in _cacheDirNames) {
    try {
      final dir = Directory('${base.path}/$name');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
  return before;
}
