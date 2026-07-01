import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import '../state/advanced_mode.dart';
import '../state/app_info.dart';
import '../state/bookmarks_controller.dart';
import '../state/browser_controller.dart';
import '../state/bw_schedule_controller.dart';
import '../state/clipboard_controller.dart';
import '../state/engine_controller.dart';
import '../state/file_ops.dart';
import '../state/jobs_controller.dart';
import '../state/local_locations.dart';
import '../state/mount_policy.dart';
import '../state/recent_locations.dart';
import '../state/remote_about.dart';
import '../state/remotes_provider.dart';
import '../state/scheduler_controller.dart';
import '../state/serve_policy.dart';
import '../state/stats_controller.dart';
import 'add_remote_dialog.dart';
import 'bandwidth_control.dart';
import 'browser_pane.dart';
import 'command_palette.dart';
import 'dedupe_dialog.dart';
import 'encrypt_remote_dialog.dart';
import 'file_op_dialogs.dart';
import 'format.dart';
import 'native_drag.dart';
import 'inspector_panel.dart';
import 'jobs_panel.dart';
import 'mount_panel.dart';
import 'pane_drag.dart';
import 'paste_action.dart';
import 'quick_look.dart';
import 'recent_activity_panel.dart';
import 'search_dialog.dart';
import 'serve_panel.dart';
import 'settings_screen.dart';
import 'shortcuts_dialog.dart';
import 'stats_panel.dart';
import 'tasks_panel.dart';
import 'theme/tokens.dart';

/// Whether the explorer shows a single wide pane (default, Spacedrive-like) or
/// the dual-pane commander. Toggled from the top bar.
final singlePaneProvider = StateProvider<bool>((ref) => true);

/// Whether the left locations sidebar is visible.
final sidebarVisibleProvider = StateProvider<bool>((ref) => true);

/// Current width of the left sidebar (drag the divider to resize).
final sidebarWidthProvider = StateProvider<double>((ref) => 240);

/// The desktop shell: top bar · [ locations sidebar | explorer | inspector ] · jobs
/// dock · status bar. The explorer is single-pane by default with a dual-pane toggle.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _jobsExpanded = true;

  // Type-to-navigate: accumulate typed chars briefly, then jump to the match.
  String _typeBuffer = '';
  Timer? _typeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(engineControllerProvider.notifier).bootstrap();
      // Arm the lazy timer-owning providers (scheduled tasks + bandwidth
      // schedule) so they tick while the app is open.
      ref.read(schedulerProvider);
      ref.read(bwScheduleControllerProvider);
      // Load persisted favorites so the command palette has them ready.
      ref.read(bookmarksProvider);
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  /// Printable keystrokes (no modifiers, not space) jump-select the first entry
  /// in the active pane starting with the typed prefix, and scroll to it (list).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final hk = HardwareKeyboard.instance;
    if (hk.isControlPressed || hk.isAltPressed || hk.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final ch = event.character;
    if (ch == null || ch.length != 1 || ch.codeUnitAt(0) <= 0x20) {
      return KeyEventResult.ignored; // skip space + control chars
    }
    _typeBuffer += ch.toLowerCase();
    _typeTimer?.cancel();
    _typeTimer = Timer(
      const Duration(milliseconds: 800),
      () => _typeBuffer = '',
    );
    _typeaheadJump();
    return KeyEventResult.handled;
  }

  void _typeaheadJump() {
    final idx = ref.read(activePaneProvider);
    final st = ref.read(paneProvider(idx));
    final entries = st.visibleEntries;
    final i = entries.indexWhere(
      (e) => e.name.toLowerCase().startsWith(_typeBuffer),
    );
    if (i < 0) return;
    ref.read(paneProvider(idx).notifier).selectOnly(entries[i].name);
    if (st.viewMode == ViewMode.list) {
      final sc = ref.read(paneScrollProvider(idx));
      if (sc.hasClients) {
        final target = (i * 36.0).clamp(0.0, sc.position.maxScrollExtent);
        sc.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    }
  }

  /// Quick Look the active pane's selection (first selected file), navigable
  /// across the listing. No-op when nothing is selected.
  void _quickLookActive() {
    final idx = ref.read(activePaneProvider);
    final st = ref.read(paneProvider(idx));
    final remote = st.remote;
    if (remote == null) return;
    final sel = st.selectedEntries.where((e) => !e.isDir).toList();
    if (sel.isEmpty) return;
    final entries = st.visibleEntries;
    final start = entries.indexOf(sel.first);
    showQuickLook(context, remote, st.path, entries, start < 0 ? 0 : start);
  }

  /// Enter on the active pane: open the single selected folder, else Quick Look
  /// the selected file(s).
  void _openActiveSelection() {
    final idx = ref.read(activePaneProvider);
    final st = ref.read(paneProvider(idx));
    if (st.remote == null) return;
    final sel = st.selectedEntries;
    if (sel.length == 1 && sel.first.isDir) {
      ref.read(paneProvider(idx).notifier).enterDir(sel.first);
    } else {
      _quickLookActive();
    }
  }

  /// F2 on the active pane: rename the single selected entry.
  Future<void> _renameActiveSelection() async {
    final idx = ref.read(activePaneProvider);
    final st = ref.read(paneProvider(idx));
    if (st.remote == null) return;
    final sel = st.selectedEntries;
    if (sel.length != 1) return; // rename targets exactly one entry
    final f = sel.first;
    final name = await showRenameDialog(
      context,
      f.name,
      taken: {
        for (final e in st.entries)
          if (e.name != f.name) e.name,
      },
    );
    if (name == null || name == f.name) return;
    await ref.read(fileOpsProvider).rename(st.remote!, f.path, name);
    await ref.read(paneProvider(idx).notifier).refresh();
  }

  /// Ctrl+C / Ctrl+X: stage the active pane's selection on the shared clipboard.
  void _clipboardStage({required bool cut}) {
    final idx = ref.read(activePaneProvider);
    final st = ref.read(paneProvider(idx));
    if (st.remote == null) return;
    final sel = st.selectedEntries;
    if (sel.isEmpty) return;
    final clip = ref.read(clipboardControllerProvider.notifier);
    cut
        ? clip.cut(st.remote!, st.path, sel)
        : clip.copy(st.remote!, st.path, sel);
  }

  /// Ctrl+V: paste the clipboard into the active pane (copy, or move for a cut),
  /// asking how to resolve name collisions. Shared with the per-pane menu.
  Future<void> _pasteIntoActive() async {
    final idx = ref.read(activePaneProvider);
    await pasteClipboardInto(
      context,
      ref,
      dest: ref.read(paneProvider(idx)),
      paneIndex: idx,
    );
  }

  /// Delete on the active pane: confirm, then delete every selected entry.
  Future<void> _deleteActiveSelection() async {
    final idx = ref.read(activePaneProvider);
    final st = ref.read(paneProvider(idx));
    if (st.remote == null) return;
    final sel = st.selectedEntries;
    if (sel.isEmpty) return;
    final ok = sel.length == 1
        ? await showDeleteConfirm(
            context,
            sel.first.name,
            isDir: sel.first.isDir,
          )
        : await showDeleteConfirm(context, '${sel.length} items');
    if (!ok) return;
    final ops = ref.read(fileOpsProvider);
    for (final f in sel) {
      await ops.deleteEntry(st.remote!, f, st.path);
    }
    await ref.read(paneProvider(idx).notifier).refresh();
  }

  /// Ctrl+Shift+F: recursively search the active pane's current folder, then
  /// reveal the chosen match (navigate into a folder, or open the file's parent
  /// folder and select it).
  void _openSearch() {
    final idx = ref.read(activePaneProvider);
    final st = ref.read(paneProvider(idx));
    final remote = st.remote;
    final client = ref.read(engineControllerProvider).client;
    if (remote == null || client == null) return;
    final basePath = st.path;
    showSearchDialog(
      context,
      client: client,
      fs: remote.fs,
      label: basePath.isEmpty ? remote.name : '${remote.name}/$basePath',
      basePath: basePath,
      onOpen: (RcloneFile m) async {
        final pane = ref.read(paneProvider(idx).notifier);
        final abs = basePath.isEmpty ? m.path : '$basePath/${m.path}';
        if (m.isDir) {
          await pane.navigateTo(abs);
          return;
        }
        final slash = abs.lastIndexOf('/');
        final parent = slash < 0 ? '' : abs.substring(0, slash);
        // Skip the reload when the match is already in the displayed folder.
        if (parent != ref.read(paneProvider(idx)).path) {
          await pane.navigateTo(parent);
        }
        pane.selectOnly(m.name);
        // Scroll the revealed row into view once the (possibly new) listing
        // has laid out — mirrors type-to-navigate.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollSelectedIntoView(idx),
        );
      },
    );
  }

  /// Animate the active pane's list to the first selected row (list view only).
  void _scrollSelectedIntoView(int idx) {
    final st = ref.read(paneProvider(idx));
    if (st.viewMode != ViewMode.list) return;
    final entries = st.visibleEntries;
    final i = entries.indexWhere((e) => st.selected.contains(e.name));
    if (i < 0) return;
    final sc = ref.read(paneScrollProvider(idx));
    if (sc.hasClients) {
      final target = (i * 36.0).clamp(0.0, sc.position.maxScrollExtent);
      sc.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  /// Scan the active pane's folder for content-identical duplicate files and
  /// let the user delete redundant copies. Refreshes the pane after deletes.
  void _openDedupe() {
    final idx = ref.read(activePaneProvider);
    final st = ref.read(paneProvider(idx));
    final remote = st.remote;
    final client = ref.read(engineControllerProvider).client;
    if (remote == null || client == null) return;
    showDedupeDialog(
      context,
      client: client,
      fs: remote.fs,
      label: st.path.isEmpty ? remote.name : '${remote.name}/${st.path}',
      basePath: st.path,
      onChanged: () => ref.read(paneProvider(idx).notifier).refresh(),
    );
  }

  /// Records a pane's arrival at a new remote+folder into the recents list.
  /// Fires on the (fs, path) change (even while still loading) so navigation is
  /// captured immediately; ignores selection/loading-only state changes.
  void _recordNav(BrowserState? prev, BrowserState next) {
    final r = next.remote;
    if (r == null) return;
    final changed =
        prev == null || prev.remote?.fs != r.fs || prev.path != next.path;
    if (!changed) return;
    ref.read(recentLocationsProvider.notifier).record(r, next.path);
  }

  /// The Ctrl+K command-palette catalogue: app actions (gated the same way as
  /// their toolbar buttons) followed by a "Go to" entry per remote.
  List<PaletteAction> _paletteActions(BuildContext context) {
    final idx = ref.read(activePaneProvider);
    BrowserController pane() => ref.read(paneProvider(idx).notifier);
    final advanced = ref.read(advancedModeProvider);
    final remotes = ref.read(remotesProvider).valueOrNull ?? const [];
    final active = ref.read(paneProvider(idx));
    final activeRemote = active.remote;
    final bookmarks = ref.read(bookmarksProvider);
    final pinned =
        activeRemote != null &&
        ref
            .read(bookmarksProvider.notifier)
            .isPinned(activeRemote.fs, active.path);
    // Recents, minus the current folder and anything already shown as a favorite.
    final pinnedKeys = bookmarks.map((b) => b.key).toSet();
    final currentKey = activeRemote == null
        ? null
        : '${activeRemote.fs}|${active.path}';
    final recents = ref
        .read(recentLocationsProvider)
        .where((l) => l.key != currentKey && !pinnedKeys.contains(l.key))
        .take(8);

    return [
      if (activeRemote != null)
        PaletteAction(
          label: 'Search this folder…',
          icon: Icons.search,
          hint: 'Ctrl+Shift+F',
          keywords: 'find recursive subfolders',
          run: _openSearch,
        ),
      if (activeRemote != null)
        PaletteAction(
          label: 'Find duplicate files…',
          icon: Icons.content_copy_outlined,
          keywords: 'dedupe duplicates redundant copies reclaim space',
          run: _openDedupe,
        ),
      // Only offer to pin a real subfolder (a remote's root is already one tap
      // away via "Go to <remote>"). Unpin stays available wherever it's pinned.
      if (activeRemote != null && (active.path.isNotEmpty || pinned))
        PaletteAction(
          label: pinned
              ? 'Remove this folder from Favorites'
              : 'Pin this folder to Favorites',
          icon: pinned ? Icons.star : Icons.star_border,
          keywords: 'bookmark favourite pin shortcut',
          run: () {
            final b = ref.read(bookmarksProvider.notifier);
            if (pinned) {
              b.remove(activeRemote.fs, active.path);
            } else {
              b.add(
                Bookmark(
                  name: activeRemote.name,
                  type: activeRemote.type,
                  fs: activeRemote.fs,
                  path: active.path,
                  isLocal: activeRemote.isLocal,
                ),
              );
            }
          },
        ),
      for (final bm in bookmarks)
        PaletteAction(
          label: bm.label,
          icon: Icons.star,
          hint: 'Favorite',
          keywords: 'bookmark favourite pinned ${bm.type}',
          run: () async {
            await pane().open(bm.remote);
            if (bm.path.isNotEmpty) await pane().navigateTo(bm.path);
          },
        ),
      for (final loc in recents)
        PaletteAction(
          label: loc.label,
          icon: Icons.history,
          hint: 'Recent',
          keywords: 'recent history visited ${loc.remote.type}',
          run: () async {
            await pane().open(loc.remote);
            if (loc.path.isNotEmpty) await pane().navigateTo(loc.path);
          },
        ),
      PaletteAction(
        label: 'Add or encrypt a remote',
        icon: Icons.add,
        keywords: 'new cloud connection account crypt',
        run: () => showAddRemoteDialog(context),
      ),
      PaletteAction(
        label: 'Settings',
        icon: Icons.settings_outlined,
        keywords: 'preferences options theme skin advanced config',
        run: () => showSettingsDialog(context),
      ),
      PaletteAction(
        label: 'Keyboard shortcuts',
        icon: Icons.keyboard_outlined,
        hint: 'F1',
        keywords: 'help keys cheat sheet',
        run: () => showShortcutsDialog(context),
      ),
      PaletteAction(
        label: 'New tab',
        icon: Icons.tab,
        hint: 'Ctrl+T',
        run: () => pane().newTab(),
      ),
      PaletteAction(
        label: 'Toggle details pane',
        icon: Icons.info_outline,
        hint: 'Ctrl+I',
        keywords: 'inspector properties',
        run: () => ref.read(inspectorVisibleProvider.notifier).state = !ref
            .read(inspectorVisibleProvider),
      ),
      PaletteAction(
        label: 'Toggle sidebar',
        icon: Icons.menu,
        keywords: 'locations remotes show hide',
        run: () => ref.read(sidebarVisibleProvider.notifier).state = !ref.read(
          sidebarVisibleProvider,
        ),
      ),
      PaletteAction(
        label: 'Toggle dual-pane view',
        icon: Icons.splitscreen,
        keywords: 'commander split two panes',
        run: () => ref.read(singlePaneProvider.notifier).state = !ref.read(
          singlePaneProvider,
        ),
      ),
      if (advanced)
        PaletteAction(
          label: 'Saved tasks',
          icon: Icons.checklist_rounded,
          keywords: 'schedule jobs recurring',
          run: () => showTasksDialog(context),
        ),
      if (advanced && ref.read(serveEnabledProvider))
        PaletteAction(
          label: 'Serve / Share on LAN',
          icon: Icons.cast_connected,
          keywords: 'http webdav share network',
          run: () => showServeDialog(context),
        ),
      if (advanced && ref.read(mountEnabledProvider))
        PaletteAction(
          label: 'Mount as a drive',
          icon: Icons.usb,
          keywords: 'drive letter winfsp vfs',
          run: () => showMountDialog(context),
        ),
      for (final r in remotes)
        PaletteAction(
          label: 'Go to ${r.name}',
          icon: r.isLocal ? Icons.computer : Icons.cloud_outlined,
          hint: r.type,
          keywords: 'open browse remote location ${r.type}',
          run: () => pane().open(r),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    BrowserController activePane() =>
        ref.read(paneProvider(ref.read(activePaneProvider)).notifier);
    // When a transfer job finishes, re-list both panes so a just-copied/uploaded
    // file shows up without a manual refresh. (Transfers are async rclone jobs
    // that complete a moment after the drop.)
    // Record folder visits (per pane) for the command palette's "Recent" list.
    ref.listen(browserAProvider, _recordNav);
    ref.listen(browserBProvider, _recordNav);
    ref.listen(jobsControllerProvider, (prev, next) {
      final was = {for (final j in (prev ?? const [])) j.id: j.status};
      final justDone = next.any(
        (j) => j.status == JobStatus.success && was[j.id] != JobStatus.success,
      );
      if (justDone) {
        ref.read(browserAProvider.notifier).refresh();
        ref.read(browserBProvider.notifier).refresh();
      }
    });
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
              activePane().back(),
          const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
              activePane().forward(),
          const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
              activePane().up(),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              ref
                  .read(paneFilterFocusProvider(ref.read(activePaneProvider)))
                  .requestFocus(),
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
              ref.read(inspectorVisibleProvider.notifier).update((v) => !v),
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
              activePane().newTab(),
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
            final idx = ref.read(activePaneProvider);
            ref
                .read(paneProvider(idx).notifier)
                .closeTab(ref.read(paneProvider(idx)).activeTab);
          },
          const SingleActivator(LogicalKeyboardKey.space): _quickLookActive,
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
              activePane().selectAll(),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              activePane().clearSelection(),
          const SingleActivator(LogicalKeyboardKey.enter): _openActiveSelection,
          const SingleActivator(LogicalKeyboardKey.f2): _renameActiveSelection,
          const SingleActivator(LogicalKeyboardKey.delete):
              _deleteActiveSelection,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
              _clipboardStage(cut: false),
          const SingleActivator(LogicalKeyboardKey.keyX, control: true): () =>
              _clipboardStage(cut: true),
          const SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _pasteIntoActive,
          const SingleActivator(LogicalKeyboardKey.f1): () =>
              showShortcutsDialog(context),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              showCommandPalette(context, _paletteActions(context)),
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            control: true,
            shift: true,
          ): _openSearch,
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(
            children: [
              _TopBar(
                jobsExpanded: _jobsExpanded,
                onToggleJobs: () =>
                    setState(() => _jobsExpanded = !_jobsExpanded),
              ),
              Expanded(child: _ExplorerArea(jobsExpanded: _jobsExpanded)),
              const _StatusBar(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sidebar + work area. For the OS skins in single-pane mode the active
/// pane's toolbar is hoisted to a full-width band across the very top (the way
/// Explorer/Finder do it), so the sidebar starts *below* the toolbar instead of
/// running the entire left edge. Airclone keeps the toolbar beside the sidebar.
class _ExplorerArea extends ConsumerWidget {
  const _ExplorerArea({required this.jobsExpanded});
  final bool jobsExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chrome = AircloneTheme.chromeOf(context);
    final singlePane = ref.watch(singlePaneProvider);
    final engineReady =
        ref.watch(engineControllerProvider).phase == EnginePhase.ready;
    final hoist = chrome.toolbarAboveSidebar && singlePane && engineReady;

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ref.watch(sidebarVisibleProvider)) ...[
          SizedBox(
            width: ref.watch(sidebarWidthProvider),
            child: const _Sidebar(),
          ),
          const _SidebarResizeHandle(),
        ],
        Expanded(
          child: _WorkArea(jobsExpanded: jobsExpanded, hoistToolbar: hoist),
        ),
      ],
    );

    if (!hoist) return body;
    // Hoisted: toolbar across the top, then [sidebar | content] below it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneToolbar(index: ref.watch(activePaneProvider)),
        Expanded(child: body),
      ],
    );
  }
}

class _WorkArea extends ConsumerWidget {
  const _WorkArea({required this.jobsExpanded, this.hoistToolbar = false});
  final bool jobsExpanded;

  /// When true the active pane omits its own toolbar — [_ExplorerArea] has
  /// hoisted it to a full-width band above the sidebar.
  final bool hoistToolbar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final engine = ref.watch(engineControllerProvider);
    if (engine.phase != EnginePhase.ready) {
      return _EngineGate(engine: engine);
    }
    final inspectorOpen = ref.watch(inspectorVisibleProvider);
    final singlePane = ref.watch(singlePaneProvider);
    final active = ref.watch(activePaneProvider);
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (singlePane)
                Expanded(
                  child: BrowserPane(index: active, showToolbar: !hoistToolbar),
                )
              else ...[
                const Expanded(child: BrowserPane(index: 0)),
                VerticalDivider(width: 1, color: c.border),
                const Expanded(child: BrowserPane(index: 1)),
              ],
              if (inspectorOpen) ...[
                VerticalDivider(width: 1, color: c.border),
                const SizedBox(width: 300, child: InspectorPanel()),
              ],
            ],
          ),
        ),
        if (jobsExpanded) ...[
          Divider(height: 1, color: c.border),
          const SizedBox(height: 240, child: _JobsDock()),
        ],
      ],
    );
  }
}

/// The bottom dock: a "Transfers" tab (live stats + jobs) and a "Recent
/// activity" tab (completed-transfer history). Defaults to Transfers so the
/// Airclone default look is unchanged.
class _JobsDock extends ConsumerStatefulWidget {
  const _JobsDock();
  @override
  ConsumerState<_JobsDock> createState() => _JobsDockState();
}

class _JobsDockState extends ConsumerState<_JobsDock> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 30,
          child: Row(
            children: [
              _tabButton(c, 0, 'Transfers'),
              _tabButton(c, 1, 'Recent activity'),
            ],
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

  Widget _tabButton(AircloneColors c, int index, String label) {
    final on = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? c.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? c.primary : c.textMuted,
            fontSize: 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.jobsExpanded, required this.onToggleJobs});
  final bool jobsExpanded;
  final VoidCallback onToggleJobs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final chrome = AircloneTheme.chromeOf(context);
    // OS skins quiet the branding; skip the version watch entirely when compact.
    final version = chrome.compactBranding
        ? null
        : ref.watch(appVersionProvider).valueOrNull;
    final inspectorOpen = ref.watch(inspectorVisibleProvider);
    final singlePane = ref.watch(singlePaneProvider);
    final sidebarVisible = ref.watch(sidebarVisibleProvider);
    final advanced = ref.watch(advancedModeProvider);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: Space.x2, right: Space.x2),
      decoration: BoxDecoration(
        // Native file managers don't tint their toolbar as a raised band.
        color: chrome.compactBranding ? c.surface : c.surfaceRaised,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => ref.read(sidebarVisibleProvider.notifier).state =
                !sidebarVisible,
            icon: Icon(sidebarVisible ? Icons.menu_open : Icons.menu, size: 18),
            tooltip: sidebarVisible ? 'Hide sidebar' : 'Show sidebar',
            color: c.textMuted,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: Space.x1),
          if (!chrome.compactBranding) ...[
            Icon(Icons.cloud_sync_outlined, size: 20, color: c.primary),
            const SizedBox(width: Space.x2),
            Text(
              'Airclone',
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: Space.x2),
            Text(
              version != null ? 'v$version' : 'alpha',
              style: TextStyle(color: c.textFaint, fontSize: 11),
            ),
          ],
          const Spacer(),
          const BandwidthButton(),
          IconButton(
            onPressed: () =>
                ref.read(singlePaneProvider.notifier).state = !singlePane,
            icon: Icon(
              singlePane ? Icons.splitscreen_outlined : Icons.splitscreen,
              size: 18,
            ),
            tooltip: singlePane
                ? 'Dual-pane view (commander)'
                : 'Single-pane view',
            color: singlePane ? c.textMuted : c.primary,
          ),
          IconButton(
            onPressed: () => ref.read(inspectorVisibleProvider.notifier).state =
                !inspectorOpen,
            icon: const Icon(Icons.info_outline, size: 18),
            tooltip: inspectorOpen
                ? 'Hide details (Ctrl+I)'
                : 'Show details (Ctrl+I)',
            color: inspectorOpen ? c.primary : c.textMuted,
          ),
          IconButton(
            onPressed: onToggleJobs,
            icon: Icon(
              jobsExpanded ? Icons.expand_more : Icons.list_alt,
              size: 18,
            ),
            tooltip: jobsExpanded ? 'Hide transfers' : 'Show transfers',
            color: c.textMuted,
          ),
          if (advanced)
            IconButton(
              onPressed: () => showTasksDialog(context),
              icon: const Icon(Icons.checklist_rounded, size: 18),
              tooltip: 'Saved tasks',
              color: c.textMuted,
            ),
          // Serve/share — advanced-gated AND hidden when disabled by policy.
          if (advanced && ref.watch(serveEnabledProvider))
            IconButton(
              onPressed: () => showServeDialog(context),
              icon: const Icon(Icons.cast_connected, size: 18),
              tooltip: 'Serve / Share on LAN',
              color: c.textMuted,
            ),
          // Mount manager — advanced-gated AND hidden when disabled by policy.
          if (advanced && ref.watch(mountEnabledProvider))
            IconButton(
              onPressed: () => showMountDialog(context),
              icon: const Icon(Icons.usb, size: 18),
              tooltip: 'Mount as a drive',
              color: c.textMuted,
            ),
          IconButton(
            onPressed: () => showShortcutsDialog(context),
            icon: const Icon(Icons.keyboard_outlined, size: 18),
            tooltip: 'Keyboard shortcuts (F1)',
            color: c.textMuted,
          ),
          IconButton(
            onPressed: () => showSettingsDialog(context),
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: 'Settings',
            color: c.textMuted,
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final remotes = ref.watch(remotesProvider);
    final userLocations = ref.watch(userLocationsProvider);
    final drives = ref.watch(drivesProvider);
    final collapsed = ref.watch(collapsedSectionsProvider);
    final active = ref.watch(activePaneProvider);
    final selectedRemote = ref.watch(paneProvider(active)).remote;
    final engineReady = ref.watch(engineControllerProvider).isReady;
    // Per-skin chrome drives sidebar presentation (selection style, header
    // casing, coloured folder icons) — see SkinChrome.
    final chrome = AircloneTheme.chromeOf(context);
    final colouredIcons = chrome.colouredFolderIcons;

    Widget tile(
      Remote r,
      IconData icon, {
      VoidCallback? onDelete,
      VoidCallback? onEdit,
      VoidCallback? onDuplicate,
      String deleteLabel = 'Remove',
      Color? iconColor,
    }) => NativePaneDropRegion(
      onDrop: (data) => _copyToRemoteRoot(context, ref, data, r),
      highlightColor: c.primary,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: _RemoteTile(
        remote: r,
        selected: r == selectedRemote,
        leadingIcon: icon,
        leadingIconColor: iconColor,
        onTap: () => _openOrToggle(ref, active, r),
        onDelete: onDelete,
        onEdit: onEdit,
        onDuplicate: onDuplicate,
        deleteLabel: deleteLabel,
      ),
    );

    final children = <Widget>[
      // ── Locations (editable: + picker · drag-drop folders · remove) ──────────
      _SectionHeader(
        label: 'LOCATIONS',
        sectionKey: 'locations',
        trailing: IconButton(
          onPressed: () => _addFolderViaPicker(ref),
          icon: const Icon(Icons.add, size: 16),
          tooltip: 'Add a folder…',
          color: c.textMuted,
          visualDensity: VisualDensity.compact,
        ),
      ),
      if (!collapsed.contains('locations'))
        NativePaneDropRegion(
          // OS folders dropped here are added to the sidebar (no in-app drop).
          onOsFiles: (paths) => _addDroppedFolders(ref, paths),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (userLocations.isEmpty)
                _hint(c, 'Drag a folder here, or click + to add one.'),
              for (final loc in userLocations)
                tile(
                  loc.remote,
                  _localIcon(loc.kind),
                  iconColor: colouredIcons ? _localAccent(loc.kind) : null,
                  onDelete: () => ref
                      .read(userLocationsProvider.notifier)
                      .remove(loc.remote.fs),
                  deleteLabel: 'Remove from sidebar',
                ),
            ],
          ),
        ),

      // ── Disks (auto-detected) ────────────────────────────────────────────────
      const _SectionHeader(label: 'DISKS', sectionKey: 'disks'),
      if (!collapsed.contains('disks'))
        for (final d in drives)
          tile(
            d.remote,
            _localIcon(d.kind),
            iconColor: colouredIcons ? _localAccent(d.kind) : null,
          ),

      // ── Cloud (rclone remotes) ───────────────────────────────────────────────
      _SectionHeader(
        label: 'CLOUD',
        sectionKey: 'cloud',
        trailing: engineReady
            ? PopupMenuButton<String>(
                icon: Icon(Icons.add, size: 16, color: c.textMuted),
                tooltip: 'Add or encrypt a remote',
                onSelected: (v) {
                  if (v == 'add') {
                    showAddRemoteDialog(context);
                  } else if (v == 'encrypt') {
                    showEncryptRemoteDialog(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('Add a remote…')),
                  PopupMenuItem(
                    value: 'encrypt',
                    child: Text('Encrypt a remote…'),
                  ),
                ],
              )
            : IconButton(
                onPressed: null,
                icon: const Icon(Icons.add, size: 16),
                tooltip: 'Start the engine to add a remote',
                color: c.textMuted,
                visualDensity: VisualDensity.compact,
              ),
      ),
      if (!collapsed.contains('cloud'))
        ...remotes.when(
          data: (list) => list.isEmpty
              ? [_hint(c, 'No cloud remotes yet — click + to add one.')]
              : [
                  for (final r in list)
                    tile(
                      r,
                      Icons.cloud_outlined,
                      onEdit: () => showEditRemoteDialog(context, r),
                      onDuplicate: () => _duplicateRemote(context, ref, r),
                      onDelete: () => _confirmDeleteRemote(context, ref, r),
                      deleteLabel: 'Delete remote',
                    ),
                ],
          loading: () => [
            const Padding(
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
    ];

    return Container(
      color: c.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
        children: children,
      ),
    );
  }
}

/// A collapsible sidebar section header: a chevron + label that toggles the
/// section's visibility, with an optional trailing action (e.g. an add button).
class _SectionHeader extends ConsumerWidget {
  const _SectionHeader({
    required this.label,
    required this.sectionKey,
    this.trailing,
  });
  final String label;
  final String sectionKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final titleCase =
        AircloneTheme.chromeOf(context).sectionHeaderStyle ==
        SectionHeaderStyle.titleCase;
    final collapsed = ref.watch(
      collapsedSectionsProvider.select((s) => s.contains(sectionKey)),
    );
    // Title Case (OS skins: "Locations") vs ALL-CAPS (Airclone: "LOCATIONS").
    final shown = titleCase
        ? '${label[0]}${label.substring(1).toLowerCase()}'
        : label;
    return Padding(
      padding: const EdgeInsets.only(top: Space.x3, bottom: Space.x1),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () => ref
                  .read(collapsedSectionsProvider.notifier)
                  .toggle(sectionKey),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                child: Row(
                  children: [
                    Icon(
                      collapsed
                          ? Icons.chevron_right
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: c.textFaint,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      shown,
                      style: TextStyle(
                        color: titleCase ? c.textMuted : c.textFaint,
                        fontSize: titleCase ? 12 : 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: titleCase ? 0 : 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Opens the native folder picker and adds the chosen folder to Locations.
Future<void> _addFolderViaPicker(WidgetRef ref) async {
  final dir = await getDirectoryPath();
  if (dir != null && dir.isNotEmpty) {
    ref.read(userLocationsProvider.notifier).addFolder(dir);
  }
}

/// Adds any dropped paths that are directories to Locations.
void _addDroppedFolders(WidgetRef ref, List<String> paths) {
  final notifier = ref.read(userLocationsProvider.notifier);
  for (final p in paths) {
    if (Directory(p).existsSync()) notifier.addFolder(p);
  }
}

Widget _hint(AircloneColors c, String text) => Padding(
  padding: const EdgeInsets.all(Space.x3),
  child: Text(text, style: TextStyle(color: c.textFaint, fontSize: 12)),
);

/// A thin draggable divider that resizes the sidebar (with a resize cursor).
class _SidebarResizeHandle extends ConsumerWidget {
  const _SidebarResizeHandle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) {
          final next = (ref.read(sidebarWidthProvider) + d.delta.dx).clamp(
            170.0,
            460.0,
          );
          ref.read(sidebarWidthProvider.notifier).state = next;
        },
        child: SizedBox(
          width: 6,
          child: Center(child: Container(width: 1, color: c.border)),
        ),
      ),
    );
  }
}

/// Icon for a local sidebar location.
IconData _localIcon(LocalKind kind) => switch (kind) {
  LocalKind.home => Icons.home_outlined,
  LocalKind.desktop => Icons.desktop_windows_outlined,
  LocalKind.documents => Icons.description_outlined,
  LocalKind.downloads => Icons.download_outlined,
  LocalKind.pictures => Icons.image_outlined,
  LocalKind.videos => Icons.movie_outlined,
  LocalKind.music => Icons.library_music_outlined,
  LocalKind.drive => Icons.storage_outlined,
  LocalKind.root => Icons.computer_outlined,
  LocalKind.folder => Icons.folder_outlined,
};

/// Win11-style coloured "known folder" tints, used by the Windows Explorer skin
/// to make the sidebar read like Explorer's Quick Access.
Color _localAccent(LocalKind kind) => switch (kind) {
  LocalKind.home => const Color(0xFF4DA3E0),
  LocalKind.desktop => const Color(0xFF4DA3E0),
  LocalKind.documents => const Color(0xFF4DA3E0),
  LocalKind.downloads => const Color(0xFF5BB561),
  LocalKind.pictures => const Color(0xFF5DB6A8),
  LocalKind.videos => const Color(0xFF6E8FE0),
  LocalKind.music => const Color(0xFFE06A9E),
  LocalKind.drive => const Color(0xFFB0B4BA),
  LocalKind.root => const Color(0xFFB0B4BA),
  LocalKind.folder => const Color(0xFFE8C15A),
};

/// Open [r] in the active pane, or clear the pane if it's already showing [r].
void _openOrToggle(WidgetRef ref, int active, Remote r) {
  final notifier = ref.read(paneProvider(active).notifier);
  if (ref.read(paneProvider(active)).remote == r) {
    notifier.clear();
  } else {
    notifier.open(r);
  }
}

Future<void> _copyToRemoteRoot(
  BuildContext context,
  WidgetRef ref,
  PaneDragData data,
  Remote dst,
) async {
  // No-op: dropping a remote's own root items back onto that same remote.
  if (data.remote == dst && data.parentPath.isEmpty) return;
  // Conflict-aware, like every other drop target: the core lists the remote
  // root (knownNames: null) to detect same-name collisions and prompt.
  await transferNamesIntoFolder(
    context,
    ref,
    srcRemote: data.remote,
    srcParentPath: data.parentPath,
    names: data.files.map((f) => f.name).toList(),
    destRemote: dst,
    destPath: '',
    type: JobType.copy,
  );
}

class _RemoteTile extends StatelessWidget {
  const _RemoteTile({
    required this.remote,
    required this.selected,
    required this.onTap,
    this.onDelete,
    this.onEdit,
    this.onDuplicate,
    this.leadingIcon,
    this.leadingIconColor,
    this.deleteLabel = 'Delete remote',
  });
  final Remote remote;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;

  /// Overrides the default cloud/computer icon (used for local locations).
  final IconData? leadingIcon;

  /// Tints the icon (Explorer/Finder coloured known-folder icons).
  final Color? leadingIconColor;

  /// Label for the tile's delete/remove menu item.
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final chrome = AircloneTheme.chromeOf(context);
    // Finder fills the whole pill with the accent and flips text to white.
    final filled =
        selected && chrome.sidebarSelection == SidebarSelection.accentFillPill;
    final leftBar = chrome.sidebarSelection == SidebarSelection.leftAccentBar;
    final fg = filled ? Colors.white : c.text;
    final subFg = filled ? Colors.white.withValues(alpha: 0.85) : c.textFaint;
    final icoColor =
        leadingIconColor ??
        (filled ? Colors.white : (selected ? c.primary : c.textMuted));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: EdgeInsets.only(
          left: leftBar ? Space.x2 : Space.x3,
          top: 2,
          bottom: 2,
        ),
        margin: EdgeInsets.symmetric(
          horizontal: chrome.sidebarItemInset,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          color: selected
              ? (filled ? c.primary : c.primary.withValues(alpha: 0.12))
              : null,
          borderRadius: BorderRadius.circular(Radii.md),
          border: leftBar
              ? Border(
                  left: BorderSide(
                    color: selected ? c.primary : Colors.transparent,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              leadingIcon ??
                  (remote.isLocal
                      ? Icons.computer_outlined
                      : Icons.cloud_outlined),
              size: 18,
              color: icoColor,
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    remote.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (chrome.tileShowsSubtitle)
                    Text(
                      remote.type,
                      style: TextStyle(color: subFg, fontSize: 11),
                    ),
                ],
              ),
            ),
            if (onDelete != null || onEdit != null || onDuplicate != null)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 16, color: c.textFaint),
                tooltip: 'Actions',
                padding: EdgeInsets.zero,
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit remote…'),
                    ),
                  if (onDuplicate != null)
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Text('Duplicate remote…'),
                    ),
                  if ((onEdit != null || onDuplicate != null) &&
                      onDelete != null)
                    const PopupMenuDivider(),
                  if (onDelete != null)
                    PopupMenuItem(value: 'delete', child: Text(deleteLabel)),
                ],
                onSelected: (v) {
                  if (v == 'edit') onEdit?.call();
                  if (v == 'duplicate') onDuplicate?.call();
                  if (v == 'delete') onDelete?.call();
                },
              )
            else
              const SizedBox(width: Space.x2),
          ],
        ),
      ),
    );
  }
}

/// Confirms then removes a remote from `rclone.conf` (cloud files are untouched).
Future<void> _confirmDeleteRemote(
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
        'This removes the remote from your rclone config. Files stored in the '
        'cloud are not affected.',
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
  for (final p in [browserAProvider, browserBProvider]) {
    if (ref.read(p).remote == remote) ref.read(p.notifier).clear();
  }
  ref.invalidate(remotesProvider);
}

/// Copies a remote's stored config under a new name. config/get returns its
/// passwords ALREADY OBSCURED, so config/create is sent with `noObscure: true` —
/// re-obscuring them (obscure: true) would double-obscure and corrupt them.
Future<void> duplicateRemoteRpc(
  RcloneClient client, {
  required String source,
  required String newName,
}) async {
  final cfg = await client.rpc('config/get', {'name': source});
  final type = (cfg['type'] as String?) ?? '';
  final params = <String, dynamic>{
    for (final e in cfg.entries)
      if (e.key != 'type') e.key: e.value,
  };
  await client.rpc('config/create', {
    'name': newName,
    'type': type,
    'parameters': params,
    'opt': {'nonInteractive': true, 'all': true, 'noObscure': true},
  });
}

/// Prompts for a new name, then duplicates [source] (cloud config copy).
Future<void> _duplicateRemote(
  BuildContext context,
  WidgetRef ref,
  Remote source,
) async {
  final controller = TextEditingController(text: '${source.name}-copy');
  final existing =
      ref.read(remotesProvider).valueOrNull?.map((r) => r.name).toSet() ??
      const {};
  final newName = await showDialog<String>(
    context: context,
    builder: (dctx) {
      final c = AircloneTheme.of(dctx);
      return AlertDialog(
        backgroundColor: c.surfaceRaised,
        title: const Text('Duplicate remote'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'New remote name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = controller.text.trim();
              if (n.isNotEmpty) Navigator.pop(dctx, n);
            },
            child: const Text('Duplicate'),
          ),
        ],
      );
    },
  );
  if (newName == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (existing.contains(newName)) {
    messenger.showSnackBar(
      SnackBar(content: Text('A remote named "$newName" already exists.')),
    );
    return;
  }
  final client = ref.read(engineControllerProvider).client;
  if (client == null) return;
  try {
    await duplicateRemoteRpc(client, source: source.name, newName: newName);
    ref.invalidate(remotesProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('Duplicated to "$newName".')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Duplicate failed: $e')));
  }
}

/// Shown until the engine is ready (locating / not-installed / provisioning / error).
class _EngineGate extends ConsumerWidget {
  const _EngineGate({required this.engine});
  final EngineUi engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    if (engine.phase == EnginePhase.needsPassword) {
      return _PasswordGate(message: engine.message);
    }
    final notInstalled = engine.phase == EnginePhase.notInstalled;
    final error = engine.phase == EnginePhase.error;
    final busy =
        engine.phase == EnginePhase.locating ||
        engine.phase == EnginePhase.provisioning ||
        engine.phase == EnginePhase.starting;

    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(Space.x6),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.cloud_sync_outlined,
              size: 40,
              color: error ? c.error : c.primary,
            ),
            const SizedBox(height: Space.x4),
            Text(
              error
                  ? 'Engine error'
                  : notInstalled
                  ? 'Set up the rclone engine'
                  : 'Starting Airclone',
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.x2),
            Text(
              engine.message ??
                  (notInstalled
                      ? 'Airclone uses the rclone engine. Download it now — nothing else to install.'
                      : 'Please wait…'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const SizedBox(height: Space.x5),
            if (busy)
              const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (notInstalled || error)
              FilledButton.icon(
                onPressed: () => ref
                    .read(engineControllerProvider.notifier)
                    .installAndStart(),
                icon: const Icon(Icons.download, size: 18),
                label: Text(
                  error ? 'Retry download' : 'Download rclone engine',
                ),
              ),
            if (error) ...[
              const SizedBox(height: Space.x2),
              TextButton(
                onPressed: () =>
                    ref.read(engineControllerProvider.notifier).bootstrap(),
                child: const Text('Re-check for a local rclone'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Password prompt for an encrypted rclone config. The password is sent to the
/// controller (→ RCLONE_CONFIG_PASS) and never persisted.
class _PasswordGate extends ConsumerStatefulWidget {
  const _PasswordGate({this.message});
  final String? message;

  @override
  ConsumerState<_PasswordGate> createState() => _PasswordGateState();
}

class _PasswordGateState extends ConsumerState<_PasswordGate> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    if (_c.text.isEmpty) return;
    ref.read(engineControllerProvider.notifier).unlockAndStart(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(Space.x6),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: c.primary),
            const SizedBox(height: Space.x4),
            Text(
              'Unlock your config',
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.x2),
            Text(
              widget.message ?? 'Your rclone config is encrypted.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const SizedBox(height: Space.x5),
            TextField(
              controller: _c,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Config password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.x4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Unlock'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final engine = ref.watch(engineControllerProvider);
    final (color, label) = switch (engine.phase) {
      EnginePhase.ready => (
        c.success,
        'engine ok · rclone ${engine.version ?? ''}',
      ),
      EnginePhase.error => (c.error, 'engine error'),
      EnginePhase.notInstalled => (c.warning, 'engine not installed'),
      _ => (c.textFaint, 'engine ${engine.phase.name}…'),
    };

    // Active-pane summary: item count · selection · free/total space.
    final active = ref.watch(activePaneProvider);
    final st = ref.watch(paneProvider(active));
    final remote = st.remote;
    final sel = st.selectedEntries;
    final selBytes = sel.fold<int>(0, (s, e) => s + (e.size > 0 ? e.size : 0));
    final about = remote == null
        ? null
        : ref.watch(remoteAboutProvider(remote.fs)).valueOrNull;

    final parts = <String>[
      if (remote != null) '${st.visibleEntries.length} items',
      if (sel.isNotEmpty) '${sel.length} selected · ${humanSize(selBytes)}',
      if (about?.free != null && about?.total != null)
        '${humanSize(about!.free!)} free of ${humanSize(about.total!)}',
    ];

    return Container(
      height: 24,
      color: c.surfaceRaised,
      padding: const EdgeInsets.symmetric(horizontal: Space.x4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.x2),
          Text(label, style: TextStyle(color: c.textMuted, fontSize: 11)),
          const Spacer(),
          if (parts.isNotEmpty)
            Text(
              parts.join('   ·   '),
              style: TextStyle(color: c.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
