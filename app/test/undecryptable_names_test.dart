import 'package:airclone/src/rclone/http_rclone_client.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/state/undecryptable_names.dart';
import 'package:airclone/src/ui/browser_pane.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A crypt remote whose password or salt does not match its data returns an
/// empty (or short) listing with HTTP 200 and no error. The engine says so once,
/// on its log, as a NOTICE — and a release build retains only ERROR/CRITICAL, so
/// that line used to be dropped before anything could act on it. A real user
/// concluded their backups had been deleted; the folder had six directories in
/// it. These tests hold the chain that now carries the fact to the pane.
///
/// The strings below are verbatim rclone 1.75.0 output.
void main() {
  group('isUndecryptableNameLine', () {
    test('matches the file and dir notices', () {
      expect(
        isUndecryptableNameLine(
          '2026/09/09 09:36:19 NOTICE: 5etumoc8orqj4ia13cu8c9tu58: Skipping '
          'undecryptable file name: bad PKCS#7 padding - too long',
        ),
        isTrue,
      );
      expect(
        isUndecryptableNameLine(
          '2026/09/09 09:47:06 NOTICE: o7mcf8m9bol7rajh36n5slbm18: Skipping '
          'undecryptable dir name: bad PKCS#7 padding - too long',
        ),
        isTrue,
      );
    });

    test('ignores every other line the engine writes', () {
      expect(
        isUndecryptableNameLine(
          '2026/09/09 09:34:48 NOTICE: FM2449-RSYNCNET: No host key validation '
          'is being performed.',
        ),
        isFalse,
      );
      expect(isUndecryptableNameLine('INFO  : big.iso: Copied (new)'), isFalse);
      expect(isUndecryptableNameLine(''), isFalse);
    });

    test('is NOT a failure line, so it is counted rather than logged', () {
      // The two predicates are deliberately disjoint: this is a recovered,
      // per-entry condition, and letting it into the diagnostics ring per name
      // would spend the whole budget restating one fact.
      const line =
          'NOTICE: abc123: Skipping undecryptable file name: bad PKCS#7 padding';
      expect(isUndecryptableNameLine(line), isTrue);
      expect(isEngineFailureLine(line), isFalse);
    });
  });

  group('undecryptableNameCount', () {
    setUp(resetUndecryptableNameCount);

    test('is monotonic, so a caller can take a delta across one request', () {
      final before = undecryptableNameCount;
      noteUndecryptableName();
      noteUndecryptableName();
      expect(undecryptableNameCount - before, 2);
    });
  });

  group('hiddenForBackend', () {
    test('reports the delta for a crypt remote', () {
      expect(hiddenForBackend('crypt', 4, 10), 6);
    });

    test('reports none when nothing was skipped during the window', () {
      expect(hiddenForBackend('crypt', 7, 7), 0);
    });

    test('attributes nothing to a backend that cannot produce the notice', () {
      // Another pane (or a folder preview) listing a broken crypt inside the
      // same window must not make an sftp folder claim entries are hidden.
      expect(hiddenForBackend('sftp', 0, 6), 0);
      expect(hiddenForBackend('local', 0, 6), 0);
      expect(hiddenForBackend('union', 0, 6), 0);
    });
  });

  group('BrowserPane', () {
    Widget host(BrowserState state) => ProviderScope(
      overrides: [browserAProvider.overrideWith(() => _FixedBrowser(state))],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: BrowserPane(index: 0)),
      ),
    );

    testWidgets('an all-hidden listing does not claim the folder is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const BrowserState(
            remote: Remote(name: 'vault', type: 'crypt', fs: 'vault:'),
            hiddenUndecryptable: 6,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Empty folder'), findsNothing);
      expect(find.text('6 items hidden'), findsOneWidget);
    });

    testWidgets('a genuinely empty folder still says so', (tester) async {
      await tester.pumpWidget(
        host(
          const BrowserState(
            remote: Remote(name: 'vault', type: 'crypt', fs: 'vault:'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Empty folder'), findsOneWidget);
    });
  });
}

/// A pane whose state is fixed — the listing has already "arrived", so the
/// render can be asserted without an engine.
class _FixedBrowser extends BrowserController {
  _FixedBrowser(this._state);
  final BrowserState _state;
  @override
  BrowserState build() => _state;
}
