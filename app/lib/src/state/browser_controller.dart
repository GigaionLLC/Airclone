import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../ui/column_header.dart' show SortKey, compareRcloneFiles;
import '../ui/file_icon.dart' show isGalleryMedia;
import '../ui/pane_drag.dart' show joinPath;
import 'console/console_controller.dart';
import 'engine_controller.dart';
import 'tree_state.dart';
import 'undecryptable_names.dart';
import 'view_memory.dart';

export 'tree_state.dart';

/// How a pane renders its directory: classic detail list, icon/thumbnail grid,
/// a date-grouped media gallery (images + video only), or an expandable tree
/// rooted at the pane's folder ([BrowserState.tree]; desktop only — the touch
/// shell keeps its own navigation, so [BrowserController.setViewMode] never
/// enters it there).
enum ViewMode { list, grid, media, tree }

/// Default grid tile target width (px). Tunable live via the density slider.
const double kDefaultGridSize = 112;

/// What a pane's tab shows: the file browser, or the rclone command console.
enum PaneKind { browser, console }

/// Lightweight descriptor of one open tab, for rendering the tab strip.
@immutable
class TabInfo {
  const TabInfo({
    required this.label,
    this.kind = PaneKind.browser,
    this.consoleId = '',
  });
  final String label;

  /// Whether this tab is a browser or a console. A console tab renders a
  /// [ConsolePane] instead of the file view (see BrowserPane).
  final PaneKind kind;

  /// The stable console id (for `consoleControllerProvider`) — empty for browser
  /// tabs.
  final String consoleId;
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
    this.hiddenUndecryptable = 0,
    this.tree = TreeState.empty,
  });

  final Remote? remote;

  /// The pane's folder. In [ViewMode.tree] this is the folder the tree is
  /// ROOTED at — the address bar, breadcrumb and tab label all describe it —
  /// and NOT the folder any given row lives in. A row's folder is its own
  /// [TreeRow.parentPath]; nothing may build a deep row's path from here.
  final String path;

  /// The listing of [path]. In the tree it is the top level; deeper levels
  /// live in [tree].
  final List<RcloneFile> entries;

  /// The tree view's forest: cached listings, expansion, and its own
  /// selection. Survives switching view modes within the tab and survives
  /// navigation (keys are full paths, so they stay valid); cleared when the
  /// remote changes.
  final TreeState tree;
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

  /// How many entries rclone withheld from the last listing because it could not
  /// decrypt their names — see [undecryptableNameCount]. Zero for every listing
  /// that was complete, which is nearly all of them.
  ///
  /// A crypt remote holding the wrong password or salt returns HTTP 200 and a
  /// SHORT list, so without this the pane cannot tell "this folder is empty"
  /// from "rclone hid everything in it", and renders the same confident "Empty
  /// folder" over both.
  final int hiddenUndecryptable;

  List<String> get segments => path.isEmpty
      ? const []
      : path.split('/').where((s) => s.isNotEmpty).toList();

  /// True when the active tab is a console session. A console's browser state is
  /// empty (`remote == null`), so callers that gate "is this pane showing
  /// content?" on `remote != null` must also accept a console tab — otherwise the
  /// phone shell bounces a console back to the locations list.
  bool get activeIsConsole =>
      activeTab >= 0 &&
      activeTab < tabs.length &&
      tabs[activeTab].kind == PaneKind.console;

  bool isSelected(String name) => selected.contains(name);

  /// The flat views' selection, resolved against [entries].
  ///
  /// **Empty in the tree view, always.** Every consumer of this getter builds
  /// a target as `path + entry.name` (Delete, F2, Ctrl+C, the inspector, Quick
  /// Look), which is correct for one flat folder and WRONG for a row three
  /// levels down — the Delete key would purge `root/name` instead of
  /// `A/B/C/name`. A tree selection therefore never surfaces here; it lives in
  /// [tree.selected] as full paths and is reached through [selectedTreeRows],
  /// whose rows carry their own parent. Consumers that only know this getter
  /// see no selection in tree mode, which is the safe failure.
  List<RcloneFile> get selectedEntries => viewMode == ViewMode.tree
      ? const []
      : entries.where((e) => selected.contains(e.name)).toList();

  /// Whether anything is selected in whichever view is showing.
  bool get hasSelection => viewMode == ViewMode.tree
      ? tree.selected.isNotEmpty
      : selected.isNotEmpty;

  /// How many items are selected in whichever view is showing.
  int get selectionCount =>
      viewMode == ViewMode.tree ? tree.selected.length : selected.length;

  /// The loaded listing of [folder]: the root's is [entries], any deeper
  /// folder's is its cached tree listing. Null when it has not been listed.
  List<RcloneFile>? childrenOf(String folder) =>
      folder == path ? entries : tree.children[folder];

  bool isTreeSelected(String fullPath) => tree.selected.contains(fullPath);

  /// The tree selection as rows, each carrying the folder it was listed from.
  /// A selected path whose folder is no longer loaded is dropped rather than
  /// guessed at — an operation must never run on an entry it cannot see.
  List<TreeRow> get selectedTreeRows {
    if (viewMode != ViewMode.tree) return const [];
    final rootDepth = segments.length;
    final out = <TreeRow>[];
    for (final p in tree.selected) {
      final parent = parentOf(p);
      final name = leafOf(p);
      final siblings = childrenOf(parent);
      if (siblings == null) continue;
      for (final f in siblings) {
        if (f.name == name) {
          final depth = p.split('/').length - rootDepth - 1;
          out.add(TreeRow.entry(entry: f, parentPath: parent, depth: depth));
          break;
        }
      }
    }
    return out;
  }

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
    int? hiddenUndecryptable,
    TreeState? tree,
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
    hiddenUndecryptable: hiddenUndecryptable ?? this.hiddenUndecryptable,
    tree: tree ?? this.tree,
  );
}

/// One tab's full state + its own back/forward history. A [PaneKind.console]
/// session carries a stable [consoleId] and an empty browser state (its content
/// lives in `consoleControllerProvider(consoleId)`, not here).
class _Session {
  _Session([BrowserState? initial]) : state = initial ?? const BrowserState();
  BrowserState state;
  List<String> history = [''];
  int idx = 0;
  PaneKind kind = PaneKind.browser;
  String consoleId = '';

  /// Per-node superseded guard for tree listings (the per-folder form of the
  /// remote+path check in `_load`). Every tree listing takes the next
  /// [treeSeq] and records it under its folder; a response whose number is no
  /// longer the one on record was overtaken — by a reload, a refresh, or the
  /// remote changing — and commits nothing. One counter for the whole session
  /// (not per folder) so a cleared map can never hand an old response a
  /// number that matches again.
  int treeSeq = 0;
  final Map<String, int> treeGen = {};
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
    tabs: [for (final ses in _sessions) _tabInfo(ses)],
    activeTab: _active,
  );

  static TabInfo _tabInfo(_Session ses) => ses.kind == PaneKind.console
      ? TabInfo(
          label: 'Console',
          kind: PaneKind.console,
          consoleId: ses.consoleId,
        )
      : TabInfo(label: _labelFor(ses.state));

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

  /// Process-wide counter for stable, globally-unique console ids (the console
  /// controller family is global, so ids must be unique across both panes).
  static int _consoleSeq = 0;

  /// Open a new console tab (the rclone command console) and make it active.
  void newConsoleTab() {
    final ses = _Session()
      ..kind = PaneKind.console
      ..consoleId = 'console-${_consoleSeq++}';
    _sessions.add(ses);
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
    // Closing a console tab: cancel any running command and FREE its controller.
    // consoleControllerProvider is a non-autoDispose family keyed by a monotonic
    // id, so without this the subscription (and its ~2000-line scrollback) would
    // leak for the app's lifetime and orphan a running command.
    final closing = _sessions[i];
    if (closing.kind == PaneKind.console && closing.consoleId.isNotEmpty) {
      final p = consoleControllerProvider(closing.consoleId);
      ref.read(p.notifier).stop();
      ref.invalidate(p);
    }
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
    // A fresh BrowserState carries an empty tree; forgetting the generation
    // map as well strands any listing still in flight for the old remote.
    _s.treeGen.clear();
    _set(BrowserState(viewMode: state.viewMode, gridSize: state.gridSize));
  }

  Future<void> open(Remote remote) async {
    _s.history = [''];
    _s.idx = 0;
    // Tree keys are paths on ONE remote — they mean nothing on another.
    _s.treeGen.clear();
    // Restore how this remote was last viewed; otherwise keep the pane's
    // current view preference (list/grid + density + sort) across remotes.
    final saved = ref.read(viewMemoryProvider)[remote.name];
    _set(
      BrowserState(
        remote: remote,
        loading: true,
        viewMode: _allowedHere(
          saved != null ? _viewModeFrom(saved.viewMode) : state.viewMode,
        ),
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

  /// Every view mode is available on every platform.
  ///
  /// The tree used to be forced to a list on touch, on the reasoning that a
  /// phone had no room for indentation plus three columns. That was true of
  /// the row as it was built, not of the tree: `tree_view.dart` now drops the
  /// Size and Modified columns below [kTreeDetailsMinWidth] and gives the
  /// space back to indentation, so the tree reads on a phone. Kept as a named
  /// seam rather than deleted because "which modes may run here" is a real
  /// question a future platform may answer differently — the Web UI already
  /// made one such assumption wrong.
  static ViewMode _allowedHere(ViewMode mode) => mode;

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
    // Clear the OLD folder's entries as we start loading the new path, so the
    // pane shows a loading spinner (initialLoad = loading && no entries) instead
    // of the previous folder's list until the new listing lands. refresh() below
    // deliberately does NOT clear — a same-folder reload keeps its list on screen.
    // The tree's cached listings and expansion are keyed by full path, so
    // they stay valid across navigation and are kept; its selection referred
    // to rows under the old root and goes the same way the flat one does.
    _set(
      state.copyWith(
        path: path,
        entries: const [],
        loading: true,
        selected: const {},
        filter: '',
        tree: state.tree.copyWith(selected: const {}, clearCursor: true),
      ),
    );
    await _load();
  }

  /// Re-list the pane. In the tree view that is the root plus every expanded
  /// folder the user can see — bounded by what they opened, never the whole
  /// forest — while listings of folders that are NOT on screen are dropped so
  /// their next expand re-lists them fresh. Each visible folder keeps its old
  /// rows until its new listing lands, as the root does.
  Future<void> refresh() async {
    if (state.remote == null) return;
    _set(state.copyWith(loading: true));
    if (state.viewMode == ViewMode.tree) {
      final visible = visibleExpandedFolders(state.path, state.tree);
      final tree = state.tree;
      _set(
        state.copyWith(
          tree: tree.copyWith(
            children: {
              for (final p in visible)
                if (tree.children[p] != null) p: tree.children[p]!,
            },
            errors: const {},
          ),
        ),
      );
      for (final p in visible) {
        // Deliberately not awaited: the visible folders list in parallel with
        // the root rather than one after another.
        unawaited(_loadTreeFolder(p));
      }
    }
    await _load();
  }

  void setFilter(String value) => _set(state.copyWith(filter: value));

  /// Toggle [name] (a root-level entry) in the selection. In the tree view the
  /// root's children are the top-level rows, so this lands in the tree
  /// selection as the full path — the flat set stays empty there.
  void toggleSelect(String name) {
    if (state.viewMode == ViewMode.tree) {
      toggleTreeSelect(joinPath(state.path, name));
      return;
    }
    final next = Set<String>.from(state.selected);
    next.contains(name) ? next.remove(name) : next.add(name);
    _set(state.copyWith(selected: next));
  }

  void clearSelection() => _set(
    state.copyWith(
      selected: const {},
      tree: state.tree.copyWith(selected: const {}),
    ),
  );

  /// Replace the selection with just [name] (used by type-to-navigate and the
  /// search dialog's reveal). Both hand over a root-level name, so in the tree
  /// this selects the top-level row and moves the cursor to it — type-to-jump
  /// follows into the tree rather than quietly stopping there (plan §4.f).
  void selectOnly(String name) {
    if (state.viewMode == ViewMode.tree) {
      selectTreeOnly(joinPath(state.path, name));
      return;
    }
    _set(state.copyWith(selected: {name}));
  }

  /// Select everything CURRENTLY DISPLAYED in this pane. In the media Gallery
  /// view that's the images/videos only — never the folders/other files the
  /// gallery hides, since selecting those would let a later bulk Delete
  /// recursively purge items the user can't see. In the tree it is every
  /// entry row on screen (expanded, and passing the filter), for the same
  /// reason: a collapsed folder's contents are not on screen.
  void selectAll() {
    if (state.viewMode == ViewMode.tree) {
      final rows = flattenTree(
        rootPath: state.path,
        rootEntries: state.entries,
        tree: state.tree,
        filter: state.filter,
      );
      _set(
        state.copyWith(
          tree: state.tree.copyWith(
            selected: {
              for (final r in rows)
                if (r.isEntry) r.path,
            },
          ),
        ),
      );
      return;
    }
    final displayed = state.viewMode == ViewMode.media
        ? state.visibleEntries.where(isGalleryMedia)
        : state.visibleEntries;
    _set(state.copyWith(selected: displayed.map((e) => e.name).toSet()));
  }

  /// Switch this pane's rendering. Expansion survives a round trip through
  /// another mode (plan §7); the selection is carried across where it can be
  /// — root-level rows exist in both worlds — and dropped where it cannot (a
  /// deep tree selection has no flat equivalent).
  void setViewMode(ViewMode mode) {
    mode = _allowedHere(mode);
    final was = state.viewMode;
    var next = state.copyWith(viewMode: mode);
    if (mode == ViewMode.tree && was != ViewMode.tree) {
      next = next.copyWith(
        selected: const {},
        tree: state.tree.copyWith(
          selected: {for (final n in state.selected) joinPath(state.path, n)},
        ),
      );
    } else if (mode != ViewMode.tree && was == ViewMode.tree) {
      next = next.copyWith(
        selected: {
          for (final p in state.tree.selected)
            if (parentOf(p) == state.path) leafOf(p),
        },
        tree: state.tree.copyWith(selected: const {}, clearCursor: true),
      );
    }
    _set(next);
    _rememberView();
  }

  /// Set the grid tile target width (density), clamped to a sane range.
  void setGridSize(double px) {
    _set(state.copyWith(gridSize: px.clamp(80, 180).toDouble()));
    _rememberView();
  }

  /// Sort by [key]; tapping the active column flips direction. The tree's
  /// cached listings are re-sorted too, each within its own parent — a sort
  /// that flattened the hierarchy is the first thing a user would notice.
  void setSort(SortKey key) {
    final asc = key == state.sortKey ? !state.ascending : true;
    int cmp(RcloneFile a, RcloneFile b) => compareRcloneFiles(a, b, key, asc);
    final sorted = [...state.entries]..sort(cmp);
    final tree = state.tree;
    _set(
      state.copyWith(
        sortKey: key,
        ascending: asc,
        entries: sorted,
        tree: tree.children.isEmpty
            ? tree
            : tree.copyWith(
                children: {
                  for (final e in tree.children.entries)
                    e.key: [...e.value]..sort(cmp),
                },
              ),
      ),
    );
    _rememberView();
  }

  // ── tree view ──────────────────────────────────────────────────────────────

  /// Open [folder] (a full path). Lists it on its FIRST expand only; a folder
  /// whose listing is cached or already in flight costs nothing.
  Future<void> expandNode(String folder) async {
    final tree = state.tree;
    if (!tree.expanded.contains(folder)) {
      _setTree(_s, (t) => t.copyWith(expanded: {...t.expanded, folder}));
    }
    if (tree.children[folder] == null && !tree.loading.contains(folder)) {
      await _loadTreeFolder(folder);
    }
  }

  /// Close [folder]. Its listing stays cached. Selected rows beneath it leave
  /// the selection — they are no longer on screen, and a later bulk Delete
  /// must not purge what the user cannot see; the cursor climbs to the folder.
  void collapseNode(String folder) {
    _setTree(_s, (t) {
      final cursor = t.cursor;
      return t.copyWith(
        expanded: {...t.expanded}..remove(folder),
        selected: {
          for (final p in t.selected)
            if (!isUnder(p, folder)) p,
        },
        cursor: cursor != null && isUnder(cursor, folder) ? folder : cursor,
      );
    });
  }

  Future<void> toggleExpand(String folder) async {
    if (state.tree.expanded.contains(folder)) {
      collapseNode(folder);
    } else {
      await expandNode(folder);
    }
  }

  /// Re-list ONE folder after an operation touched it — the root through the
  /// ordinary load, anything deeper through its own. A collapsed folder just
  /// forgets its listing so the next expand fetches it fresh.
  Future<void> reloadTreeFolder(String folder) async {
    if (folder == state.path) {
      await refresh();
      return;
    }
    if (!state.tree.expanded.contains(folder)) {
      _setTree(
        _s,
        (t) => t.copyWith(
          children: {...t.children}..remove(folder),
          errors: {...t.errors}..remove(folder),
        ),
      );
      return;
    }
    await _loadTreeFolder(folder);
  }

  void toggleTreeSelect(String fullPath) {
    _setTree(_s, (t) {
      final next = Set<String>.from(t.selected);
      next.contains(fullPath) ? next.remove(fullPath) : next.add(fullPath);
      return t.copyWith(selected: next, cursor: fullPath);
    });
  }

  /// Replace the tree selection with [fullPath] and put the cursor on it.
  void selectTreeOnly(String fullPath) =>
      _setTree(_s, (t) => t.copyWith(selected: {fullPath}, cursor: fullPath));

  void setTreeCursor(String? fullPath) => _setTree(
    _s,
    (t) => fullPath == null
        ? t.copyWith(clearCursor: true)
        : t.copyWith(cursor: fullPath),
  );

  /// Commit a tree change to [ses] — which may no longer be the active tab by
  /// the time an async listing lands, so the emit is conditional. `copyWith`
  /// drops `error` unless it is passed; a tree change must not clear the
  /// root's error message.
  void _setTree(_Session ses, TreeState Function(TreeState) fn) {
    final s = ses.state;
    ses.state = s.copyWith(tree: fn(s.tree), error: s.error);
    if (identical(ses, _s)) state = _emit();
  }

  /// One `operations/list` for [folder], committed to the tab that asked for
  /// it — and only if nothing overtook it (see `_Session.treeGen`).
  Future<void> _loadTreeFolder(String folder) async {
    final ses = _s;
    final remote = ses.state.remote;
    final client = ref.read(engineControllerProvider).client;
    if (remote == null) return;
    if (client == null) {
      _setTree(
        ses,
        (t) => t.copyWith(errors: {...t.errors, folder: 'Engine not ready'}),
      );
      return;
    }
    final gen = ++ses.treeSeq;
    ses.treeGen[folder] = gen;
    _setTree(
      ses,
      (t) => t.copyWith(
        loading: {...t.loading, folder},
        errors: {...t.errors}..remove(folder),
      ),
    );
    bool superseded() =>
        ses.state.remote != remote || ses.treeGen[folder] != gen;
    try {
      final res = await client.rpc(
        'operations/list',
        remote.listParams(folder),
      );
      if (superseded()) return;
      final sortKey = ses.state.sortKey;
      final asc = ses.state.ascending;
      final list =
          (res['list'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(RcloneFile.fromJson)
              .toList()
            ..sort((a, b) => compareRcloneFiles(a, b, sortKey, asc));
      _setTree(
        ses,
        (t) => t.copyWith(
          children: {...t.children, folder: list},
          loading: {...t.loading}..remove(folder),
        ),
      );
    } catch (e) {
      if (superseded()) return;
      _setTree(
        ses,
        (t) => t.copyWith(
          errors: {...t.errors, folder: '$e'},
          loading: {...t.loading}..remove(folder),
        ),
      );
    }
  }

  Future<void> _load() async {
    final remote = state.remote;
    final client = ref.read(engineControllerProvider).client;
    if (remote == null || client == null) {
      _set(state.copyWith(loading: false, error: 'Engine not ready'));
      return;
    }
    // Snapshot what THIS load targets. Loads overlap (fast folder clicks, a
    // pull-to-refresh, the jobs-done auto-refresh, or slow cloud lists racing
    // thumbnail traffic on the one engine), and whichever RPC returns last would
    // otherwise win — clobbering the current folder with a stale/empty response
    // and flashing "Empty folder". Guard by re-checking remote+path after the
    // await and bailing (committing nothing) if navigation has moved on.
    final path = state.path;
    bool superseded() => state.remote != remote || state.path != path;
    // Sample the undecryptable-name counter across the request. rclone answers
    // 200 with the surviving entries and says nothing about the ones it dropped,
    // so the count of notices the engine emitted WHILE this listing ran is the
    // only way to know the list came back short.
    final skipsBefore = undecryptableNameCount;
    try {
      final res = await client.rpc('operations/list', remote.listParams(path));
      if (superseded()) return;
      final list =
          (res['list'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(RcloneFile.fromJson)
              .toList()
            ..sort(
              (a, b) =>
                  compareRcloneFiles(a, b, state.sortKey, state.ascending),
            );
      _set(
        state.copyWith(
          entries: list,
          loading: false,
          hiddenUndecryptable: hiddenForBackend(
            remote.type,
            skipsBefore,
            undecryptableNameCount,
          ),
        ),
      );
    } catch (e) {
      if (superseded()) return;
      _set(
        state.copyWith(
          entries: const [],
          loading: false,
          error: '$e',
          hiddenUndecryptable: 0,
        ),
      );
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

/// Bumped by Ctrl+L / Alt+D to pop the active pane's address bar into edit
/// mode (the Explorer/Finder "focus the address bar" gesture). The PathBar
/// watches the tick and starts editing when it changes.
final pathEditRequestProvider = StateProvider.family<int, int>(
  (ref, index) => 0,
);

/// App-lifetime ScrollController per pane list view (so type-to-navigate can
/// scroll the active pane to a matched row).
final paneScrollProvider = Provider.family<ScrollController, int>((ref, index) {
  final ctrl = ScrollController();
  ref.onDispose(ctrl.dispose);
  return ctrl;
});
