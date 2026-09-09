import 'package:airclone/src/state/file_ops.dart';
import 'package:airclone/src/state/sync_preview.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dry run used to dispatch the real job with `DryRun` set and leave the
/// answer in the Transfers dock as a row saying "Done" beside a byte count. For
/// a Sync — the one mode that deletes — the number the dry run exists to produce
/// was nowhere on screen.
///
/// The buckets alone are not that answer either: the same difference means
/// different things under different flags, so these cover the mapping from "how
/// the two sides differ" to "what this transfer would therefore do".
CompareResult _result({
  List<String> missingOnDst = const [],
  List<String> missingOnSrc = const [],
  List<String> differ = const [],
  List<String> match = const [],
  List<String> error = const [],
}) => CompareResult(
  success: false,
  status: '',
  hashType: 'md5',
  match: match,
  missingOnSrc: missingOnSrc,
  missingOnDst: missingOnDst,
  differ: differ,
  error: error,
);

void main() {
  final full = _result(
    missingOnDst: ['new.txt'],
    missingOnSrc: ['gone1.txt', 'gone2.txt'],
    differ: ['changed.txt'],
    match: ['same1.txt', 'same2.txt'],
  );

  group('what each mode does with the same differences', () {
    test('sync deletes what the source does not have', () {
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.sync),
      );
      expect(p.wouldCreate, ['new.txt']);
      expect(p.wouldOverwrite, ['changed.txt']);
      expect(p.wouldDelete, ['gone1.txt', 'gone2.txt']);
      expect(p.unchanged, 2);
      expect(p.changesNothing, isFalse);
    });

    test('copy deletes nothing, however the sides differ', () {
      // missingOnSrc is a fact about the two folders; it only becomes a
      // deletion under Sync. Reporting it for Copy would invent a threat.
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.copy),
      );
      expect(p.wouldDelete, isEmpty);
      expect(p.wouldCreate, ['new.txt']);
    });

    test('move deletes nothing on the destination either', () {
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.move),
      );
      expect(p.wouldDelete, isEmpty);
    });
  });

  group('flags that change the outcome', () {
    test('skip existing means nothing is overwritten', () {
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.sync, skipExisting: true),
      );
      expect(p.wouldOverwrite, isEmpty);
      // Still deletes: --ignore-existing is about files present on both.
      expect(p.wouldDelete, hasLength(2));
    });

    test('keep replaced makes the overwrites recoverable', () {
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.sync, keepReplaced: true),
      );
      expect(p.overwritesRecoverable, isTrue);
    });

    test('skip newer is flagged as "some of these may not happen"', () {
      // Which ones is decided per file at run time; claiming to know would be
      // the preview lying precisely where it is trusted.
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.sync, skipNewer: true),
      );
      expect(p.someMayBeSkipped, isTrue);
      expect(p.wouldOverwrite, ['changed.txt']);
    });

    test('nothing to overwrite means nothing to hedge about', () {
      final p = previewFrom(
        _result(missingOnDst: ['new.txt']),
        const TransferOptions(mode: TransferMode.sync, skipNewer: true),
      );
      expect(p.someMayBeSkipped, isFalse);
    });
  });

  group('the delete cap', () {
    test('says the run would abort before it is started', () {
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.sync, maxDeleteFiles: 1),
      );
      expect(p.wouldAbortOnMaxDelete, isTrue);
    });

    test('a cap that is not exceeded is not a warning', () {
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.sync, maxDeleteFiles: 2),
      );
      expect(p.wouldAbortOnMaxDelete, isFalse);
    });

    test('no cap, no abort', () {
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.sync),
      );
      expect(p.wouldAbortOnMaxDelete, isFalse);
    });

    test('the cap is a sync-only concept, so copy ignores it', () {
      final p = previewFrom(
        full,
        const TransferOptions(mode: TransferMode.copy, maxDeleteFiles: 1),
      );
      expect(p.maxDeleteFiles, isNull);
      expect(p.wouldAbortOnMaxDelete, isFalse);
    });
  });

  test('identical folders change nothing', () {
    final p = previewFrom(
      _result(match: ['a', 'b']),
      const TransferOptions(mode: TransferMode.sync),
    );
    expect(p.changesNothing, isTrue);
    expect(p.unchanged, 2);
  });

  test('uncomparable files are reported, never counted as identical', () {
    final p = previewFrom(
      _result(match: ['a'], error: ['locked.db']),
      const TransferOptions(mode: TransferMode.sync),
    );
    expect(p.errors, ['locked.db']);
    expect(p.unchanged, 1);
  });

  group('previewConfig', () {
    test('carries the comparison mode so "differs" means the same thing', () {
      expect(previewConfig(const TransferOptions(compare: CompareMode.size)), {
        'SizeOnly': true,
      });
      expect(
        previewConfig(const TransferOptions(compare: CompareMode.checksum)),
        {'Checksum': true},
      );
    });

    test('carries nothing else — the default compares rclone\'s way', () {
      expect(previewConfig(const TransferOptions()), isEmpty);
      expect(
        previewConfig(const TransferOptions(compare: CompareMode.sizeModTime)),
        isEmpty,
      );
      // Performance and safety knobs change what happens to a difference, not
      // whether there is one, so they must not reach the comparison.
      expect(
        previewConfig(
          const TransferOptions(transfers: 8, maxDeleteFiles: 3, dryRun: true),
        ),
        isEmpty,
      );
    });
  });

  test('the preview compares under the transfer\'s own filters', () {
    // operations/check honours _filter. A preview given different rules than
    // the run reports a different set of deletions than the run performs.
    const o = TransferOptions(
      mode: TransferMode.sync,
      excludes: ['*.tmp'],
      includes: ['docs/**'],
    );
    final block = filterBlock(o);
    expect(block, isNotNull);
    expect(block!['ExcludeRule'], ['*.tmp']);
    expect(block['IncludeRule'], ['docs/**']);
  });
}
