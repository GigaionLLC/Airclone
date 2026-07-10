import 'dart:io';

import 'package:airclone/src/state/config_backups.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for the always-on config-backup ring (dev/plans/config-portability-plan.md
/// §2). The backups folder and the clock are injected, so the write→prune→restore
/// behaviour is exercised over a throwaway temp directory with a controllable
/// wall clock — no app-support lookup, no real-time flakiness.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp; // sandbox holding both the "active config" and the ring
  late Directory ring; // the backups folder

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('airclone-backups-test-');
    ring = Directory('${tmp.path}/config-backups');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A [ConfigBackups] over [ring] whose clock returns a fixed [at] — bump it
  /// per call to simulate backups taken at distinct seconds.
  ConfigBackups backupsAt(DateTime at) =>
      ConfigBackups(ring, clock: () => at, keep: 10);

  File activeConfig(String contents) {
    final f = File('${tmp.path}/rclone.conf');
    f.writeAsStringSync(contents);
    return f;
  }

  group('backupActiveConfig', () {
    test(
      'copies the active config to a UTC-stamped name and returns it',
      () async {
        final src = activeConfig('[drive]\ntype = drive\n');
        final at = DateTime.utc(2026, 7, 9, 14, 30, 5);
        final path = await backupsAt(at).backupActiveConfig(src);

        expect(path, isNotNull);
        expect(path, endsWith('rclone-20260709-143005.conf'));
        expect(File(path!).readAsStringSync(), '[drive]\ntype = drive\n');
      },
    );

    test('stamps in UTC regardless of the clock\'s zone', () async {
      final src = activeConfig('x');
      // A local-zone timestamp; backupActiveConfig must convert to UTC.
      final local = DateTime(2026, 1, 2, 3, 4, 5).toUtc();
      final path = await backupsAt(local).backupActiveConfig(src);
      final expected =
          'rclone-${local.year.toString().padLeft(4, '0')}'
          '${local.month.toString().padLeft(2, '0')}'
          '${local.day.toString().padLeft(2, '0')}-'
          '${local.hour.toString().padLeft(2, '0')}'
          '${local.minute.toString().padLeft(2, '0')}'
          '${local.second.toString().padLeft(2, '0')}.conf';
      expect(path, endsWith(expected));
    });

    test('returns null when there is no active config to snapshot', () async {
      final missing = File('${tmp.path}/does-not-exist.conf');
      expect(
        await backupsAt(DateTime.utc(2026)).backupActiveConfig(missing),
        isNull,
      );
    });

    test(
      'two backups in the same second get a disambiguating suffix',
      () async {
        final at = DateTime.utc(2026, 7, 9, 14, 30, 5);
        final b = backupsAt(at);
        final first = await b.backupActiveConfig(activeConfig('one'));
        final second = await b.backupActiveConfig(activeConfig('two'));
        expect(first, endsWith('rclone-20260709-143005.conf'));
        expect(second, endsWith('rclone-20260709-143005-02.conf'));
        // Both copies survive and hold their own contents.
        expect(File(first!).readAsStringSync(), 'one');
        expect(File(second!).readAsStringSync(), 'two');
      },
    );

    test(
      'same-second backups list newest-first (bare first file sorts oldest)',
      () async {
        final at = DateTime.utc(2026, 3, 4, 5, 6, 7);
        final b = backupsAt(at);
        await b.backupActiveConfig(activeConfig('first'));
        await b.backupActiveConfig(activeConfig('second'));
        await b.backupActiveConfig(activeConfig('third'));
        final names = (await b.listBackups())
            .map((f) => f.uri.pathSegments.last)
            .toList();
        // Newest first: the last-written (-03) leads and the bare first-written
        // trails — write order is preserved even though '.' > '-' would invert a
        // naive lexical basename sort.
        expect(names, [
          'rclone-20260304-050607-03.conf',
          'rclone-20260304-050607-02.conf',
          'rclone-20260304-050607.conf',
        ]);
      },
    );
  });

  group('listBackups & prune', () {
    test('keeps only the 10 newest, deleting the oldest', () async {
      final src = activeConfig('cfg');
      // 12 backups one minute apart, oldest first.
      for (var i = 0; i < 12; i++) {
        await backupsAt(DateTime.utc(2026, 1, 1, 0, i)).backupActiveConfig(src);
      }
      final backups = await backupsAt(DateTime.utc(2026)).listBackups();
      expect(backups.length, 10);
      final names = backups.map((f) => f.uri.pathSegments.last).toList();
      // Newest first (descending stamp), and the two oldest (00:00, 00:01) gone.
      expect(names.first, 'rclone-20260101-001100.conf'); // 00:11
      expect(names.last, 'rclone-20260101-000200.conf'); // 00:02
      expect(names, isNot(contains('rclone-20260101-000000.conf')));
      expect(names, isNot(contains('rclone-20260101-000100.conf')));
    });

    test(
      'listBackups returns newest-first and ignores foreign files',
      () async {
        final src = activeConfig('cfg');
        await backupsAt(DateTime.utc(2026, 1, 1, 0, 0)).backupActiveConfig(src);
        await backupsAt(DateTime.utc(2026, 1, 1, 0, 5)).backupActiveConfig(src);
        // A non-backup file in the folder must be skipped.
        File('${ring.path}/notes.txt').writeAsStringSync('ignore me');

        final backups = await backupsAt(DateTime.utc(2026)).listBackups();
        final names = backups.map((f) => f.uri.pathSegments.last).toList();
        expect(names, [
          'rclone-20260101-000500.conf',
          'rclone-20260101-000000.conf',
        ]);
      },
    );

    test('an empty/absent ring lists nothing', () async {
      expect(await backupsAt(DateTime.utc(2026)).listBackups(), isEmpty);
    });
  });

  group('restoreBackup', () {
    test(
      'overwrites the active config and snapshots the current one first',
      () async {
        final src = activeConfig('ORIGINAL');
        // Make a backup of ORIGINAL, then mutate the active config.
        final backupPath = await backupsAt(
          DateTime.utc(2026, 1, 1, 0, 0),
        ).backupActiveConfig(src);
        src.writeAsStringSync('MUTATED');

        // Restore the ORIGINAL backup over the (now MUTATED) active config.
        final snapshot = await backupsAt(
          DateTime.utc(2026, 1, 1, 0, 5),
        ).restoreBackup(backupPath!, src);

        // Active config is back to the backed-up contents…
        expect(src.readAsStringSync(), 'ORIGINAL');
        // …and the pre-restore MUTATED state was snapshotted for reversibility.
        expect(snapshot, isNotNull);
        expect(File(snapshot!).readAsStringSync(), 'MUTATED');
      },
    );

    test(
      'restoring the OLDEST backup survives the snapshot-triggered prune',
      () async {
        final src = activeConfig('v0');
        // Fill the ring to capacity (10) so restoring adds an 11th (the snapshot),
        // which prunes the oldest — the very backup we're about to restore.
        String? oldest;
        for (var i = 0; i < 10; i++) {
          final p = await backupsAt(
            DateTime.utc(2026, 1, 1, 0, i),
          ).backupActiveConfig(activeConfig('v$i'));
          oldest ??= p; // first (00:00) is the oldest
        }
        // The oldest backup captured `v0`. Restore it while at capacity.
        src.writeAsStringSync('current');
        await backupsAt(
          DateTime.utc(2026, 1, 1, 1, 0),
        ).restoreBackup(oldest!, src);

        // Even though the snapshot's prune deleted the oldest FILE, its bytes were
        // read first, so the active config holds the restored `v0`.
        expect(src.readAsStringSync(), 'v0');
        expect(File(oldest).existsSync(), isFalse); // pruned as the oldest
      },
    );
  });
}
