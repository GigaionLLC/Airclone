import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/advanced_mode.dart';
import '../state/android_native.dart';
import '../state/browser_controller.dart';
import '../state/clipboard_controller.dart';
import '../state/engine_controller.dart';
import '../state/local_locations.dart';
import '../state/pane_layout.dart';
import '../state/remotes_provider.dart';
import '../state/stats_controller.dart';
import 'add_remote_dialog.dart';
import 'browser_pane.dart';
import 'connection_test_dialog.dart';
import 'encrypt_remote_dialog.dart';
import 'scan_from_desktop_sheet.dart';
import 'engine_gate.dart';
import 'jobs_panel.dart';
import 'mobile_features_sheet.dart';
import 'pane_split.dart';
import 'paste_action.dart';
import 'recent_activity_panel.dart';
import 'search_dialog.dart';
import 'settings_screen.dart';
import 'stats_panel.dart';
import 'tab_strip.dart';
import 'theme/tokens.dart';

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
    // System back: leave a folder, then leave the remote, then leave a non-Files
    // tab — only exit the app from the Files tab's locations list (never while a
    // split is up: back collapses that first).
    final canPop = _tab == 0 && (gated || (!browsing && !split));
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
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
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.add, size: 20, color: c.textMuted),
            tooltip: 'Add, encrypt, or import a remote',
            onSelected: (v) {
              switch (v) {
                case 'add':
                  showAddRemoteDialog(context);
                case 'encrypt':
                  showEncryptRemoteDialog(context);
                case 'qr':
                  // Phone-first on-ramp: pull remotes off a computer by scanning
                  // its "Send to phone" QR (config-portability plan §5).
                  showScanFromDesktopSheet(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add', child: Text('Add a remote…')),
              PopupMenuItem(value: 'encrypt', child: Text('Encrypt a remote…')),
              PopupMenuItem(
                value: 'qr',
                child: Text('Import from a computer (QR)…'),
              ),
            ],
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
          ? PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: c.textFaint),
              onSelected: (v) async {
                switch (v) {
                  case 'test':
                    final client = ref.read(engineControllerProvider).client;
                    if (client != null) showConnectionTest(context, client, r);
                  case 'edit':
                    await showEditRemoteDialog(context, r);
                  case 'delete':
                    await _deleteRemote(context, ref, r);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'test', child: Text('Test connection')),
                PopupMenuItem(value: 'edit', child: Text('Edit remote…')),
                PopupMenuItem(value: 'delete', child: Text('Delete remote')),
              ],
            )
          : null,
      onTap: () => _open(ref, r),
    );
  }

  /// Confirms then removes a remote from the rclone config (cloud files are
  /// untouched) — the phone-sized twin of the desktop sidebar action.
  Future<void> _deleteRemote(
    BuildContext context,
    WidgetRef ref,
    Remote remote,
  ) async {
    final c = AircloneTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Delete "${remote.name}"?'),
        content: const Text(
          'This removes the remote from your rclone config. Files stored in '
          'the cloud are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.error),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      await client.rpc('config/delete', {'name': remote.name});
    } catch (_) {
      /* surfaced via the (unchanged) list if it fails */
    }
    if (ref.read(paneProvider(0)).remote == remote) {
      ref.read(paneProvider(0).notifier).clear();
    }
    ref.invalidate(remotesProvider);
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
    final split = ref.watch(mobileSplitProvider);
    final orientation = ref.watch(paneSplitOrientationProvider);
    final clipEmpty = ref.watch(
      clipboardControllerProvider.select((s) => s.isEmpty),
    );

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
          final showOverflow = hasRemote || compact;
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
                  onPressed: () => _search(context, ref),
                  icon: const Icon(Icons.search, size: 20),
                  color: c.textMuted,
                  tooltip: 'Search this folder',
                ),
              if (!compact && primary)
                IconButton(
                  onPressed: () => _toggleSplit(ref),
                  icon: Icon(
                    split ? Icons.splitscreen : Icons.splitscreen_outlined,
                    size: 20,
                  ),
                  color: split ? c.primary : c.textMuted,
                  tooltip: split ? 'Close split view' : 'Split view',
                ),
              if (!compact && primary && split)
                IconButton(
                  onPressed: () =>
                      ref.read(paneSplitOrientationProvider.notifier).cycle(),
                  icon: Icon(_orientationIcon(orientation), size: 20),
                  color: c.textMuted,
                  tooltip: 'Layout: ${orientation.label}',
                ),
              if (!compact && !primary)
                IconButton(
                  onPressed: () => _closeSplit(ref),
                  icon: const Icon(Icons.close_fullscreen, size: 18),
                  color: c.textMuted,
                  tooltip: 'Close second pane',
                ),
              if (showOverflow)
                _overflow(
                  context,
                  ref,
                  c,
                  state: state,
                  hasRemote: hasRemote,
                  clipEmpty: clipEmpty,
                  compact: compact,
                  split: split,
                  orientation: orientation,
                ),
            ],
          );
        },
      ),
    );
  }

  /// The overflow (⋯) menu. Always holds the folder verbs (refresh · paste ·
  /// view mode); in [compact] mode it also absorbs search and the split
  /// controls that the roomy header shows as dedicated icons.
  Widget _overflow(
    BuildContext context,
    WidgetRef ref,
    AircloneColors c, {
    required BrowserState state,
    required bool hasRemote,
    required bool clipEmpty,
    required bool compact,
    required bool split,
    required PaneSplitOrientation orientation,
  }) {
    final ctrl = ref.read(paneProvider(index).notifier);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 20, color: c.textMuted),
      onSelected: (v) async {
        switch (v) {
          case 'features':
            await showMobileFeaturesSheet(context, ref, index);
          case 'search':
            _search(context, ref);
          case 'refresh':
            await ctrl.refresh();
          case 'paste':
            if (context.mounted) {
              await pasteClipboardInto(
                context,
                ref,
                dest: ref.read(paneProvider(index)),
                paneIndex: index,
              );
            }
          case 'view-list':
            ctrl.setViewMode(ViewMode.list);
          case 'view-grid':
            ctrl.setViewMode(ViewMode.grid);
          case 'view-media':
            ctrl.setViewMode(ViewMode.media);
          case 'split-toggle':
            _toggleSplit(ref);
          case 'split-close':
            _closeSplit(ref);
          case 'orient-adaptive':
            ref
                .read(paneSplitOrientationProvider.notifier)
                .set(PaneSplitOrientation.adaptive);
          case 'orient-side':
            ref
                .read(paneSplitOrientationProvider.notifier)
                .set(PaneSplitOrientation.sideBySide);
          case 'orient-stack':
            ref
                .read(paneSplitOrientationProvider.notifier)
                .set(PaneSplitOrientation.stacked);
        }
      },
      itemBuilder: (_) => [
        if (hasRemote) ...[
          const PopupMenuItem(value: 'features', child: Text('All features…')),
          const PopupMenuDivider(),
        ],
        if (compact && hasRemote)
          const PopupMenuItem(
            value: 'search',
            child: Text('Search this folder'),
          ),
        if (hasRemote) ...[
          const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
          PopupMenuItem(
            value: 'paste',
            enabled: !clipEmpty,
            child: const Text('Paste here'),
          ),
          const PopupMenuDivider(),
          _viewItem('view-list', 'List', ViewMode.list, state),
          _viewItem('view-grid', 'Grid', ViewMode.grid, state),
          _viewItem('view-media', 'Gallery', ViewMode.media, state),
        ],
        if (compact && primary) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'split-toggle',
            child: Text(split ? 'Close split view' : 'Split view'),
          ),
          if (split) ...[
            _orientItem(
              'orient-adaptive',
              'Adaptive layout',
              PaneSplitOrientation.adaptive,
              orientation,
            ),
            _orientItem(
              'orient-side',
              'Side by side',
              PaneSplitOrientation.sideBySide,
              orientation,
            ),
            _orientItem(
              'orient-stack',
              'Stacked',
              PaneSplitOrientation.stacked,
              orientation,
            ),
          ],
        ],
        if (compact && !primary) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'split-close',
            child: Text('Close second pane'),
          ),
        ],
      ],
    );
  }

  /// Turn the second pane on/off. Turning it *off* drops the (now hidden) pane
  /// as the active one so selection/paste targets fall back to pane 0.
  void _toggleSplit(WidgetRef ref) {
    final on = ref.read(mobileSplitProvider);
    ref.read(mobileSplitProvider.notifier).state = !on;
    if (on) ref.read(activePaneProvider.notifier).state = 0;
  }

  void _closeSplit(WidgetRef ref) {
    ref.read(mobileSplitProvider.notifier).state = false;
    ref.read(activePaneProvider.notifier).state = 0;
  }

  IconData _orientationIcon(PaneSplitOrientation o) => switch (o) {
    PaneSplitOrientation.adaptive => Icons.auto_awesome_mosaic_outlined,
    PaneSplitOrientation.sideBySide => Icons.view_column_outlined,
    PaneSplitOrientation.stacked => Icons.view_agenda_outlined,
  };

  PopupMenuItem<String> _viewItem(
    String value,
    String label,
    ViewMode mode,
    BrowserState state,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: state.viewMode == mode
              ? const Icon(Icons.check, size: 16)
              : null,
        ),
        Text(label),
      ],
    ),
  );

  PopupMenuItem<String> _orientItem(
    String value,
    String label,
    PaneSplitOrientation mode,
    PaneSplitOrientation current,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: current == mode ? const Icon(Icons.check, size: 16) : null,
        ),
        Text(label),
      ],
    ),
  );

  /// Recursive search rooted at this pane's current folder; opening a match
  /// navigates to it (same behavior as the desktop Ctrl+Shift+F).
  void _search(BuildContext context, WidgetRef ref) {
    final state = ref.read(paneProvider(index));
    final remote = state.remote;
    final client = ref.read(engineControllerProvider).client;
    if (remote == null || client == null) return;
    final basePath = state.path;
    showSearchDialog(
      context,
      client: client,
      fs: remote.fs,
      label: basePath.isEmpty ? remote.name : '${remote.name}/$basePath',
      basePath: basePath,
      onOpen: (RcloneFile m) async {
        final pane = ref.read(paneProvider(index).notifier);
        final abs = basePath.isEmpty ? m.path : '$basePath/${m.path}';
        if (m.isDir) {
          await pane.navigateTo(abs);
          return;
        }
        final slash = abs.lastIndexOf('/');
        final parent = slash < 0 ? '' : abs.substring(0, slash);
        if (parent != ref.read(paneProvider(index)).path) {
          await pane.navigateTo(parent);
        }
        pane.selectOnly(m.name);
      },
    );
  }
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
