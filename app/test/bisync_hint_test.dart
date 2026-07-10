import 'package:airclone/src/ui/jobs_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('looksLikeBisyncNeedsResync', () {
    test('matches real-looking rclone "lost prior listing" failures', () {
      // The canonical phrasings rclone emits when its baseline is gone. Note
      // "Path1"/"Path2" are spliced between "prior" and "listing", so a literal
      // "prior listing" substring match would miss these — the matcher must not.
      expect(
        looksLikeBisyncNeedsResync('cannot find prior Path1 listing...'),
        isTrue,
      );
      expect(
        looksLikeBisyncNeedsResync(
          'Bisync critical error: cannot find prior Path1 or Path2 listings',
        ),
        isTrue,
      );
    });

    test('matches the "--resync to recover" recovery instruction', () {
      expect(
        looksLikeBisyncNeedsResync('...run bisync with --resync...'),
        isTrue,
      );
      expect(
        looksLikeBisyncNeedsResync(
          'Bisync aborted. Must run --resync to recover.',
        ),
        isTrue,
      );
    });

    test('is case-insensitive', () {
      expect(
        looksLikeBisyncNeedsResync('CANNOT FIND PRIOR PATH1 LISTING'),
        isTrue,
      );
      expect(
        looksLikeBisyncNeedsResync('Try Running Bisync Again With --RESYNC'),
        isTrue,
      );
    });

    test('does not match generic errors that merely mention sync', () {
      // A bare one-way sync failure has neither the "--resync" flag token nor a
      // "prior … listing" pair, so it must not trigger the bisync hint.
      expect(
        looksLikeBisyncNeedsResync('sync failed: connection refused'),
        isFalse,
      );
      expect(
        looksLikeBisyncNeedsResync('directory not found on sync target'),
        isFalse,
      );
    });

    test('does not match a "prior" or "listing" word in isolation', () {
      // Requires both words together — one alone is not the baseline signal.
      expect(
        looksLikeBisyncNeedsResync('permission denied on prior run'),
        isFalse,
      );
      expect(
        looksLikeBisyncNeedsResync('failed to read directory listing'),
        isFalse,
      );
    });

    test('does not match an empty error string', () {
      expect(looksLikeBisyncNeedsResync(''), isFalse);
    });
  });
}
