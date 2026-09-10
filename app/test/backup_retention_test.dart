import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/state/backup_retention.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pruning old versions is a delete loop over a remote — the most destructive
/// thing this app does. Everything it deletes is decided by the two pure
/// functions here, so these tests are the safety mechanism, not documentation
/// of one.
///
/// The bias throughout: a false NEGATIVE costs disk space, a false POSITIVE
/// destroys the user's data. Anything ambiguous must be kept.
RcloneFile f(String name, {DateTime? modTime, int size = 100}) => RcloneFile(
  name: name,
  path: 'backup/$name',
  isDir: false,
  size: size,
  modTime: modTime,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime(2026, 9, 9, 12);
  final old = now.subtract(const Duration(days: 60));
  final recent = now.subtract(const Duration(days: 3));

  group('isReplacedVersion', () {
    test('recognises both suffix shapes rclone can produce', () {
      // --suffix-keep-extension inserts before the extension; without it,
      // rclone appends. A config from an older build may hold either.
      expect(isReplacedVersion('report.replaced.pdf'), isTrue);
      expect(isReplacedVersion('report.pdf.replaced'), isTrue);
    });

    test('a file merely CONTAINING the word is not a version', () {
      // The suffix must be a whole dot-separated segment.
      for (final n in [
        'my.replacedparts.txt',
        'replacedstuff.txt',
        'the-replaced-file.txt',
        'notreplaced.txt',
      ]) {
        expect(isReplacedVersion(n), isFalse, reason: n);
      }
    });

    test('a LEADING segment named replaced is the file\'s own name', () {
      // `replaced.txt` is a file someone called "replaced". Deleting it because
      // of its name would be indefensible.
      expect(isReplacedVersion('replaced.txt'), isFalse);
      expect(isReplacedVersion('replaced'), isFalse);
    });

    test('an ordinary file is never a version', () {
      for (final n in ['report.pdf', 'a', 'a.b.c.d', 'photo.jpg', '']) {
        expect(isReplacedVersion(n), isFalse, reason: n);
      }
    });
  });

  group('liveNameFor', () {
    test('recovers the file a version belongs to', () {
      expect(liveNameFor('report.replaced.pdf'), 'report.pdf');
      expect(liveNameFor('report.pdf.replaced'), 'report.pdf');
      expect(liveNameFor('a.b.replaced.c'), 'a.b.c');
    });

    test('null for anything that is not a version', () {
      expect(liveNameFor('report.pdf'), isNull);
      expect(liveNameFor('replaced.txt'), isNull);
    });
  });

  group('prunableVersions', () {
    test('an old version whose live file still exists is prunable', () {
      final out = prunableVersions(
        entries: [
          f('report.pdf'),
          f('report.replaced.pdf', modTime: old),
        ],
        retentionDays: 30,
        now: now,
      );
      expect(out.map((e) => e.name), ['report.replaced.pdf']);
    });

    test('NEVER the live file itself, however old', () {
      // The single worst thing this could do.
      final out = prunableVersions(
        entries: [
          f('report.pdf', modTime: DateTime(2001)),
          f('photo.jpg', modTime: DateTime(2001)),
        ],
        retentionDays: 0,
        now: now,
      );
      expect(out, isEmpty);
    });

    test('NEVER the last copy in existence', () {
      // The current file was deleted at the source and the backup copied that
      // forward. This version is not a redundant old copy — it is the only copy
      // left, and it is exactly what the user will come looking for.
      final out = prunableVersions(
        entries: [f('deleted-at-source.replaced.pdf', modTime: old)],
        retentionDays: 30,
        now: now,
      );
      expect(
        out,
        isEmpty,
        reason: 'no live file of that name means this is the last copy',
      );
    });

    test('a version newer than the cutoff is kept', () {
      final out = prunableVersions(
        entries: [
          f('report.pdf'),
          f('report.replaced.pdf', modTime: recent),
        ],
        retentionDays: 30,
        now: now,
      );
      expect(out, isEmpty);
    });

    test('a version with NO modification time is kept', () {
      // Unknown age is not "old enough". A backend that omits modTime must not
      // cost the user their history.
      final out = prunableVersions(
        entries: [f('report.pdf'), f('report.replaced.pdf')],
        retentionDays: 30,
        now: now,
      );
      expect(out, isEmpty);
    });

    test('directories are never candidates', () {
      final out = prunableVersions(
        entries: [
          const RcloneFile(name: 'archive.replaced.d', path: 'x', isDir: true),
        ],
        retentionDays: 0,
        now: now,
      );
      expect(out, isEmpty);
    });

    test(
      'retention 0 prunes every version with a live file, and nothing else',
      () {
        final out = prunableVersions(
          entries: [
            f('a.txt'),
            f('a.replaced.txt', modTime: recent),
            f('orphan.replaced.txt', modTime: recent),
            f('b.txt', modTime: DateTime(2001)),
          ],
          retentionDays: 0,
          now: now,
        );
        expect(out.map((e) => e.name), ['a.replaced.txt']);
      },
    );

    test('a negative or absurd retention is clamped, not obeyed', () {
      // A corrupt preference must not turn into "delete everything".
      final entries = [f('a.txt'), f('a.replaced.txt', modTime: recent)];
      expect(
        prunableVersions(
          entries: entries,
          retentionDays: -9999,
          now: now,
        ).map((e) => e.name),
        ['a.replaced.txt'],
        reason: 'clamps to 0, which prunes a version with a live file',
      );
      expect(
        prunableVersions(entries: entries, retentionDays: 999999, now: now),
        isEmpty,
        reason: 'clamps to the longest window, which keeps a recent version',
      );
    });

    test('several versions of one file are handled independently', () {
      final out = prunableVersions(
        entries: [
          f('report.pdf'),
          f('report.replaced.pdf', modTime: old),
          f('report.pdf.replaced', modTime: recent),
        ],
        retentionDays: 30,
        now: now,
      );
      expect(out.map((e) => e.name), ['report.replaced.pdf']);
    });
  });

  group('prunableVersionsRecursive', () {
    RcloneFile at(String path, {DateTime? modTime}) => RcloneFile(
      name: path.split('/').last,
      path: path,
      isDir: false,
      size: 10,
      modTime: modTime,
    );

    test('A LIVE FILE IN ANOTHER FOLDER DOES NOT VOUCH FOR A VERSION', () {
      // The trap. prunableVersions decides "is this the last copy?" by looking
      // for a live file of that name in the SAME listing. Over a recursive
      // listing, a/report.pdf would vouch for b/report.replaced.pdf - and that
      // version, which is the only copy of b's report, would be deleted.
      final out = prunableVersionsRecursive(
        entries: [
          at('a/report.pdf'),
          at('b/report.replaced.pdf', modTime: old),
        ],
        retentionDays: 30,
        now: now,
      );
      expect(
        out,
        isEmpty,
        reason: 'b/ has no live report.pdf, so its version is the last copy',
      );
    });

    test('a version IS pruned when its live file sits beside it', () {
      final out = prunableVersionsRecursive(
        entries: [
          at('a/report.pdf'),
          at('a/report.replaced.pdf', modTime: old),
          at('b/other.txt'),
        ],
        retentionDays: 30,
        now: now,
      );
      expect(out.map((e) => e.path), ['a/report.replaced.pdf']);
    });

    test('folders are handled independently, not merged', () {
      final out = prunableVersionsRecursive(
        entries: [
          at('a/x.txt'),
          at('a/x.replaced.txt', modTime: old),
          at('b/x.txt'),
          at('b/x.replaced.txt', modTime: recent),
        ],
        retentionDays: 30,
        now: now,
      );
      expect(out.map((e) => e.path), ['a/x.replaced.txt']);
    });

    test('the root counts as a folder', () {
      final out = prunableVersionsRecursive(
        entries: [
          at('x.txt'),
          at('x.replaced.txt', modTime: old),
        ],
        retentionDays: 30,
        now: now,
      );
      expect(out.map((e) => e.path), ['x.replaced.txt']);
    });
  });

  group('parentOf', () {
    test('splits a path from its last segment', () {
      expect(parentOf('a/b/c.txt'), 'a/b');
      expect(parentOf('c.txt'), '');
      expect(parentOf(''), '');
    });
  });

  group('versionBytes', () {
    test('counts versions only, so the cost is visible', () {
      expect(
        versionBytes([
          f('a.txt', size: 1000),
          f('a.replaced.txt', size: 300),
          f('b.replaced.txt', size: 200),
        ]),
        500,
      );
    });

    test('an unknown size counts as zero rather than -1', () {
      expect(versionBytes([f('a.replaced.txt', size: -1)]), 0);
    });
  });

  group('BackupRetention', () {
    test('defaults to 30 days, which is one of the choices', () {
      expect(kRetentionDayChoices, contains(kDefaultRetentionDays));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(backupRetentionProvider), 30);
    });

    test('a chosen window survives a restart', () async {
      final first = ProviderContainer();
      await first.read(backupRetentionProvider.notifier).set(7);
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.read(backupRetentionProvider);
      await Future<void>.delayed(Duration.zero);
      expect(second.read(backupRetentionProvider), 7);
    });

    test('a corrupt stored value is clamped on read', () async {
      SharedPreferences.setMockInitialValues({'backup_retention_days': -50});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(backupRetentionProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(backupRetentionProvider), 0);
    });
  });
}
