import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/ui/browser_pane.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _entries = [
  RcloneFile(name: 'folder', path: 'folder', isDir: true),
  RcloneFile(name: 'file.txt', path: 'file.txt', isDir: false, size: 42),
];

/// A browser whose state is a populated listing — reproduces the "blank pane"
/// render bug without needing a live engine.
class _FakeBrowser extends BrowserController {
  @override
  BrowserState build() => const BrowserState(
    remote: Remote(name: 'test', type: 'local', fs: '/'),
    entries: _entries,
  );
}

/// Same listing, rendered in the grid view mode (alpha.7).
class _FakeGridBrowser extends BrowserController {
  @override
  BrowserState build() => const BrowserState(
    remote: Remote(name: 'test', type: 'local', fs: '/'),
    entries: _entries,
    viewMode: ViewMode.grid,
  );
}

/// One image with a known date — exercises the media gallery + date grouping.
class _FakeMediaBrowser extends BrowserController {
  @override
  BrowserState build() => BrowserState(
    remote: const Remote(name: 'test', type: 'local', fs: '/'),
    entries: [
      RcloneFile(
        name: 'pic.jpg',
        path: 'pic.jpg',
        isDir: false,
        size: 1000,
        modTime: DateTime(2026, 6, 18),
      ),
    ],
    viewMode: ViewMode.media,
  );
}

void main() {
  testWidgets('BrowserPane renders a loaded listing without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [browserAProvider.overrideWith(_FakeBrowser.new)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: BrowserPane(index: 0)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('file.txt'), findsOneWidget);
  });

  testWidgets('BrowserPane renders the grid view without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [browserAProvider.overrideWith(_FakeGridBrowser.new)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: BrowserPane(index: 0)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('file.txt'), findsOneWidget);
  });

  testWidgets('BrowserPane renders the media gallery without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [browserAProvider.overrideWith(_FakeMediaBrowser.new)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: BrowserPane(index: 0)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The pinned day header proves grouping rendered.
    expect(find.text('Jun 18, 2026'), findsOneWidget);
  });
}
