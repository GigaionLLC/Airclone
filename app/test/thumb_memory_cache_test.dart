import 'dart:typed_data';

import 'package:airclone/src/state/thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A thumbnail tile that scrolls out of a grid is disposed, taking its bytes
/// with it. Without a cache behind it, scrolling back re-read the file and
/// re-ran the at-rest decrypt for a picture already built twice — which is why
/// a second pass over a photo folder cost as much as the first.
///
/// The store is bounded in BYTES, because a thumbnail's size depends on what is
/// in the picture, so an entry count would not bound memory at all.
void main() {
  Uint8List bytes(int n) => Uint8List(n);

  test('a hit returns the identical instance', () {
    // Identity, not equality: Flutter's image cache keys on the instance, so
    // handing back the same list is what stops the PNG being decoded again.
    final cache = ThumbMemoryCache();
    final value = bytes(10);
    cache.put('a', value);
    expect(identical(cache.get('a'), value), isTrue);
  });

  test('a miss is null and costs nothing', () {
    final cache = ThumbMemoryCache();
    expect(cache.get('nope'), isNull);
    expect(cache.bytes, 0);
    expect(cache.length, 0);
  });

  test('tracks its size across put, replace and remove', () {
    final cache = ThumbMemoryCache();
    cache.put('a', bytes(100));
    cache.put('b', bytes(250));
    expect(cache.bytes, 350);
    expect(cache.length, 2);

    cache.put('a', bytes(50)); // replace, not add
    expect(cache.bytes, 300);
    expect(cache.length, 2);

    cache.remove('b');
    expect(cache.bytes, 50);
    expect(cache.length, 1);

    cache.remove('gone'); // absent key must not go negative
    expect(cache.bytes, 50);
  });

  test('evicts least-recently-used first once over budget', () {
    final cache = ThumbMemoryCache(budgetBytes: 300);
    cache.put('a', bytes(100));
    cache.put('b', bytes(100));
    cache.put('c', bytes(100));
    expect(cache.bytes, 300);

    // Touch 'a' so 'b' becomes the oldest.
    expect(cache.get('a'), isNotNull);

    cache.put('d', bytes(100)); // 400 > 300 → drop one
    expect(cache.get('b'), isNull, reason: 'b was least recently used');
    expect(cache.get('a'), isNotNull);
    expect(cache.get('c'), isNotNull);
    expect(cache.get('d'), isNotNull);
    expect(cache.bytes, lessThanOrEqualTo(300));
  });

  test('keeps evicting until it is back inside the budget', () {
    final cache = ThumbMemoryCache(budgetBytes: 250);
    cache.put('a', bytes(100));
    cache.put('b', bytes(100));
    cache.put('c', bytes(200)); // 400 > 250 → must drop BOTH a and b
    expect(cache.length, 1);
    expect(cache.get('c'), isNotNull);
    expect(cache.bytes, 200);
  });

  test('an entry larger than the whole budget is still served', () {
    // The caller is about to draw it; dropping it on insert would mean fetching
    // it again immediately and never being able to show it at all.
    final cache = ThumbMemoryCache(budgetBytes: 100);
    cache.put('huge', bytes(500));
    expect(cache.get('huge'), isNotNull);
    expect(cache.length, 1);
  });

  test('clear empties it and resets the accounting', () {
    final cache = ThumbMemoryCache();
    cache.put('a', bytes(100));
    cache.put('b', bytes(100));
    cache.clear();
    expect(cache.length, 0);
    expect(cache.bytes, 0);
    expect(cache.get('a'), isNull);
  });
}
