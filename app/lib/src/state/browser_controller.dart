import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../ui/column_header.dart' show SortKey, compareRcloneFiles;
import 'engine_controller.dart';

/// How a pane renders its directory: classic detail list, icon/thumbnail grid,
/// or a date-grouped media gallery (images + video only).
enum ViewMode { list, grid, media }

/// Default grid tile target width (px). Tunable live via the density slider.
const double kDefaultGridSize = 112;

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
  );
}

/// Drives ONE browser pane: open a remote, navigate (with back/forward history),
/// list via `operations/list`, filter, and track a multi-selection. Two instances
/// back the dual pane (A/B).
class BrowserController extends Notifier<BrowserState> {
  // Browser-style navigation history (paths within the current remote).
  List<String> _history = const [''];
  int _idx = 0;

  bool get canBack => _idx > 0;
  bool get canForward => _idx < _history.length - 1;

  @override
  BrowserState build() => const BrowserState();

  void clear() {
    _history = const [''];
    _idx = 0;
    state = const BrowserState();
  }

  Future<void> open(Remote remote) async {
    _history = [''];
    _idx = 0;
    // Keep the pane's view preference (list/grid + density) across remotes.
    state = BrowserState(
      remote: remote,
      loading: true,
      viewMode: state.viewMode,
      gridSize: state.gridSize,
    );
    await _load();
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
    _idx--;
    await _navigate(_history[_idx], record: false);
  }

  Future<void> forward() async {
    if (!canForward) return;
    _idx++;
    await _navigate(_history[_idx], record: false);
  }

  /// Core navigation: optionally records history, resets selection + filter, loads.
  Future<void> _navigate(String path, {bool record = true}) async {
    if (record && path != state.path) {
      if (_history.length > _idx + 1) _history = _history.sublist(0, _idx + 1);
      _history = [..._history, path];
      _idx = _history.length - 1;
    }
    state = state.copyWith(
      path: path,
      loading: true,
      selected: const {},
      filter: '',
    );
    await _load();
  }

  Future<void> refresh() async {
    if (state.remote == null) return;
    state = state.copyWith(loading: true);
    await _load();
  }

  void setFilter(String value) => state = state.copyWith(filter: value);

  void toggleSelect(String name) {
    final next = Set<String>.from(state.selected);
    next.contains(name) ? next.remove(name) : next.add(name);
    state = state.copyWith(selected: next);
  }

  void clearSelection() => state = state.copyWith(selected: const {});

  void selectAll() => state = state.copyWith(
    selected: state.visibleEntries.map((e) => e.name).toSet(),
  );

  /// Switch this pane between list and grid rendering.
  void setViewMode(ViewMode mode) => state = state.copyWith(viewMode: mode);

  /// Set the grid tile target width (density), clamped to a sane range.
  void setGridSize(double px) =>
      state = state.copyWith(gridSize: px.clamp(80, 180).toDouble());

  /// Sort by [key]; tapping the active column flips direction.
  void setSort(SortKey key) {
    final asc = key == state.sortKey ? !state.ascending : true;
    final sorted = [...state.entries]
      ..sort((a, b) => compareRcloneFiles(a, b, key, asc));
    state = state.copyWith(sortKey: key, ascending: asc, entries: sorted);
  }

  Future<void> _load() async {
    final remote = state.remote;
    final client = ref.read(engineControllerProvider).client;
    if (remote == null || client == null) {
      state = state.copyWith(loading: false, error: 'Engine not ready');
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
      state = state.copyWith(entries: list, loading: false);
    } catch (e) {
      state = state.copyWith(entries: const [], loading: false, error: '$e');
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
