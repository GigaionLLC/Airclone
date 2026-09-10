import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/ui/browser_pane.dart';
import 'package:airclone/src/ui/file_row.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:shared_preferences/shared_preferences.dart';

/// The invariant this file guards (tree-view plan §2.2, and the v0.5.0 race it
/// descends from): pane operations used to build their target as
/// `state.path + entry name`, so a listing that did not match `state.path`
/// produced a preview 404 and a copy that failed "object not found". A tree
/// holds MANY folders' listings at once while `state.path` stays the root — so
/// every operation started from a tree row must derive its path from that
/// row's own parent. These tests act on a row three levels deep and assert the
/// RPC that reaches rclone names the deep path while `state.path` is `''`.
///
/// Listings are answered per folder so the fake is a small filesystem:
///
///     /            A/
///     A/           B/  x.txt
///     A/B/         C/  y.txt
///     A/B/C/       deep.txt
class _TreeClient implements RcloneClient {
  _TreeClient({this.otherRootNames = const []});

  /// What the OTHER pane's remote lists at its root (collision fodder).
  final List<String> otherRootNames;

  final calls = <({String method, Map<String, dynamic>? params})>[];

  static const _fs = <String, List<Map<String, dynamic>>>{
    '': [
      {'Name': 'A', 'Path': 'A', 'IsDir': true, 'Size': -1},
    ],
    'A': [
      {'Name': 'B', 'Path': 'A/B', 'IsDir': true, 'Size': -1},
      {'Name': 'x.txt', 'Path': 'A/x.txt', 'IsDir': false, 'Size': 1},
    ],
    'A/B': [
      {'Name': 'C', 'Path': 'A/B/C', 'IsDir': true, 'Size': -1},
      {'Name': 'y.txt', 'Path': 'A/B/y.txt', 'IsDir': false, 'Size': 2},
    ],
    'A/B/C': [
      {'Name': 'deep.txt', 'Path': 'A/B/C/deep.txt', 'IsDir': false, 'Size': 3},
    ],
  };

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    if (method == 'operations/list') {
      if (params?['fs'] == 'other:') {
        return {
          'list': [
            for (final n in otherRootNames)
              {'Name': n, 'Path': n, 'IsDir': false, 'Size': 9},
          ],
        };
      }
      final path = (params?['remote'] ?? '') as String;
      return {'list': _fs[path] ?? const []};
    }
    // stat → no IsDir ⇒ a file ⇒ operations/copyfile|movefile; everything else
    // is an async job handle.
    return {'jobid': 1};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._client);
  final RcloneClient _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);
}

const _remote = Remote(name: 'gd', type: 'drive', fs: 'gd:');
const _other = Remote(name: 'other', type: 'drive', fs: 'other:');

/// Pumps a full-width pane A rooted at [_remote], switched to the tree view
/// with A, A/B and A/B/C expanded — so `deep.txt` is on screen three levels
/// below a `state.path` that is still the remote root.
Future<ProviderContainer> _pumpDeepTree(
  WidgetTester tester,
  _TreeClient client,
) async {
  final container = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: BrowserPane(index: 0)),
      ),
    ),
  );
  final ctrl = container.read(browserAProvider.notifier);
  await ctrl.open(_remote);
  ctrl.setViewMode(ViewMode.tree);
  await ctrl.expandNode('A');
  await ctrl.expandNode('A/B');
  await ctrl.expandNode('A/B/C');
  await tester.pumpAndSettle();
  expect(find.text('deep.txt'), findsOneWidget);
  // The precondition the whole file is about.
  expect(container.read(browserAProvider).path, '');
  return container;
}

/// Unmounts the pane and disposes [container] INSIDE the test body. A
/// dispatched transfer starts the jobs poller (a periodic timer that only a
/// container dispose cancels), and the framework checks for pending timers
/// before `addTearDown` callbacks run.
Future<void> _unmount(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
}

/// Opens the ⋯ menu of the row named [name].
///
/// The row's InkWell registers `onDoubleTap`, whose recognizer HOLDS the
/// gesture arena for the double-tap window, so the button's tap resolves only
/// when that ~300 ms timer fires — and a timer schedules no frame, so
/// `pumpAndSettle` alone returns before the menu exists.
Future<void> _openRowMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(FileRow)),
      matching: find.byTooltip('Actions'),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'rename from a row three levels deep targets the row\'s own parent, '
    'not state.path',
    (tester) async {
      final client = _TreeClient();
      final container = await _pumpDeepTree(tester, client);

      await _openRowMenu(tester, 'deep.txt');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'renamed.txt');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final mv = client.calls.where((c) => c.method == 'operations/movefile');
      expect(mv, hasLength(1), reason: 'exactly one rename RPC');
      expect(mv.single.params!['srcRemote'], 'A/B/C/deep.txt');
      expect(mv.single.params!['dstRemote'], 'A/B/C/renamed.txt');
      // The rename re-listed the row's OWN folder, not the root.
      final relists = client.calls
          .where((c) => c.method == 'operations/list')
          .map((c) => c.params!['remote'])
          .toList();
      expect(relists.last, 'A/B/C');
      await _unmount(tester, container);
    },
  );

  testWidgets('delete from a deep row deletes the deep path', (tester) async {
    final client = _TreeClient();
    final container = await _pumpDeepTree(tester, client);

    await _openRowMenu(tester, 'deep.txt');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // The confirm dialog's commit button carries the same label.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    final del = client.calls.where((c) => c.method == 'operations/deletefile');
    expect(del, hasLength(1));
    expect(del.single.params!['remote'], 'A/B/C/deep.txt');
    // Never the root-relative name the old code would have built.
    expect(client.calls.any((c) => c.params?['remote'] == 'deep.txt'), isFalse);
    await _unmount(tester, container);
  });

  testWidgets(
    'a selection spanning two folders copies each from its own parent and '
    'asks once per source folder',
    (tester) async {
      // The other pane holds both names, so EACH group collides.
      final client = _TreeClient(otherRootNames: const ['x.txt', 'y.txt']);
      final container = await _pumpDeepTree(tester, client);
      final ctrlB = container.read(browserBProvider.notifier);
      await ctrlB.open(_other);
      await tester.pumpAndSettle();

      final ctrl = container.read(browserAProvider.notifier);
      ctrl.toggleTreeSelect('A/x.txt');
      ctrl.toggleTreeSelect('A/B/y.txt');
      await tester.pumpAndSettle();
      expect(container.read(browserAProvider).tree.selected, {
        'A/x.txt',
        'A/B/y.txt',
      });

      await tester.tap(find.byTooltip('Copy to other pane'));
      await tester.pumpAndSettle();
      // One prompt per source folder (plan §4.D): group A first…
      expect(find.text('1 of 1 already exist here'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      // …then group A/B.
      expect(find.text('1 of 1 already exist here'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      final copies = client.calls
          .where((c) => c.method == 'operations/copyfile')
          .map((c) => '${c.params!['srcRemote']} -> ${c.params!['dstRemote']}')
          .toList();
      expect(copies, ['A/x.txt -> x.txt', 'A/B/y.txt -> y.txt']);
      // Nothing was ever addressed relative to the root.
      expect(
        copies.any((s) => s.startsWith('x.txt') || s.startsWith('y.txt')),
        isFalse,
      );
      await _unmount(tester, container);
    },
  );

  testWidgets('Left collapses the focused folder and Right re-expands it '
      'from the cache (plan §4.E)', (tester) async {
    final client = _TreeClient();
    final container = await _pumpDeepTree(tester, client);
    // Click the A row: selects it, puts the cursor on it, focuses the tree.
    await tester.tap(find.text('A'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(container.read(browserAProvider).tree.cursor, 'A');
    final listingsBefore = client.calls
        .where((c) => c.method == 'operations/list')
        .length;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      container.read(browserAProvider).tree.expanded,
      isNot(contains('A')),
    );
    expect(find.text('deep.txt'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(container.read(browserAProvider).tree.expanded, contains('A'));
    expect(find.text('x.txt'), findsOneWidget);
    // Re-expanding came from the cache: no new listing.
    expect(
      client.calls.where((c) => c.method == 'operations/list').length,
      listingsBefore,
    );
    await _unmount(tester, container);
  });

  testWidgets(
    'a deep tree selection never surfaces through selectedEntries (so a '
    'consumer that assumes state.path cannot act on it)',
    (tester) async {
      final client = _TreeClient();
      final container = await _pumpDeepTree(tester, client);
      final ctrl = container.read(browserAProvider.notifier);
      ctrl.toggleTreeSelect('A/B/C/deep.txt');
      final st = container.read(browserAProvider);
      expect(st.tree.selected, {'A/B/C/deep.txt'});
      expect(st.selectedEntries, isEmpty);
      expect(st.selected, isEmpty);
      await _unmount(tester, container);
    },
  );
}
