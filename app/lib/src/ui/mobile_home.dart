import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';
import '../state/advanced_mode.dart';
import '../state/android_native.dart';
import '../state/browser_controller.dart';
import '../state/engine_controller.dart';
import '../state/local_locations.dart';
import '../state/pane_layout.dart';
import '../state/remotes_provider.dart';
import '../state/stats_controller.dart';
import 'browser_pane.dart';
import 'engine_gate.dart';
import 'jobs_panel.dart';
import 'mobile_action_sheets.dart';
import 'pane_split.dart';
import 'recent_activity_panel.dart';
import 'selection_actions.dart';
import 'settings_screen.dart';
import 'stats_panel.dart';
import 'tab_strip.dart';
import 'theme/tokens.dart';
import 'touch.dart';

/// The phone shell: bottom navigation over Files · Transfers · Settings.
/// Everything runs off the same providers as the desktop shell — the Files tab
/// drives pane 0, so rotating a tablet between the two shells keeps state.
class MobileHomeScreen extends ConsumerStatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  ConsumerState<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends ConsumerState<MobileHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final browsing = ref.watch(
      paneProvider(0).select((s) => s.remote != null || s.activeIsConsole),
    );
    final split = ref.watch(mobileSplitProvider);
    // When the engine gate is on screen, pane state is irrelevant — back must
    // not get swallowed navigating a browser the user can't see.
    final gated = ref.watch(
      engineControllerProvider.select((e) => e.phase != EnginePhase.ready),
    );
    // The + FAB — shown on the Files tab when a real folder is open in the target
    // pane (not a console), as the primary "add something here" affordance, the
    // way other mobile file apps do. Opens the create bottom sheet.
    // In single-pane the visible pane is ALWAYS pane 0; only trust activePane
    // when a split is actually on screen — it can linger at 1 after an "open in
    // other pane" with no split, and the FAB must never target a hidden pane.
    final activePane = ref.watch(activePaneProvider);
    final fabPane = split ? activePane : 0;
    final fabVisible =
        _tab == 0 &&
        !gated &&
        ref.watch(
          paneProvider(
            fabPane,
          ).select((s) => s.remote != null && !s.activeIsConsole),
        );
    // A live multi-selection (touch): system-back clears it first, before it
    // would otherwise navigate up or leave the folder. Checked on BOTH panes —
    // a selection can live on the non-active pane in split view, and its bar is
    // rendered per-pane regardless of which pane is active.
    final touching = _tab == 0 && isTouchPrimary;
    final sel0 =
        touching &&
        ref.watch(paneProvider(0).select((s) => s.selected.isNotEmpty));
    final sel1 =
        touching &&
        split &&
        ref.watch(paneProvider(1).select((s) => s.selected.isNotEmpty));
    final hasSelection = sel0 || sel1;
    // System back: leave a folder, then leave the remote, then leave a non-Files
    // tab — only exit the app from the Files tab's locations list (never while a
    // split is up: back collapses that first).
    final canPop =
        _tab == 0 && !hasSelection && (gated || (!browsing && !split));
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (hasSelection) {
          if (sel0) ref.read(paneProvider(0).notifier).clearSelection();
          if (sel1) ref.read(paneProvider(1).notifier).clearSelection();
          return;
        }
        if (_tab != 0) {
          setState(() => _tab = 0);
          return;
        }
        if (split) {
          // Back walks the *active* pane up; at its root it collapses the split
          // back to single-pane rather than exiting the app.
          final active = ref.read(activePaneProvider);
          final pane = ref.read(paneProvider(active));
          final actrl = ref.read(paneProvider(active).notifier);
          if (pane.activeIsConsole) {
            actrl.closeTab(pane.activeTab);
          } else if (pane.path.isNotEmpty) {
            actrl.up();
          } else {
            ref.read(mobileSplitProvider.notifier).state = false;
            ref.read(activePaneProvider.notifier).state = 0;
          }
          return;
        }
        final pane = ref.read(paneProvider(0));
        final ctrl = ref.read(paneProvider(0).notifier);
        if (pane.activeIsConsole) {
          // Back on a console tab closes it (there's always a browser tab
          // beneath — the console is opened on top of one).
          ctrl.closeTab(pane.activeTab);
        } else if (pane.path.isNotEmpty) {
          ctrl.up();
        } else {
          ctrl.clear();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: switch (_tab) {
            0 => const _MobileFiles(),
            1 => const _MobileTransfers(),
            _ => const _MobileSettings(),
          },
        ),
        floatingActionButton: fabVisible
            ? FloatingActionButton(
                onPressed: () => showMobileCreateSheet(context, ref, fabPane),
                tooltip: 'Add',
                child: const Icon(Icons.add),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: 'Files',
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_vert),
              label: 'Transfers',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

/// Files tab: the engine gate until ready, then the locations list, then the
/// browser once a location/remote is open.
class _MobileFiles extends ConsumerWidget {
  const _MobileFiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineControllerProvider);
    if (engine.phase != EnginePhase.ready) {
      return EngineGate(engine: engine);
    }
    final browsing = ref.watch(
      paneProvider(0).select((s) => s.remote != null || s.activeIsConsole),
    );
    // Split mode keeps the browser on screen even if pane 0 is cleared, so
    // clearing one pane doesn't tear down the whole split.
    final split = ref.watch(mobileSplitProvider);
    return (browsing || split)
        ? const _MobileBrowser()
        : const _MobileLocations();
  }
}

// ── Locations ────────────────────────────────────────────────────────────────

class _MobileLocations extends ConsumerWidget {
  const _MobileLocations();

  void _open(WidgetRef ref, Remote r) =>
      ref.read(paneProvider(0).notifier).open(r);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final remotes = ref.watch(remotesProvider);
    final locations = ref.watch(userLocationsProvider);
    final drives = ref.watch(drivesProvider);
    final needsAccess =
        Platform.isAndroid &&
        ref.watch(allFilesAccessProvider).valueOrNull == false;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x4,
        vertical: Space.x2,
      ),
      children: [
        Row(
          children: [
            Icon(Icons.cloud_sync_outlined, size: 22, color: c.primary),
            const SizedBox(width: Space.x2),
            Text(
              'Airclone',
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // Advanced: open the rclone command console (parity with desktop).
            // Reachable here so it doesn't require opening a location first to
            // reveal the tab strip's console button. Opening it makes pane 0's
            // active tab a console, which flips the Files tab to the browser.
            if (ref.watch(advancedModeProvider))
              IconButton(
                onPressed: () =>
                    ref.read(paneProvider(0).notifier).newConsoleTab(),
                icon: Icon(Icons.terminal, size: 20, color: c.textMuted),
                tooltip: 'Open console',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (needsAccess) const StorageAccessBanner(),
        _header(c, 'This phone'),
        for (final d in drives) _tile(context, ref, d.remote, d.kind),
        for (final l in locations) _tile(context, ref, l.remote, l.kind),
        _header(
          c,
          'Cloud',
          trailing: IconButton(
            icon: Icon(Icons.add, size: 22, color: c.textMuted),
            tooltip: 'Add, encrypt, or import a remote',
            onPressed: () => showMobileAddRemoteSheet(context),
          ),
        ),
        ...remotes.when(
          data: (list) => [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.x3),
                child: Text(
                  'No cloud remotes yet — tap + to connect one.',
                  style: TextStyle(color: c.textFaint, fontSize: 13),
                ),
              ),
            for (final r in list)
              _tile(context, ref, r, null, cloudActions: true),
          ],
          loading: () => const [
            Padding(
              padding: EdgeInsets.all(Space.x4),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ],
          error: (e, _) => [
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Text('$e', style: TextStyle(color: c.error, fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _header(AircloneColors c, String label, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: Space.x4, bottom: Space.x1),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: c.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    Remote r,
    LocalKind? kind, {
    bool cloudActions = false,
  }) {
    final c = AircloneTheme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.x2),
      visualDensity: VisualDensity.compact,
      leading: Icon(
        kind != null ? _kindIcon(kind) : Icons.cloud_outlined,
        color: c.primary,
      ),
      title: Text(
        r.name,
        style: TextStyle(color: c.text, fontWeight: FontWeight.w500),
      ),
      subtitle: r.isLocal
          ? null
          : Text(r.type, style: TextStyle(color: c.textFaint, fontSize: 12)),
      trailing: cloudActions
          ? IconButton(
              icon: Icon(Icons.more_vert, size: 20, color: c.textFaint),
              tooltip: 'Remote actions',
              onPressed: () => showMobileRemoteSheet(context, ref, r),
            )
          : null,
      onTap: () => _open(ref, r),
    );
  }

  IconData _kindIcon(LocalKind kind) => switch (kind) {
    LocalKind.home => Icons.home_outlined,
    LocalKind.desktop => Icons.desktop_windows_outlined,
    LocalKind.documents => Icons.description_outlined,
    LocalKind.downloads => Icons.download_outlined,
    LocalKind.pictures => Icons.image_outlined,
    LocalKind.videos => Icons.movie_outlined,
    LocalKind.music => Icons.library_music_outlined,
    LocalKind.drive => Icons.smartphone_outlined,
    LocalKind.root => Icons.smartphone_outlined,
    LocalKind.folder => Icons.folder_outlined,
  };
}

// ── Browser ──────────────────────────────────────────────────────────────────

/// The phone browser. Single-pane by default — pane 0 with its slim header +
/// tab strip. The primary header's split toggle reveals an opt-in second pane
/// (paneProvider(1)) shown with a resizable, adaptively-oriented [PaneSplit];
/// each pane keeps its own slim header so both stay independently navigable.
class _MobileBrowser extends ConsumerWidget {
  const _MobileBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(mobileSplitProvider);
    if (!split) {
      return const _MobilePaneColumn(index: 0, primary: true, withTabs: true);
    }
    final orientation = ref.watch(paneSplitOrientationProvider);
    return LayoutBuilder(
      builder: (context, cons) {
        // Adaptive: side-by-side on a wide (tablet/landscape) area, stacked on
        // a narrow (portrait phone) one. A manual choice overrides the width.
        final axis = resolveSplitAxis(orientation, cons.maxWidth);
        return PaneSplit(
          axis: axis,
          first: const _MobilePaneColumn(
            index: 0,
            primary: true,
            withTabs: true,
          ),
          second: const _MobilePaneColumn(
            index: 1,
            primary: false,
            withTabs: false,
          ),
        );
      },
    );
  }
}

/// One pane in the phone browser: its slim [_MobilePaneHeader], the (pane-0)
/// [PaneTabStrip], then the shared [BrowserPane] body with its desktop toolbar
/// and internal tab strip suppressed — the header + strip above own those.
class _MobilePaneColumn extends StatelessWidget {
  const _MobilePaneColumn({
    required this.index,
    required this.primary,
    required this.withTabs,
  });
  final int index;
  final bool primary;
  final bool withTabs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MobilePaneHeader(index: index, primary: primary),
        if (withTabs) PaneTabStrip(index: index, touch: true),
        Expanded(
          child: BrowserPane(index: index, showToolbar: false, showTabs: false),
        ),
      ],
    );
  }
}

/// The slim per-pane phone header: back/up · the folder title · search · an
/// overflow menu (refresh · paste · view mode). The [primary] pane also carries
/// the split toggle (+ orientation cycle when split), the secondary pane a
/// close-split button. On a narrow (forced side-by-side) pane the trailing
/// icons fold into the overflow so the row never overflows.
class _MobilePaneHeader extends ConsumerWidget {
  const _MobilePaneHeader({required this.index, required this.primary});
  final int index;
  final bool primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(paneProvider(index));
    final ctrl = ref.read(paneProvider(index).notifier);
    final remote = state.remote;
    final hasRemote = remote != null;
    // A console tab has an empty browser state (remote == null) but IS content —
    // give it its own header treatment instead of the inert "pick a location".
    final isConsole = state.activeIsConsole;

    // Multi-select active on touch → the header becomes the selection action bar.
    if (isTouchPrimary && state.selected.isNotEmpty) {
      return _selectionBar(context, ref, c, state);
    }

    final folder = !hasRemote
        ? 'Home'
        : (state.path.isEmpty ? remote.name : state.path.split('/').last);
    final subtitle = !hasRemote
        ? 'Pick a location'
        : (state.path.isEmpty ? remote.type : '${remote.name}/${state.path}');

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: Space.x1),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: LayoutBuilder(
        builder: (context, cons) {
          // Fold the trailing icons into the overflow when the pane is too
          // narrow to lay them out inline (forced side-by-side on a phone).
          final compact = cons.maxWidth < 300;
          return Row(
            children: [
              IconButton(
                onPressed: isConsole
                    ? () => ctrl.closeTab(state.activeTab)
                    : !hasRemote
                    ? null
                    : () => state.path.isEmpty ? ctrl.clear() : ctrl.up(),
                icon: Icon(
                  isConsole ? Icons.close : Icons.arrow_back,
                  size: 22,
                ),
                color: c.text,
                tooltip: isConsole
                    ? 'Close console'
                    : (state.path.isEmpty ? 'All locations' : 'Up'),
              ),
              Expanded(
                // Console tab → a plain "Console" title. A remote is open → a
                // clickable, scrollable breadcrumb so you can jump to any ancestor
                // (or the remote root) in one tap. Otherwise → the Home title.
                child: isConsole
                    ? Row(
                        children: [
                          Icon(Icons.terminal, size: 18, color: c.textMuted),
                          const SizedBox(width: Space.x2),
                          Text(
                            'Console',
                            style: TextStyle(
                              color: c.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : hasRemote
                    ? _Breadcrumb(
                        rootLabel: remote.name,
                        segments: state.segments,
                        onTap: ctrl.goToSegment,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            folder,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textFaint, fontSize: 11),
                          ),
                        ],
                      ),
              ),
              if (!compact && hasRemote)
                IconButton(
                  onPressed: () => mobileFolderSearch(context, ref, index),
                  icon: const Icon(Icons.search, size: 20),
                  color: c.textMuted,
                  tooltip: 'Search this folder',
                ),
              // Inline quick view-mode toggle: tap to cycle List → Grid →
              // Gallery. The explicit chooser also lives in the ⋯ sheet.
              if (!compact && hasRemote)
                IconButton(
                  onPressed: () => ctrl.setViewMode(_nextView(state.viewMode)),
                  icon: Icon(_viewIcon(state.viewMode), size: 20),
                  color: c.textMuted,
                  tooltip: 'View: ${_viewLabel(state.viewMode)}',
                ),
              // Always present: the ⋯ sheet is never empty — a primary pane
              // always has the Layout (split) section and a secondary always has
              // "Close second pane", even with no remote/console open. Gating it
              // on hasRemote previously stranded the split controls.
              IconButton(
                onPressed: () => showMobileActionsSheet(
                  context,
                  ref,
                  index,
                  primary: primary,
                  compact: compact,
                ),
                icon: Icon(Icons.more_vert, size: 20, color: c.textMuted),
                tooltip: 'More actions',
              ),
            ],
          );
        },
      ),
    );
  }

  /// Touch multi-select: the header morphs into this action bar — close, the live
  /// count, select-all, and the bulk verbs (copy · cut · delete) over the current
  /// selection. Copy/Cut drop the selection and confirm with a snackbar
  /// ("… tap + → Paste"); Delete confirms, deletes, then clears.
  Widget _selectionBar(
    BuildContext context,
    WidgetRef ref,
    AircloneColors c,
    BrowserState state,
  ) {
    final ctrl = ref.read(paneProvider(index).notifier);
    final n = state.selected.length;
    final visible = state.visibleEntries.length;
    final allSelected = visible > 0 && n >= visible;
    final plural = n == 1 ? '' : 's';

    void snack(String msg) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: Space.x1),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: ctrl.clearSelection,
            icon: const Icon(Icons.close, size: 22),
            color: c.text,
            tooltip: 'Clear selection',
          ),
          Expanded(
            child: Text(
              '$n selected',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () =>
                allSelected ? ctrl.clearSelection() : ctrl.selectAll(),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              allSelected ? Icons.deselect : Icons.select_all,
              size: 22,
            ),
            color: c.textMuted,
            tooltip: allSelected ? 'Deselect all' : 'Select all',
          ),
          IconButton(
            onPressed: () {
              selectionClip(ref, index, cut: false);
              ctrl.clearSelection();
              snack('Copied $n item$plural — open a folder and tap + → Paste');
            },
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_outlined, size: 22),
            color: c.textMuted,
            tooltip: 'Copy',
          ),
          IconButton(
            onPressed: () {
              selectionClip(ref, index, cut: true);
              ctrl.clearSelection();
              snack(
                'Cut $n item$plural — open a folder and tap + → Paste to move',
              );
            },
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.content_cut, size: 22),
            color: c.textMuted,
            tooltip: 'Cut',
          ),
          IconButton(
            onPressed: () async {
              final r = await selectionDelete(context, ref, index);
              if (!r.ran) return;
              ctrl.clearSelection();
              if (r.failed > 0 && context.mounted) {
                snack(
                  "Couldn't delete ${r.failed} item${r.failed == 1 ? '' : 's'}.",
                );
              }
            },
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 22),
            color: c.error,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  IconData _viewIcon(ViewMode m) => switch (m) {
    ViewMode.list => Icons.view_list_outlined,
    ViewMode.grid => Icons.grid_view_outlined,
    ViewMode.media => Icons.photo_library_outlined,
  };

  ViewMode _nextView(ViewMode m) => switch (m) {
    ViewMode.list => ViewMode.grid,
    ViewMode.grid => ViewMode.media,
    ViewMode.media => ViewMode.list,
  };

  String _viewLabel(ViewMode m) => switch (m) {
    ViewMode.list => 'List',
    ViewMode.grid => 'Grid',
    ViewMode.media => 'Gallery',
  };
}

/// A horizontally-scrollable folder breadcrumb for the phone header:
/// `[remote] › sub › sub-sub`. Tapping the root chip or any ancestor navigates
/// there via the pane controller (`goToSegment`, where -1 = the remote root and
/// `i` = the i-th path segment). The last crumb is the current folder (not
/// tappable), and the row auto-scrolls to the end so the deepest folder shows.
class _Breadcrumb extends StatefulWidget {
  const _Breadcrumb({
    required this.rootLabel,
    required this.segments,
    required this.onTap,
  });

  final String rootLabel;
  final List<String> segments;

  /// -1 = the remote root; 0..n-1 = that path segment.
  final void Function(int index) onTap;

  @override
  State<_Breadcrumb> createState() => _BreadcrumbState();
}

class _BreadcrumbState extends State<_Breadcrumb> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _jumpToEnd();
  }

  @override
  void didUpdateWidget(_Breadcrumb old) {
    super.didUpdateWidget(old);
    // Navigating deeper/shallower changes the crumbs — keep the current folder
    // (the tail) in view.
    _jumpToEnd();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final segs = widget.segments;
    final crumbs = <Widget>[
      _crumb(
        c,
        widget.rootLabel,
        current: segs.isEmpty,
        onTap: () => widget.onTap(-1),
        root: true,
      ),
    ];
    for (var i = 0; i < segs.length; i++) {
      crumbs.add(Icon(Icons.chevron_right, size: 16, color: c.textFaint));
      crumbs.add(
        _crumb(
          c,
          segs[i],
          current: i == segs.length - 1,
          onTap: () => widget.onTap(i),
        ),
      );
    }
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
    );
  }

  Widget _crumb(
    AircloneColors c,
    String label, {
    required bool current,
    required VoidCallback onTap,
    bool root = false,
  }) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (root) ...[
          Icon(
            Icons.folder_outlined,
            size: 15,
            color: current ? c.text : c.textMuted,
          ),
          const SizedBox(width: Space.x1),
        ],
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: current ? c.text : c.textMuted,
            fontSize: 15,
            fontWeight: current ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
    // The current folder isn't a link (you're already here); ancestors are.
    if (current) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: content,
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: content,
      ),
    );
  }
}

// ── Transfers ────────────────────────────────────────────────────────────────

class _MobileTransfers extends ConsumerStatefulWidget {
  const _MobileTransfers();

  @override
  ConsumerState<_MobileTransfers> createState() => _MobileTransfersState();
}

class _MobileTransfersState extends ConsumerState<_MobileTransfers> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Space.x3),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Transfers')),
              ButtonSegment(value: 1, label: Text('Recent')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
            showSelectedIcon: false,
          ),
        ),
        Divider(height: 1, color: c.border),
        Expanded(
          child: _tab == 0
              ? Column(
                  children: [
                    if (ref.watch(statsProvider.select((s) => s.isActive)))
                      const SizedBox(
                        height: 100,
                        child: Padding(
                          padding: EdgeInsets.all(Space.x2),
                          child: StatsPanel(),
                        ),
                      ),
                    const Expanded(child: JobsPanel()),
                  ],
                )
              : const RecentActivityPanel(),
        ),
      ],
    );
  }
}

// ── Settings ─────────────────────────────────────────────────────────────────

class _MobileSettings extends StatelessWidget {
  const _MobileSettings();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(Space.x4),
      child: SettingsContent(embedded: true),
    );
  }
}
