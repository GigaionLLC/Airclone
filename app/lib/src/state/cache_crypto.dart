import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The rclone config password (or null). Set by the engine controller once the
/// engine is up; **never persisted**. When non-null, the on-disk cache is bound
/// to it — so without the config password the cached blobs are unreadable.
final cachePassphraseProvider = StateProvider<String?>((ref) => null);

/// PBKDF2 work factor. **Do not change**: it is baked into every blob already on
/// disk, and a different figure silently makes the whole cache unreadable —
/// which degrades to "regenerate everything", not to an error anyone would see.
const int kCacheKdfIterations = 50000;

/// Fixed app salt — the secret (password / name) is what varies, not the salt.
final List<int> _kCacheSalt = utf8.encode('airclone::cache::v1');

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
///
/// **Both halves run in a worker isolate**, and that is load-bearing rather than
/// tidiness. Each is CPU-bound pure Dart, and each used to run on the isolate
/// that also builds frames: the PBKDF2 stretch costs ~1.5 s on a phone, and a
/// decrypt a few ms paid *per thumbnail* on every scroll. A grid of photos calls
/// this once per tile, so on the UI isolate the first call froze the app and the
/// rest janked every fling. See [_CryptoWorker].
class CacheCrypto {
  CacheCrypto(this._ref);
  final Ref _ref;

  /// One worker for the process. The derived keys live inside it, so a secret is
  /// stretched once however many [CacheCrypto] instances exist.
  static final _CryptoWorker _worker = _CryptoWorker();

  /// Which secret this remote's blobs are bound to. Resolved on the calling
  /// isolate (it reads a provider); the stretching happens in the worker.
  String _secretFor(String remoteSecret) {
    final pw = _ref.read(cachePassphraseProvider);
    return (pw != null && pw.isNotEmpty) ? 'pw:$pw' : 'rn:$remoteSecret';
  }

  /// Encrypt [plain] into a self-describing blob (nonce | ciphertext | mac).
  /// Throws if no blob could be produced, which every caller already treats as
  /// "skip the disk write".
  Future<Uint8List> seal(Uint8List plain, String remoteSecret) async {
    final out = await _worker.run(
      _CryptoOp.seal,
      _secretFor(remoteSecret),
      plain,
    );
    if (out == null) throw StateError('cache seal failed');
    return out;
  }

  /// Decrypt a [blob] produced by [seal]; `null` if the key is wrong or the blob
  /// is corrupt.
  Future<Uint8List?> open(Uint8List blob, String remoteSecret) =>
      _worker.run(_CryptoOp.open, _secretFor(remoteSecret), blob);
}

/// The two things the worker can be asked to do.
enum _CryptoOp { seal, open }

/// Runs [CacheCrypto]'s key stretching and AES-GCM on a second isolate, so the
/// UI isolate never pays for either.
///
/// One long-lived isolate rather than an `Isolate.run` per call: a folder of
/// photos would otherwise spawn one per thumbnail, and the derived keys have to
/// live somewhere in order to be derived only once. Keeping them here rather
/// than on the UI isolate is also the better home for key material.
///
/// If the isolate cannot be spawned the work happens in-process instead. That is
/// slow — it is exactly the old behaviour — but correct, which is the right way
/// round for a cache: the alternative is an app that cannot show a thumbnail.
class _CryptoWorker {
  SendPort? _tx;
  Future<void>? _starting;
  bool _unavailable = false;

  final ReceivePort _rx = ReceivePort();
  final Map<int, Completer<Uint8List?>> _pending = {};
  int _nextId = 0;
  bool _listening = false;

  static final Map<String, Future<SecretKey>> _fallbackKeys = {};

  Future<Uint8List?> run(_CryptoOp op, String secret, Uint8List data) async {
    if (!_unavailable) {
      try {
        await _ensureStarted();
      } catch (_) {
        // Fall through to the in-process path below.
      }
    }
    final tx = _tx;
    if (tx == null) return _inProcess(op, secret, data);

    final id = _nextId++;
    final completer = Completer<Uint8List?>();
    _pending[id] = completer;
    tx.send([id, op.index, secret, data, _rx.sendPort]);
    return completer.future;
  }

  Future<void> _ensureStarted() {
    if (_tx != null) return Future<void>.value();
    return _starting ??= _spawn();
  }

  Future<void> _spawn() async {
    if (!_listening) {
      _rx.listen((message) {
        final reply = message as List<Object?>;
        _pending.remove(reply[0] as int)?.complete(reply[1] as Uint8List?);
      });
      _listening = true;
    }
    final handshake = ReceivePort();
    try {
      await Isolate.spawn(
        _cryptoWorkerMain,
        handshake.sendPort,
        debugName: 'airclone-cache-crypto',
      );
      _tx =
          await handshake.first.timeout(const Duration(seconds: 10))
              as SendPort;
    } catch (_) {
      // No isolate (spawn refused, or a host that cannot). Latch it: retrying
      // per call would make every thumbnail pay the failed spawn over again.
      _unavailable = true;
      _starting = null;
      rethrow;
    } finally {
      handshake.close();
    }
  }

  /// Last resort: the same work, on the calling isolate.
  Future<Uint8List?> _inProcess(
    _CryptoOp op,
    String secret,
    Uint8List data,
  ) async {
    try {
      final key = await deriveCacheKey(_fallbackKeys, secret);
      return op == _CryptoOp.seal
          ? await _sealWith(key, data)
          : await _openWith(key, data);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Worker isolate
// ---------------------------------------------------------------------------

/// Entry point for the crypto isolate. Owns the derived-key cache, so a secret
/// is stretched exactly once for the life of the process.
void _cryptoWorkerMain(SendPort handshake) {
  final rx = ReceivePort();
  handshake.send(rx.sendPort);

  final keys = <String, Future<SecretKey>>{};

  rx.listen((message) async {
    final req = message as List<Object?>;
    final id = req[0] as int;
    final op = _CryptoOp.values[req[1] as int];
    final secret = req[2] as String;
    final data = req[3] as Uint8List;
    final reply = req[4] as SendPort;
    try {
      final key = await deriveCacheKey(keys, secret);
      reply.send([
        id,
        op == _CryptoOp.seal
            ? await _sealWith(key, data)
            : await _openWith(key, data),
      ]);
    } catch (_) {
      reply.send([id, null]);
    }
  });
}

/// Stretch [secret] into a key, reusing [into]'s entry when one exists.
///
/// The map holds the **Future**, not the key. Holding the key alone leaves a
/// window: every caller arriving during the ~1.5 s stretch finds no entry yet
/// and starts a stretch of its own. A folder of thumbnails opens with exactly
/// that burst of concurrent calls, which turned one 1.5 s cost into seven —
/// measured on an Android emulator as 10.6 s of solid CPU, and the "app isn't
/// responding" dialog that goes with it. A failed derivation is evicted rather
/// than cached, so a transient failure does not poison the secret forever.
///
/// Visible for testing: the dedup is the fix, so it is worth pinning directly.
Future<SecretKey> deriveCacheKey(
  Map<String, Future<SecretKey>> into,
  String secret,
) {
  final existing = into[secret];
  if (existing != null) return existing;
  final pending = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: kCacheKdfIterations,
    bits: 256,
  ).deriveKeyFromPassword(password: secret, nonce: _kCacheSalt);
  into[secret] = pending;
  unawaited(
    pending.catchError((Object e) {
      into.remove(secret);
      throw e;
    }),
  );
  return pending;
}

Future<Uint8List> _sealWith(SecretKey key, Uint8List plain) async {
  final box = await AesGcm.with256bits().encrypt(plain, secretKey: key);
  return Uint8List.fromList(box.concatenation());
}

Future<Uint8List> _openWith(SecretKey key, Uint8List blob) async {
  final box = SecretBox.fromConcatenation(blob, nonceLength: 12, macLength: 16);
  return Uint8List.fromList(
    await AesGcm.with256bits().decrypt(box, secretKey: key),
  );
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
