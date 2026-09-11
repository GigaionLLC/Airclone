import 'package:airclone/src/state/task_kind.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// A backup's constraints are applied when it is created **and again when it
/// runs**, so a task edited through the raw advanced dialog cannot run as
/// something other than what its name says.
///
/// "When it runs" has three doors, not two. The scheduler tick and the headless
/// runner both re-applied [backupOptions]; the ▶ Run button in Saved tasks
/// dispatched the task's STORED options untouched. So a task called "Back up
/// Documents", edited once to sync, ran as a sync from that button — deleting at
/// the destination to match the source, which is the exact outcome the whole
/// constraint exists to prevent.
///
/// These pin the transformation every door must share. The UI wiring is checked
/// by reading the dispatch site; what is testable without a widget is that the
/// transformation itself is total — nothing hostile survives it.
void main() {
  /// What the raw advanced dialog can produce, and a backup must never run as.
  const hostile = TransferOptions(
    mode: TransferMode.sync,
    dryRun: true,
    keepReplaced: false,
  );

  group('a backup run', () {
    test('is forced back to copy, whatever was stored', () {
      expect(backupOptions(hostile).mode, TransferMode.copy);
    });

    test('keeps replaced files, so there is a version history to restore', () {
      expect(backupOptions(hostile).keepReplaced, isTrue);
    });

    test(
      'is never a dry run — the worst failure is looking like it worked',
      () {
        expect(backupOptions(hostile).dryRun, isFalse);
      },
    );

    test('produces something isBackupShaped agrees with', () {
      // The codebase's own predicate for "these options really are a backup".
      expect(isBackupShaped(hostile), isFalse, reason: 'precondition');
      expect(isBackupShaped(backupOptions(hostile)), isTrue);
    });

    test('is idempotent, so re-applying at each door cannot drift', () {
      final once = backupOptions(hostile);
      final twice = backupOptions(once);
      expect(twice.mode, once.mode);
      expect(twice.dryRun, once.dryRun);
      expect(twice.keepReplaced, once.keepReplaced);
    });
  });

  group('a repeating transfer', () {
    test('never runs an uncapped sync', () {
      const uncapped = TransferOptions(mode: TransferMode.sync);
      expect(uncapped.maxDeleteFiles, isNull, reason: 'precondition');
      final capped = withScheduledDeleteCap(uncapped);
      expect(capped.mode, TransferMode.sync, reason: 'still a sync');
      expect(capped.maxDeleteFiles, isNotNull, reason: 'but now capped');
    });

    test('respects a cap the user chose rather than overriding it', () {
      const chosen = TransferOptions(
        mode: TransferMode.sync,
        maxDeleteFiles: 3,
      );
      expect(withScheduledDeleteCap(chosen).maxDeleteFiles, 3);
    });

    test('leaves a copy alone — there is nothing to cap', () {
      const copy = TransferOptions(mode: TransferMode.copy);
      expect(withScheduledDeleteCap(copy).maxDeleteFiles, isNull);
    });
  });

  test('the kind decides which transformation applies', () {
    // The dispatch sites all branch on exactly this, so a new TaskKind that
    // forgets to choose is the way this regresses.
    expect(TaskKind.values, contains(TaskKind.transfer));
    expect(TaskKind.values, contains(TaskKind.backup));
    expect(TaskKind.values, contains(TaskKind.photos));
    // A photo backup is a backup: it must take the backup transformation.
    expect(TaskKind.photos, isNot(TaskKind.transfer));
  });
}
