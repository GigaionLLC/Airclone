import 'dart:convert';
import 'dart:typed_data';

import 'package:airclone/src/state/cache_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The preview cache is encrypted at rest, and the cost of that used to land on
/// the isolate that draws frames: one PBKDF2 stretch is ~1.5 s on a phone, and a
/// decrypt is paid per thumbnail. A grid of photos calls both in a burst, which
/// is what made scrolling a photo folder freeze the app.
///
/// These tests pin the two properties that fix it — the stretch happens once,
/// and blobs still round-trip — plus the compatibility rule that matters most:
/// thumbnails already on a user's disk must stay readable.
void main() {
  ProviderContainer make() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  final plain = Uint8List.fromList(List<int>.generate(4096, (i) => i % 256));

  group('key stretching', () {
    test('concurrent callers share ONE derivation', () async {
      final keys = <String, Future<SecretKey>>{};
      // Do NOT await between these: the burst is the whole point. Before the
      // fix each call found an empty map and started its own 1.5 s stretch.
      final a = deriveCacheKey(keys, 'rn:remote');
      final b = deriveCacheKey(keys, 'rn:remote');
      final c = deriveCacheKey(keys, 'rn:remote');
      expect(identical(a, b), isTrue);
      expect(identical(a, c), isTrue);
      expect(keys, hasLength(1));
      expect(await a, isA<SecretKey>());
    });

    test('a different secret gets its own key', () async {
      final keys = <String, Future<SecretKey>>{};
      final a = deriveCacheKey(keys, 'rn:one');
      final b = deriveCacheKey(keys, 'rn:two');
      expect(identical(a, b), isFalse);
      expect(keys, hasLength(2));
      expect(
        await (await a).extractBytes(),
        isNot(equals(await (await b).extractBytes())),
      );
    });

    test('a settled derivation is reused rather than repeated', () async {
      final keys = <String, Future<SecretKey>>{};
      final first = await deriveCacheKey(keys, 'rn:remote');
      final second = await deriveCacheKey(keys, 'rn:remote');
      expect(identical(first, second), isTrue);
    });
  });

  group('seal / open', () {
    test('round-trips through the worker', () async {
      final crypto = make().read(cacheCryptoProvider);
      final blob = await crypto.seal(plain, 'remote');
      expect(blob, isNot(equals(plain)), reason: 'must not store cleartext');
      expect(await crypto.open(blob, 'remote'), equals(plain));
    });

    test('a wrong secret yields null, not an exception', () async {
      final crypto = make().read(cacheCryptoProvider);
      final blob = await crypto.seal(plain, 'remote');
      expect(await crypto.open(blob, 'a-different-remote'), isNull);
    });

    test('a corrupt blob yields null', () async {
      final crypto = make().read(cacheCryptoProvider);
      final blob = await crypto.seal(plain, 'remote');
      blob[blob.length - 1] ^= 0xFF; // break the MAC
      expect(await crypto.open(blob, 'remote'), isNull);
    });

    test('too-short input yields null rather than throwing', () async {
      final crypto = make().read(cacheCryptoProvider);
      expect(
        await crypto.open(Uint8List.fromList([1, 2, 3]), 'remote'),
        isNull,
      );
    });

    test('the config password, when set, is what binds the blob', () async {
      final container = make();
      container.read(cachePassphraseProvider.notifier).state = 'hunter2';
      final crypto = container.read(cacheCryptoProvider);
      final blob = await crypto.seal(plain, 'remote');
      // Same remote name, different password: the cache must not open.
      expect(await crypto.open(blob, 'remote'), equals(plain));
      container.read(cachePassphraseProvider.notifier).state = 'other';
      expect(await crypto.open(blob, 'remote'), isNull);
    });
  });

  test(
    'opens a blob sealed the old way — caches on disk stay readable',
    () async {
      // Built from the documented primitives rather than from `seal`, so this
      // fails if the worker ever drifts from what wrote the files already on a
      // user's disk. A mismatch is silent in production: every thumbnail simply
      // regenerates, and nobody sees an error.
      final key =
          await Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: kCacheKdfIterations,
            bits: 256,
          ).deriveKeyFromPassword(
            password: 'rn:remote',
            nonce: utf8.encode('airclone::cache::v1'),
          );
      final box = await AesGcm.with256bits().encrypt(plain, secretKey: key);
      final legacyBlob = Uint8List.fromList(box.concatenation());

      final crypto = make().read(cacheCryptoProvider);
      expect(await crypto.open(legacyBlob, 'remote'), equals(plain));
    },
  );
}
