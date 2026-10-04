import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/ui/browser_pane.dart';
import 'package:airclone/src/ui/pane_search_box.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _remote = Remote(name: 'test', type: 'local', fs: '/');
const _entries = [
  RcloneFile(name: 'holiday.txt', path: 'holiday.txt', isDir: false, size: 4),
  RcloneFile(name: 'work.txt', path: 'work.txt', isDir: false, size: 4),
];

/// A pane already listed, with whatever search state the test starts from.
/// Records scope changes instead of scanning.
class _Pane extends BrowserController {
  _Pane(this.initial);
  final BrowserState initial;
  final scopes = <SearchScope>[];

  @override
  BrowserState build() => initial;

  @override
  void setSearchScope(SearchScope scope) => scopes.add(scope);
}

SearchHit _hit(String abs, {bool dir = false}) {
  final slash = abs.lastIndexOf('/');
  final parent = slash < 0 ? '' : abs.substring(0, slash);
  return SearchHit(
    entry: RcloneFile(name: abs.split('/').last, path: abs, isDir: dir),
    parentPath: parent,
    relParent: parent,
  );
}

Future<_Pane> _pumpPane(WidgetTester tester, BrowserState state) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  late _Pane pane;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [browserAProvider.overrideWith(() => pane = _Pane(state))],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: BrowserPane(index: 0)),
      ),
    ),
  );
  await tester.pump();
  return pane;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the toolbar carries one search box, hinting This folder', (
    tester,
  ) async {
    await _pumpPane(
      tester,
      const BrowserState(remote: _remote, entries: _entries),
    );
    expect(find.byType(PaneSearchBox), findsOneWidget);
    expect(find.text('Search this folder'), findsOneWidget);
    // Nothing typed: no strip, no subfolders row.
    expect(find.byType(SearchStrip), findsNothing);
    expect(find.byType(SearchSubfoldersRow), findsNothing);
  });

  testWidgets('a This-folder query shows the scope switch, a count, and the '
      'way into subfolders - also under "No matches"', (tester) async {
    final pane = await _pumpPane(
      tester,
      const BrowserState(remote: _remote, entries: _entries, filter: 'nope'),
    );
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('This folder'), findsOneWidget);
    expect(find.text('Subfolders'), findsOneWidget);
    expect(find.text('0 in this folder'), findsOneWidget);
    expect(find.text('Search subfolders for "nope"'), findsOneWidget);

    await tester.tap(find.text('Search subfolders for "nope"'));
    await tester.pump();
    expect(pane.scopes, [SearchScope.subfolders]);
  });

  testWidgets('Subfolders results show each match with its folder, and no '
      'subfolders row', (tester) async {
    await _pumpPane(
      tester,
      BrowserState(
        remote: _remote,
        entries: _entries,
        filter: 'beach',
        search: PaneSearch(
          scope: SearchScope.subfolders,
          status: SearchScanStatus.done,
          scanned: 40,
          hits: [_hit('Photos/2024/beach.jpg'), _hit('beach notes.txt')],
        ),
      ),
    );
    expect(find.text('beach.jpg'), findsOneWidget);
    expect(find.text('Photos/2024'), findsOneWidget);
    // A match in the search folder itself is labelled with that folder.
    expect(find.text('beach notes.txt'), findsOneWidget);
    expect(find.text('2 matches in 40 items'), findsOneWidget);
    expect(find.byType(SearchSubfoldersRow), findsNothing);
    // The folder's own listing is not what is on screen.
    expect(find.text('work.txt'), findsNothing);
  });

  testWidgets('a scan in progress says what it is scanning and offers Cancel', (
    tester,
  ) async {
    await _pumpPane(
      tester,
      BrowserState(
        remote: _remote,
        path: 'Movies',
        entries: _entries,
        search: PaneSearch(
          scope: SearchScope.subfolders,
          status: SearchScanStatus.scanning,
          startedAt: DateTime.now(),
        ),
      ),
    );
    expect(find.textContaining('Scanning Movies'), findsWidgets);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets(
    'a crypt scan that skipped names says results may be incomplete',
    (tester) async {
      await _pumpPane(
        tester,
        BrowserState(
          remote: _remote,
          entries: _entries,
          filter: 'x',
          search: const PaneSearch(
            scope: SearchScope.subfolders,
            status: SearchScanStatus.done,
            scanned: 3,
            hiddenNames: 2,
          ),
        ),
      );
      expect(find.textContaining('could not be decrypted'), findsOneWidget);
      expect(find.text('No matches in subfolders.'), findsOneWidget);
    },
  );

  group('the box itself', () {
    Future<ProviderContainer> pumpBox(
      WidgetTester tester, {
      bool tv = false,
    }) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final box = Column(
        children: const [PaneSearchBox(index: 0), SearchScopeToggle(index: 0)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: tv ? TvDpadEscape(child: box) : box),
          ),
        ),
      );
      return container;
    }

    testWidgets('binds the Ctrl+F focus node and types into the filter', (
      tester,
    ) async {
      final c = await pumpBox(tester);
      final node = c.read(paneFilterFocusProvider(0));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode, same(node));
      await tester.enterText(find.byType(TextField), 'abc');
      expect(c.read(browserAProvider).filter, 'abc');
    });

    testWidgets('follows the filter when it changes elsewhere (a tab switch, '
        'a navigation)', (tester) async {
      final c = await pumpBox(tester);
      c.read(browserAProvider.notifier).setFilter('from elsewhere');
      await tester.pump();
      expect(find.text('from elsewhere'), findsOneWidget);
      c.read(browserAProvider.notifier).setFilter('');
      await tester.pump();
      expect(find.text('from elsewhere'), findsNothing);
    });

    testWidgets('Esc clears the text first, then lets go of the field', (
      tester,
    ) async {
      final c = await pumpBox(tester);
      final node = c.read(paneFilterFocusProvider(0));
      await tester.enterText(find.byType(TextField), 'abc');
      expect(node.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.read(browserAProvider).filter, isEmpty);
      expect(node.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });

    testWidgets('on a TV, DOWN from the box lands on the scope switch', (
      tester,
    ) async {
      final c = await pumpBox(tester, tv: true);
      final node = c.read(paneFilterFocusProvider(0));
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(node.hasFocus, isFalse);
      expect(
        focused?.findAncestorWidgetOfExactType<SearchScopeToggle>(),
        isNotNull,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
