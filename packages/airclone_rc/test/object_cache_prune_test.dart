@TestOn('vm')
library;

import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

/// The copy fallback's cache is capped (#45): before, every video played or
/// thumbnailed on iOS stayed on the phone in full.
void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('prune'));
  tearDown(() async => dir.delete(recursive: true));

  LibrcloneObjectServer server() => LibrcloneObjectServer(
    rpc: (method, [params]) async => const {},
    cacheDir: dir.path,
    maxCacheBytes: 250,
    maxCacheAge: const Duration(hours: 1),
  );

  Future<File> file(
    String name,
    int size, {
    Duration age = Duration.zero,
  }) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(List.filled(size, 0));
    await f.setLastModified(DateTime.now().subtract(age));
    return f;
  }

  Set<String> left() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toSet();

  test('drops partial copies and files past the age limit', () async {
    await file('fresh', 10);
    await file('stale', 10, age: const Duration(hours: 2));
    await file('leftover.part', 10);
    await server().pruneCache();
    expect(left(), {'fresh'});
  });

  test('evicts the oldest first until it fits the size cap', () async {
    await file('a', 100, age: const Duration(minutes: 30));
    await file('b', 100, age: const Duration(minutes: 20));
    await file('c', 100, age: const Duration(minutes: 10));
    await server().pruneCache();
    expect(left(), {'b', 'c'});
  });

  test('never evicts the file about to be served', () async {
    await file('big', 400, age: const Duration(minutes: 5));
    await file('old', 100, age: const Duration(minutes: 30));
    await server().pruneCache(keep: 'big');
    expect(left(), {'big'});
  });
}
