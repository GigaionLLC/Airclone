import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:shared_preferences/shared_preferences.dart';

/// Answers folder listings synchronously, and a RECURSIVE listing as an async
/// job whose `job/status` stays unfinished until [finish] (or answers inline
/// when [inline] is set). Records every call.
class _Client implements RcloneClient {
  final calls = <(String, Map<String, dynamic>)>[];
  final stopped = <int>[];
  bool inline = false;
  int _nextJob = 1;
  final Map<int, Map<String, dynamic>?> _jobs = {};

  /// The recursive listing the next scan finds, relative to the folder asked.
  List<Map<String, dynamic>> tree = [
    _e('Movies', dir: true),
    _e('Movies/holiday.mp4'),
    _e('Movies/2024', dir: true),
    _e('Movies/2024/beach holiday.mkv'),
    _e('notes.txt'),
  ];

  /// Lets the newest scan finish.
  void finish([int? job]) => _jobs[job ?? _nextJob - 1] = {'list': tree};

  int get scans =>
      calls.where((c) => c.$1 == 'operations/list' && _recursive(c.$2)).length;

  static bool _recursive(Map<String, dynamic> p) =>
      (p['opt'] as Map?)?['recurse'] == true;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final p = params ?? const <String, dynamic>{};
    calls.add((method, p));
    switch (method) {
      case 'operations/list':
        if (!_recursive(p)) {
          return {
            'list': [
              _e('Holiday.txt'),
              _e('work.txt'),
              _e('Movies', dir: true),
            ],
          };
        }
        if (inline) return {'list': tree};
        final id = _nextJob++;
        _jobs[id] = null;
        return {'jobid': id};
      case 'job/status':
        final id = p['jobid'] as int;
        final out = _jobs[id];
        if (stopped.contains(id)) {
          return {'finished': true, 'success': false, 'error': 'stopped'};
        }
        return out == null
            ? {'finished': false}
            : {'finished': true, 'success': true, 'output': out};
      case 'job/stop':
        stopped.add(p['jobid'] as int);
        return {};
    }
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _e(String path, {bool dir = false}) => {
  'Name': path.split('/').last,
  'Path': path,
  'IsDir': dir,
  'Size': dir ? -1 : 10,
};

class _FakeEngine extends EngineController {
  _FakeEngine(this._client);
  final RcloneClient _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);
}

// A local remote: its listFs differs from fs, which is what the scan must NOT
// use (following links through a whole tree can loop).
const _remote = Remote(name: 'disk', type: 'local', fs: '/data/');

Future<(BrowserController, _Client)> _open() async {
  final client = _Client();
  final container = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
    ],
  );
  addTearDown(container.dispose);
  final ctrl = container.read(browserAProvider.notifier);
  await ctrl.open(_remote);
  return (ctrl, client);
}

/// Let the 400 ms poll run.
Future<void> _poll() => Future<void>.delayed(const Duration(milliseconds: 900));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('This folder: every word must appear in the name', () async {
    final (ctrl, _) = await _open();
    ctrl.setFilter('holi');
    expect(ctrl.state.visibleEntries.map((e) => e.name), ['Holiday.txt']);
    ctrl.setFilter('txt work');
    expect(ctrl.state.visibleEntries.map((e) => e.name), ['work.txt']);
  });

  test('Subfolders starts ONE async recursive list of the pane folder on '
      'remote.fs, then the query re-filters without listing again', () async {
    final (ctrl, client) = await _open();
    ctrl.setFilter('holiday');
    ctrl.setSearchScope(SearchScope.subfolders);
    await Future<void>.delayed(Duration.zero);
    expect(ctrl.state.search.status, SearchScanStatus.scanning);
    final call = client.calls.lastWhere((c) => c.$1 == 'operations/list');
    expect(call.$2['fs'], '/data/');
    expect(call.$2['remote'], '');
    expect(call.$2['_async'], isTrue);
    expect(call.$2['opt'], containsPair('recurse', true));

    client.finish();
    await _poll();
    final s = ctrl.state.search;
    expect(s.status, SearchScanStatus.done);
    expect(s.scanned, 5);
    expect(s.hits.map((h) => h.absPath), [
      'Movies/holiday.mp4',
      'Movies/2024/beach holiday.mkv',
    ]);

    ctrl.setFilter('2024');
    expect(ctrl.state.search.hits.map((h) => h.absPath), [
      'Movies/2024',
      'Movies/2024/beach holiday.mkv',
    ]);
    expect(client.scans, 1, reason: 'refining never re-lists');
  });

  test('an engine that answers inline is still an answer', () async {
    final (ctrl, client) = await _open();
    client.inline = true;
    ctrl.setFilter('notes');
    ctrl.setSearchScope(SearchScope.subfolders);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(ctrl.state.search.status, SearchScanStatus.done);
    expect(ctrl.state.search.hits.single.absPath, 'notes.txt');
  });

  test('entering Subfolders drops the flat selection and select-all is '
      'inert there', () async {
    final (ctrl, client) = await _open();
    ctrl.toggleSelect('work.txt');
    expect(ctrl.state.selected, {'work.txt'});
    ctrl.setSearchScope(SearchScope.subfolders);
    expect(ctrl.state.selected, isEmpty);
    ctrl.selectAll();
    expect(ctrl.state.selected, isEmpty);
    expect(ctrl.state.selectedEntries, isEmpty);
    client.finish();
    await _poll();
  });

  test(
    'Cancel stops the job on the engine and a late answer is dropped',
    () async {
      final (ctrl, client) = await _open();
      ctrl.setFilter('holiday');
      ctrl.setSearchScope(SearchScope.subfolders);
      await _poll();
      ctrl.cancelSearch();
      await Future<void>.delayed(Duration.zero);
      expect(client.stopped, [1]);
      expect(ctrl.state.search.status, SearchScanStatus.cancelled);
      client.finish(1);
      await _poll();
      expect(ctrl.state.search.status, SearchScanStatus.cancelled);
      expect(ctrl.state.search.hits, isEmpty);

      ctrl.retrySearch();
      client.finish();
      await _poll();
      expect(ctrl.state.search.status, SearchScanStatus.done);
    },
  );

  test('navigating resets to This folder, clears the query and stops a scan '
      'in flight', () async {
    final (ctrl, client) = await _open();
    ctrl.setFilter('holiday');
    ctrl.setSearchScope(SearchScope.subfolders);
    await _poll();
    await ctrl.navigateTo('Movies');
    await Future<void>.delayed(Duration.zero);
    expect(client.stopped, [1]);
    expect(ctrl.state.search.scope, SearchScope.folder);
    expect(ctrl.state.filter, isEmpty);
    client.finish(1);
    await _poll();
    expect(ctrl.state.search.hits, isEmpty, reason: 'stale scan dropped');
  });

  test('choosing Subfolders again on the same folder reuses the scan; '
      'refresh scans again', () async {
    final (ctrl, client) = await _open();
    ctrl.setFilter('notes');
    ctrl.setSearchScope(SearchScope.subfolders);
    client.finish();
    await _poll();
    ctrl.setSearchScope(SearchScope.folder);
    ctrl.setSearchScope(SearchScope.subfolders);
    expect(ctrl.state.search.status, SearchScanStatus.done);
    expect(ctrl.state.search.hits.single.absPath, 'notes.txt');
    expect(client.scans, 1);

    await ctrl.refresh();
    expect(client.scans, 2);
    expect(ctrl.state.search.status, SearchScanStatus.scanning);
    client.finish();
    await _poll();
    expect(ctrl.state.search.status, SearchScanStatus.done);
  });

  test('a scan lands in the tab that started it', () async {
    final (ctrl, client) = await _open();
    ctrl.setFilter('notes');
    ctrl.setSearchScope(SearchScope.subfolders);
    ctrl.newTab();
    client.finish();
    await _poll();
    expect(ctrl.state.search.inSubfolders, isFalse, reason: 'new tab');
    ctrl.switchTab(0);
    expect(ctrl.state.search.status, SearchScanStatus.done);
    expect(ctrl.state.search.hits.single.absPath, 'notes.txt');
  });

  test('stepOutOfSearch: results, then text, then the open box', () async {
    final (ctrl, client) = await _open();
    ctrl.openSearchBox();
    ctrl.setFilter('x');
    ctrl.setSearchScope(SearchScope.subfolders);
    expect(ctrl.stepOutOfSearch(), isTrue);
    expect(ctrl.state.search.scope, SearchScope.folder);
    expect(ctrl.state.filter, 'x');
    expect(ctrl.state.search.open, isTrue);
    expect(ctrl.stepOutOfSearch(), isTrue);
    expect(ctrl.state.filter, isEmpty);
    expect(ctrl.stepOutOfSearch(), isTrue);
    expect(ctrl.state.search.open, isFalse);
    expect(ctrl.stepOutOfSearch(), isFalse);
    // Cancelled before the engine had answered with a job id: the stop goes
    // out as soon as it does.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(client.stopped, [1]);
  });

  test('searchSiblingsOf answers from the scan', () async {
    final (ctrl, client) = await _open();
    ctrl.setSearchScope(SearchScope.subfolders);
    client.finish();
    await _poll();
    expect(ctrl.searchSiblingsOf('Movies').map((f) => f.name), [
      'holiday.mp4',
      '2024',
    ]);
  });
}
