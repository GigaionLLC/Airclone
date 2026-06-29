import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../ui/column_header.dart' show SortKey, compareRcloneFiles;
import 'engine_controller.dart';
import 'view_memory.dart';

/// How a pane renders its directory: classic detail list, icon/thumbnail grid,
/// or a date-grouped media gallery (images + video only).
enum ViewMode { list, grid, media }

/// Default grid tile target width (px). Tunable live via the density slider.
const double kDefaultGridSize = 112;

/// Lightweight descriptor of one open tab, for rendering the tab strip.
@immutable
class TabInfo {
  const TabInfo({required this.label});
  final String label;
}

@immutable
class BrowserState {
  const BrowserState({
    this.remote,
    this.path = '',
    this.entries = const [],
    this.loading = false,
    this.error,
    this.selected = const {},
    this.filter = '',
    this.sortKey = SortKey.name,
    this.ascending = true,
    this.viewMode = ViewMode.list,
    this.gridSize = kDefaultGridSize,
    this.tabs = const [],
    this.activeTab = 0,
  });

  final Remote? remote;
  final String path;
  final List<RcloneFile> entries;
  final bool loading;
  final String? error;
  final SortKey sortKey;
  final bool ascending;

  /// Per-pane view mode (list vs grid).
  final ViewMode viewMode;

  /// Per-pane grid tile target width in px.
  final double gridSize;

  /// Names (within the current folder) that are multi-selected.
  final Set<String> selected;

  /// Live client-side name filter (Ctrl+F box).
  final String filter;

  /// Open tabs in this pane (overlaid by the controller); the active one's
  /// location is reflected by the fields above.
  final List<TabInfo> tabs;

  /// Index of the active tab within [tabs].
  final int activeTab;

  List<String> get segments => path.isEmpty
      ? const []
      : path.split('/').where((s) => s.isNotEmpty).toList();

  bool isSelected(String name) => selected.contains(name);

  List<RcloneFile> get selectedEntries =>
      entries.where((e) => selected.contains(e.name)).toList();

  /// Entries after applying [filter] (what the list actually shows).
  List<RcloneFile> get visibleEntries {
    if (filter.isEmpty) return entries;
    final q = filter.toLowerCase();
    return entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  BrowserState copyWith({
    Remote? remote,
    String? path,
    List<RcloneFile>? entries,
    bool? loading,
    String? error,
    Set<String>? selected,
    String? filter,
    SortKey? sortKey,
    bool? ascending,
    ViewMode? viewMode,
    double? gridSize,
    List<TabInfo>? tabs,
    int? activeTab,
  }) => BrowserState(
    remote: remote ?? this.remote,
    path: path ?? this.path,
    entries: entries ?? this.entries,
    loading: loading ?? this.loading,
    error: error,
    selected: selected ?? this.selected,
    filter: filter ?? this.filter,
    sortKey: sortKey ?? this.sortKey,
    ascending: ascending ?? this.ascending,
    viewMode: viewMode ?? this.viewMode,
    gridSize: gridSize ?? this.gridSize,
    tabs: tabs ?? this.tabs,
    activeTab: activeTab ?? this.activeTab,
  );
}

/// One tab's full state + its own back/forward history.
class _Session {
  _Session([BrowserState? initial]) : state = initial ?? const BrowserState();
  BrowserState state;
  List<String> history = [''];
  int idx = 0;
}

/// Drives ONE browser pane with **tabs**: each tab is an independent session
/// (remote/path/selection/view + its own back/forward history). The public
/// [state] mirrors the active tab, with [BrowserState.tabs]/`activeTab` overlaid
/// so call sites and the tab strip see a single coherent snapshot.
class BrowserController extends Notifier<BrowserState> {
  final List<_Session> _sessions = [_Session()];
  int _active = 0;

  _Session get _s => _sessions[_active];

  bool get canBack => _s.idx > 0;
  bool get canForward => _s.idx < _s.history.length - 1;

  @override
  BrowserState build() => _emit();

  /// Public snapshot: the active session's state + the tab metadata.
  BrowserState _emit() => _s.state.copyWith(
    tabs: [for (final ses in _sessions) TabInfo(label: _labelFor(ses.state))],
    activeTab: _active,
  );

  static String _labelFor(BrowserState s) {
    final r = s.remote;
    if (r == null) return 'New tab';
    return s.path.isEmpty ? r.name : s.path.split('/').last;
  }

  /// Commit a new active-session state and re-emit with tab metadata.
  void _set(BrowserState s) {
    _s.state = s;
    state = _emit();
  }

  // ── tabs ───────────────────────────────────────────────────────────────────
  void newTab() {
    _sessions.add(
      _Session(
        BrowserState(viewMode: state.viewMode, gridSize: state.gridSize),
      ),
    );
    _active = _sessions.length - 1;
    state = _emit();
  }

  void switchTab(int i) {
    if (i < 0 || i >= _sessions.length || i == _active) return;
    _active = i;
    state = _emit();
  }

  void closeTab(int i) {
    if (_sessions.length <= 1 || i < 0 || i >= _sessions.length) return;
    _sessions.removeAt(i);
    if (_active >= _sessions.length) {
      _active = _sessions.length - 1;
    } else if (_active > i) {
      _active--;
    }
    state = _emit();
  }

  // ── navigation ─────────────────────────────────────────────────────────────
  void clear() {
    _s.history = [''];
    _s.idx = 0;
    _set(BrowserState(viewMode: state.viewMode, gridSize: state.gridSize));
  }

  Future<void> open(Remote remote) async {
    _s.history = [''];
    _s.idx = 0;
    // Restore how this remote was last viewed; otherwise keep the pane's
    // current view preference (list/grid + density + sort) across remotes.
    final saved = ref.read(viewMemoryProvider)[remote.name];
    _set(
      BrowserState(
        remote: remote,
        loading: true,
        viewMode: saved != null
            ? _viewModeFrom(saved.viewMode)
            : state.viewMode,
        gridSize: saved?.gridSize ?? state.gridSize,
        sortKey: saved != null ? _sortKeyFrom(saved.sortKey) : state.sortKey,
        ascending: saved?.ascending ?? state.ascending,
      ),
    );
    await _load();
  }

  static ViewMode _viewModeFrom(String name) => ViewMode.values.firstWhere(
    (v) => v.name == name,
    orElse: () => ViewMode.list,
  );

  static SortKey _sortKeyFrom(String name) => SortKey.values.firstWhere(
    (v) => v.name == name,
    orElse: () => SortKey.name,
  );

  /// Persist the active remote's current view settings (mode/sort/density).
  void _rememberView() {
    final r = state.remote;
    if (r == null) return;
    ref
        .read(viewMemoryProvider.notifier)
        .remember(
          r.name,
          ViewPref(
            viewMode: state.viewMode.name,
            sortKey: state.sortKey.name,
            ascending: state.ascending,
            gridSize: state.gridSize,
          ),
        );
  }

  Future<void> enterDir(RcloneFile dir) async {
    if (!dir.isDir) return;
    await _navigate(
      state.path.isEmpty ? dir.name : '${state.path}/${dir.name}',
    );
  }

  Future<void> goToSegment(int index) async {
    final segs = state.segments;
    await _navigate((index < 0) ? '' : segs.take(index + 1).join('/'));
  }

  Future<void> up() async {
    if (state.segments.isEmpty) return;
    await goToSegment(state.segments.length - 2);
  }

  /// Navigate to a typed/pasted path within the current remote (Explorer-style).
  Future<void> navigateTo(String path) async {
    await _navigate(
      path
          .trim()
          .replaceAll('\\', '/')
          .split('/')
          .where((s) => s.isNotEmpty)
          .join('/'),
    );
  }

  Future<void> back() async {
    if (!canBack) return;
    _s.idx--;
    await _navigate(_s.history[_s.idx], record: false);
  }

  Future<void> forward() async {
    if (!canForward) return;
    _s.idx++;
    await _navigate(_s.history[_s.idx], record: false);
  }

  /// Core navigation: optionally records history, resets selection + filter, loads.
  Future<void> _navigate(String path, {bool record = true}) async {
    if (record && path != state.path) {
      if (_s.history.length > _s.idx + 1) {
        _s.history = _s.history.sublist(0, _s.idx + 1);
      }
      _s.history = [..._s.history, path];
      _s.idx = _s.history.length - 1;
    }
    _set(
      state.copyWith(path: path, loading: true, selected: const {}, filter: ''),
    );
    await _load();
  }

  Future<void> refresh() async {
    if (state.remote == null) return;
    _set(state.copyWith(loading: true));
    await _load();
  }

  void setFilter(String value) => _set(state.copyWith(filter: value));

  void toggleSelect(String name) {
    final next = Set<String>.from(state.selected);
    next.contains(name) ? next.remove(name) : next.add(name);
    _set(state.copyWith(selected: next));
  }

  void clearSelection() => _set(state.copyWith(selected: const {}));

  /// Replace the selection with just [name] (used by type-to-navigate).
  void selectOnly(String name) => _set(state.copyWith(selected: {name}));

  void selectAll() => _set(
    state.copyWith(selected: state.visibleEntries.map((e) => e.name).toSet()),
  );

  /// Switch this pane between list and grid rendering.
  void setViewMode(ViewMode mode) {
    _set(state.copyWith(viewMode: mode));
    _rememberView();
  }

  /// Set the grid tile target width (density), clamped to a sane range.
  void setGridSize(double px) {
    _set(state.copyWith(gridSize: px.clamp(80, 180).toDouble()));
    _rememberView();
  }

  /// Sort by [key]; tapping the active column flips direction.
  void setSort(SortKey key) {
    final asc = key == state.sortKey ? !state.ascending : true;
    final sorted = [...state.entries]
      ..sort((a, b) => compareRcloneFiles(a, b, key, asc));
    _set(state.copyWith(sortKey: key, ascending: asc, entries: sorted));
    _rememberView();
  }

  Future<void> _load() async {
    final remote = state.remote;
    final client = ref.read(engineControllerProvider).client;
    if (remote == null || client == null) {
      _set(state.copyWith(loading: false, error: 'Engine not ready'));
      return;
    }
    try {
      final res = await client.rpc(
        'operations/list',
        remote.listParams(state.path),
      );
      final list =
          (res['list'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(RcloneFile.fromJson)
              .toList()
            ..sort(
              (a, b) =>
                  compareRcloneFiles(a, b, state.sortKey, state.ascending),
            );
      _set(state.copyWith(entries: list, loading: false));
    } catch (e) {
      _set(state.copyWith(entries: const [], loading: false, error: '$e'));
    }
  }
}

/// The two panes of the desktop commander.
final browserAProvider = NotifierProvider<BrowserController, BrowserState>(
  BrowserController.new,
);
final browserBProvider = NotifierProvider<BrowserController, BrowserState>(
  BrowserController.new,
);

/// Which pane is focused (0 = A / left, 1 = B / right). Sidebar clicks and the
/// destination of a "copy between panes" target the active pane.
final activePaneProvider = StateProvider<int>((_) => 0);

/// The provider for a pane index.
NotifierProvider<BrowserController, BrowserState> paneProvider(int index) =>
    index == 0 ? browserAProvider : browserBProvider;

/// App-lifetime FocusNode per pane filter box (Ctrl+F focuses the active pane's).
final paneFilterFocusProvider = Provider.family<FocusNode, int>((ref, index) {
  final node = FocusNode();
  ref.onDispose(node.dispose);
  return node;
});

/// App-lifetime ScrollController per pane list view (so type-to-navigate can
/// scroll the active pane to a matched row).
final paneScrollProvider = Provider.family<ScrollController, int>((ref, index) {
  final ctrl = ScrollController();
  ref.onDispose(ctrl.dispose);
  return ctrl;
});
