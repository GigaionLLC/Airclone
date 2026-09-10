import 'dart:async';

import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/ui/column_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:shared_preferences/shared_preferences.dart';

/// Answers `operations/list` per folder and records every folder listed, in
/// order. With [manual] on, each listing is left pending so a test can decide
/// which response lands first (the superseded-guard cases).
class _Client implements RcloneClient {
  _Client(this.fs);

  final Map<String, List<Map<String, dynamic>>> fs;
  final listed = <String>[];
  final pending = <Completer<Map<String, dynamic>>>[];
  bool manual = false;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    if (method == 'operations/list') {
      final path = (params?['remote'] ?? '') as String;
      listed.add(path);
      if (manual) {
        final c = Completer<Map<String, dynamic>>();
        pending.add(c);
        return c.future;
      }
      return Future.value({'list': fs[path] ?? const []});
    }
    return Future.value(<String, dynamic>{});
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

Map<String, dynamic> _d(String path) => {
  'Name': path.split('/').last,
  'Path': path,
  'IsDir': true,
  'Size': -1,
};
Map<String, dynamic> _f(String path, [int size = 1]) => {
  'Name': path.split('/').last,
  'Path': path,
  'IsDir': false,
  'Size': size,
};

/// Root: A/ b.txt     A: B/ x.txt     A/B: y.txt
final _fs = <String, List<Map<String, dynamic>>>{
  '': [_d('A'), _f('b.txt')],
  'A': [_d('A/B'), _f('A/x.txt', 5)],
  'A/B': [_f('A/B/y.txt')],
};

const _remote = Remote(name: 'gd', type: 'drive', fs: 'gd:');
const _other = Remote(name: 'od', type: 'onedrive', fs: 'od:');

/// A pane opened on [_remote] in tree mode, root listed.
Future<(ProviderContainer, BrowserController, _Client)> _open() async {
  final client = _Client(_fs);
  final container = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
    ],
  );
  addTearDown(container.dispose);
  final ctrl = container.read(browserAProvider.notifier);
  await ctrl.open(_remote);
  ctrl.setViewMode(ViewMode.tree);
  expect(client.listed, ['']);
  return (container, ctrl, client);
}

List<String> _kids(BrowserController ctrl, String folder) => [
  for (final f in ctrl.state.tree.children[folder] ?? []) f.name,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('expanding a folder issues exactly one listing; collapsing then '
      're-expanding issues none (cached)', () async {
    final (_, ctrl, client) = await _open();
    await ctrl.expandNode('A');
    expect(client.listed, ['', 'A']);
    expect(_kids(ctrl, 'A'), ['B', 'x.txt']);
    expect(ctrl.state.tree.expanded, {'A'});

    ctrl.collapseNode('A');
    expect(ctrl.state.tree.expanded, isEmpty);
    expect(_kids(ctrl, 'A'), ['B', 'x.txt'], reason: 'cache kept');

    await ctrl.expandNode('A');
    expect(client.listed, ['', 'A'], reason: 'no second listing');
    await ctrl.toggleExpand('A');
    await ctrl.toggleExpand('A');
    expect(client.listed, ['', 'A']);
  });

  test('a rapid expand / collapse / expand while the listing is in flight '
      'issues one listing and renders it', () async {
    final (_, ctrl, client) = await _open();
    client.manual = true;
    final first = ctrl.expandNode('A');
    ctrl.collapseNode('A');
    final again = ctrl.expandNode('A');
    expect(client.listed, ['', 'A'], reason: 'the in-flight load is reused');
    expect(ctrl.state.tree.loading, {'A'});
    client.pending.single.complete({'list': _fs['A']!});
    await first;
    await again;
    expect(_kids(ctrl, 'A'), ['B', 'x.txt']);
    expect(ctrl.state.tree.loading, isEmpty);
    expect(ctrl.state.tree.expanded, {'A'});
  });

  test('per-node superseded guard: a reload issued after an expand wins even '
      'when the expand\'s (older) response lands last', () async {
    final (_, ctrl, client) = await _open();
    client.manual = true;
    final expand = ctrl.expandNode('A'); // listing #1, pending
    final reload = ctrl.reloadTreeFolder('A'); // listing #2, pending
    expect(client.listed, ['', 'A', 'A']);
    // The NEWER listing lands first…
    client.pending[1].complete({
      'list': [_f('A/new.txt')],
    });
    await reload;
    expect(_kids(ctrl, 'A'), ['new.txt']);
    // …then the older one — which must be dropped, not rendered over it.
    client.pending[0].complete({
      'list': [_f('A/old.txt')],
    });
    await expand;
    expect(_kids(ctrl, 'A'), ['new.txt']);
    expect(ctrl.state.tree.loading, isEmpty);
  });

  test('opening another remote strands a listing in flight for the old one '
      'and empties the forest', () async {
    final (_, ctrl, client) = await _open();
    client.manual = true;
    final expand = ctrl.expandNode('A');
    final pendingA = client.pending.single;
    client.manual = false;
    await ctrl.open(_other);
    expect(ctrl.state.tree.children, isEmpty);
    expect(ctrl.state.tree.expanded, isEmpty);
    pendingA.complete({'list': _fs['A']!});
    await expand;
    expect(ctrl.state.tree.children, isEmpty, reason: 'stale listing dropped');
  });

  test('refresh re-lists the root and every VISIBLE expanded folder, and '
      'forgets the listings of folders that are not on screen', () async {
    final (_, ctrl, client) = await _open();
    await ctrl.expandNode('A');
    await ctrl.expandNode('A/B');
    expect(client.listed, ['', 'A', 'A/B']);
    // Hide A/B behind a collapsed A: still expanded, no longer visible.
    ctrl.collapseNode('A');
    ctrl.expandNode('A'); // cached ⇒ no listing
    ctrl.collapseNode('A');
    client.listed.clear();
    await ctrl.refresh();
    // Root only: A is collapsed, so neither A nor A/B is on screen.
    expect(client.listed, ['']);
    expect(ctrl.state.tree.children.keys, isEmpty);
    // Now with A open again: root + A, and A/B (visible under A) too.
    await ctrl.expandNode('A'); // cache was dropped ⇒ one listing
    client.listed.clear();
    await ctrl.refresh();
    expect(client.listed.toSet(), {'', 'A', 'A/B'});
    expect(_kids(ctrl, 'A/B'), ['y.txt']);
  });

  test('switching tree → list → tree keeps the expansion set', () async {
    final (_, ctrl, client) = await _open();
    await ctrl.expandNode('A');
    await ctrl.expandNode('A/B');
    ctrl.setViewMode(ViewMode.list);
    expect(ctrl.state.tree.expanded, {'A', 'A/B'});
    ctrl.setViewMode(ViewMode.grid);
    ctrl.setViewMode(ViewMode.tree);
    expect(ctrl.state.tree.expanded, {'A', 'A/B'});
    expect(client.listed, ['', 'A', 'A/B'], reason: 'nothing re-listed');
  });

  test('the selection is carried across modes where it can be: root-level '
      'rows both ways, and a deep tree selection dropped', () async {
    final (_, ctrl, _) = await _open();
    ctrl.setViewMode(ViewMode.list);
    ctrl.toggleSelect('b.txt');
    ctrl.setViewMode(ViewMode.tree);
    expect(ctrl.state.selected, isEmpty);
    expect(ctrl.state.tree.selected, {'b.txt'});

    await ctrl.expandNode('A');
    ctrl.toggleTreeSelect('A/x.txt');
    expect(ctrl.state.tree.selected, {'b.txt', 'A/x.txt'});
    expect(ctrl.state.selectedEntries, isEmpty, reason: 'never in tree mode');
    expect(ctrl.state.selectionCount, 2);
    expect(ctrl.state.selectedTreeRows.map((r) => r.parentPath), ['', 'A']);

    ctrl.setViewMode(ViewMode.list);
    expect(ctrl.state.selected, {'b.txt'});
    expect(ctrl.state.tree.selected, isEmpty);
  });

  test('type-to-jump follows into the tree: selectOnly / toggleSelect on a '
      'root-level name land in the tree selection as full paths', () async {
    final (_, ctrl, _) = await _open();
    ctrl.selectOnly('b.txt');
    expect(ctrl.state.selected, isEmpty);
    expect(ctrl.state.tree.selected, {'b.txt'});
    expect(ctrl.state.tree.cursor, 'b.txt');
    ctrl.toggleSelect('A');
    expect(ctrl.state.tree.selected, {'b.txt', 'A'});
    ctrl.clearSelection();
    expect(ctrl.state.tree.selected, isEmpty);
  });

  test('collapsing a folder drops the selection beneath it and lifts the '
      'cursor to the folder', () async {
    final (_, ctrl, _) = await _open();
    await ctrl.expandNode('A');
    await ctrl.expandNode('A/B');
    ctrl.toggleTreeSelect('b.txt');
    ctrl.toggleTreeSelect('A/x.txt');
    ctrl.selectTreeOnly('A/B/y.txt');
    ctrl.toggleTreeSelect('b.txt');
    expect(ctrl.state.tree.selected, {'A/B/y.txt', 'b.txt'});
    ctrl.setTreeCursor('A/B/y.txt');
    ctrl.collapseNode('A');
    expect(ctrl.state.tree.selected, {'b.txt'});
    expect(ctrl.state.tree.cursor, 'A');
  });

  test('selectAll in tree mode selects every entry row on screen and nothing '
      'inside a collapsed folder', () async {
    final (_, ctrl, _) = await _open();
    await ctrl.expandNode('A');
    await ctrl.expandNode('A/B');
    ctrl.collapseNode('A/B');
    ctrl.selectAll();
    expect(ctrl.state.tree.selected, {'A', 'A/B', 'A/x.txt', 'b.txt'});
    ctrl.setFilter('x.t');
    ctrl.selectAll();
    // A stays because x.txt beneath it matches; A/B and b.txt do not.
    expect(ctrl.state.tree.selected, {'A', 'A/x.txt'});
  });

  test(
    'sorting sorts within each parent: cached listings re-sort too',
    () async {
      final (_, ctrl, _) = await _open();
      await ctrl.expandNode('A');
      ctrl.setSort(SortKey.name); // already name asc ⇒ flips to desc
      expect(ctrl.state.ascending, isFalse);
      // Folders stay first regardless; files reverse within their folder.
      expect(_kids(ctrl, 'A'), ['B', 'x.txt']);
      ctrl.setSort(SortKey.size);
      expect(ctrl.state.sortKey, SortKey.size);
      expect(_kids(ctrl, 'A'), ['B', 'x.txt']);
    },
  );

  test('navigating keeps the forest (keys are full paths) but drops the '
      'tree selection', () async {
    final (_, ctrl, client) = await _open();
    await ctrl.expandNode('A');
    ctrl.toggleTreeSelect('A/x.txt');
    await ctrl.navigateTo('A');
    expect(ctrl.state.path, 'A');
    expect(ctrl.state.tree.children.keys, {'A'});
    expect(ctrl.state.tree.selected, isEmpty);
    expect(client.listed.last, 'A');
  });

  test(
    'a listing failure is recorded per folder and cleared on retry',
    () async {
      final (_, ctrl, client) = await _open();
      client.manual = true;
      final expand = ctrl.expandNode('A');
      client.pending.single.completeError(StateError('offline'));
      await expand;
      expect(ctrl.state.tree.errors['A'], contains('offline'));
      expect(ctrl.state.tree.loading, isEmpty);
      expect(ctrl.state.tree.children.containsKey('A'), isFalse);
      client.manual = false;
      await ctrl.reloadTreeFolder('A');
      expect(ctrl.state.tree.errors, isEmpty);
      expect(_kids(ctrl, 'A'), ['B', 'x.txt']);
    },
  );
}
