@TestOn('vm')
library;

import 'dart:io';

import 'package:airclone/src/rclone/rclone_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// The engine hot-swap, against real files in a temp dir.
///
/// This is the path that was broken: the in-app "Update engine" wrote the new
/// binary straight over the managed one, which on Windows is LOCKED by the
/// running engine, so the update always failed once an engine had been
/// downloaded. The fix stages the download, stops the engine, then swaps —
/// keeping the old binary so a bad rclone release can be undone.
void main() {
  late Directory dir;
  late String managed;
  late String staged;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('airclone_engine_swap');
    managed = '${dir.path}${Platform.pathSeparator}rclone';
    staged = '$managed.new';
  });
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      /* best effort */
    }
  });

  Future<void> write(String path, String body) =>
      File(path).writeAsString(body);
  String? read(String path) =>
      File(path).existsSync() ? File(path).readAsStringSync() : null;

  group('swapEngineBinary', () {
    test('installs the staged binary and keeps the old one as .old', () async {
      await write(managed, 'OLD');
      await write(staged, 'NEW');

      await RcloneEngine.swapEngineBinary(staged: staged, managed: managed);

      expect(read(managed), 'NEW');
      expect(read('$managed.old'), 'OLD', reason: 'rollback needs the old one');
      expect(File(staged).existsSync(), isFalse, reason: 'staged is consumed');
    });

    test('works when there is no existing engine (first install)', () async {
      await write(staged, 'NEW');

      await RcloneEngine.swapEngineBinary(staged: staged, managed: managed);

      expect(read(managed), 'NEW');
      expect(File('$managed.old').existsSync(), isFalse);
    });

    test('replaces a stale .old from an earlier update', () async {
      await write('$managed.old', 'ANCIENT');
      await write(managed, 'OLD');
      await write(staged, 'NEW');

      await RcloneEngine.swapEngineBinary(staged: staged, managed: managed);

      expect(read(managed), 'NEW');
      expect(read('$managed.old'), 'OLD');
    });

    test('a missing staged file leaves the old engine in place', () async {
      await write(managed, 'OLD');
      // No staged file: the swap must fail AND put the engine back, never
      // leave the app with nothing to run.
      await expectLater(
        RcloneEngine.swapEngineBinary(staged: staged, managed: managed),
        throwsA(isA<Object>()),
      );

      expect(read(managed), 'OLD');
    });
  });

  group('restoreEngineBackup', () {
    test('puts the previous engine back', () async {
      await write(managed, 'NEW-BROKEN');
      await write('$managed.old', 'OLD-GOOD');

      await RcloneEngine.restoreEngineBackup(managed);

      expect(read(managed), 'OLD-GOOD');
      expect(File('$managed.old').existsSync(), isFalse);
    });

    test('is a no-op with no backup', () async {
      await write(managed, 'CURRENT');

      await RcloneEngine.restoreEngineBackup(managed);

      expect(read(managed), 'CURRENT');
    });
  });

  test(
    'discardEngineBackup drops the .old once the new engine is up',
    () async {
      await write(managed, 'NEW');
      await write('$managed.old', 'OLD');

      await RcloneEngine.discardEngineBackup(managed);

      expect(read(managed), 'NEW');
      expect(File('$managed.old').existsSync(), isFalse);
    },
  );

  test('swap then rollback returns to exactly the original binary', () async {
    await write(managed, 'v1.74.3');
    await write(staged, 'v1.75.0-broken');

    await RcloneEngine.swapEngineBinary(staged: staged, managed: managed);
    expect(read(managed), 'v1.75.0-broken');

    await RcloneEngine.restoreEngineBackup(managed);
    expect(read(managed), 'v1.74.3');
  });
}
