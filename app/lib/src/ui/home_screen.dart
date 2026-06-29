import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/models/remote.dart';
import '../state/advanced_mode.dart';
import '../state/app_info.dart';
import '../state/browser_controller.dart';
import '../state/engine_controller.dart';
import '../state/local_locations.dart';
import '../state/remote_about.dart';
import '../state/remotes_provider.dart';
import '../state/stats_controller.dart';
import '../state/transfer_service.dart';
import 'add_remote_dialog.dart';
import 'bandwidth_control.dart';
import 'browser_pane.dart';
import 'format.dart';
import 'inspector_panel.dart';
import 'jobs_panel.dart';
import 'pane_drag.dart';
import 'quick_look.dart';
import 'settings_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    BrowserController activePane() =>
        ref.read(paneProvider(ref.read(activePaneProvider)).notifier);
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
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (ref.watch(sidebarVisibleProvider)) ...[
                      SizedBox(
                        width: ref.watch(sidebarWidthProvider),
                        child: const _Sidebar(),
                      ),
                      const _SidebarResizeHandle(),
                    ],
                    Expanded(child: _WorkArea(jobsExpanded: _jobsExpanded)),
                  ],
                ),
              ),
              const _StatusBar(),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkArea extends ConsumerWidget {
  const _WorkArea({required this.jobsExpanded});
  final bool jobsExpanded;

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
                Expanded(child: BrowserPane(index: active))
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
          SizedBox(
            height: 220,
            child: Column(
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
            ),
          ),
        ],
      ],
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
    final version = ref.watch(appVersionProvider).valueOrNull;
    final inspectorOpen = ref.watch(inspectorVisibleProvider);
    final singlePane = ref.watch(singlePaneProvider);
    final sidebarVisible = ref.watch(sidebarVisibleProvider);
    final advanced = ref.watch(advancedModeProvider);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: Space.x2, right: Space.x2),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
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

    Widget tile(
      Remote r,
      IconData icon, {
      VoidCallback? onDelete,
      String deleteLabel = 'Remove',
    }) => DragTarget<PaneDragData>(
      onAcceptWithDetails: (d) => _copyToRemoteRoot(ref, d.data, r),
      builder: (_, cand, _) => _RemoteTile(
        remote: r,
        selected: r == selectedRemote,
        dropHover: cand.isNotEmpty,
        leadingIcon: icon,
        onTap: () => _openOrToggle(ref, active, r),
        onDelete: onDelete,
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
        DropTarget(
          onDragDone: (d) =>
              _addDroppedFolders(ref, d.files.map((f) => f.path).toList()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (userLocations.isEmpty)
                _hint(c, 'Drag a folder here, or click + to add one.'),
              for (final loc in userLocations)
                tile(
                  loc.remote,
                  _localIcon(loc.kind),
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
        for (final d in drives) tile(d.remote, _localIcon(d.kind)),

      // ── Cloud (rclone remotes) ───────────────────────────────────────────────
      _SectionHeader(
        label: 'CLOUD',
        sectionKey: 'cloud',
        trailing: IconButton(
          onPressed: engineReady ? () => showAddRemoteDialog(context) : null,
          icon: const Icon(Icons.add, size: 16),
          tooltip: engineReady
              ? 'Add remote'
              : 'Start the engine to add a remote',
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
    final collapsed = ref.watch(
      collapsedSectionsProvider.select((s) => s.contains(sectionKey)),
    );
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
                      label,
                      style: TextStyle(
                        color: c.textFaint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
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
  WidgetRef ref,
  PaneDragData data,
  Remote dst,
) async {
  final svc = ref.read(transferServiceProvider);
  for (final f in data.files) {
    await svc.transfer(
      srcRemote: data.remote,
      srcPath: joinPath(data.parentPath, f.name),
      dstRemote: dst,
      dstPath: f.name,
      type: JobType.copy,
    );
  }
}

class _RemoteTile extends StatelessWidget {
  const _RemoteTile({
    required this.remote,
    required this.selected,
    required this.onTap,
    this.onDelete,
    this.dropHover = false,
    this.leadingIcon,
    this.deleteLabel = 'Delete remote',
  });
  final Remote remote;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool dropHover;

  /// Overrides the default cloud/computer icon (used for local locations).
  final IconData? leadingIcon;

  /// Label for the tile's delete/remove menu item.
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.only(left: Space.x2, top: 2, bottom: 2),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: dropHover
              ? c.primary.withValues(alpha: 0.18)
              : selected
              ? c.primary.withValues(alpha: 0.12)
              : null,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border(
            left: BorderSide(
              color: selected ? c.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              leadingIcon ??
                  (remote.isLocal
                      ? Icons.computer_outlined
                      : Icons.cloud_outlined),
              size: 18,
              color: selected ? c.primary : c.textMuted,
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
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    remote.type,
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 16, color: c.textFaint),
                tooltip: 'Actions',
                padding: EdgeInsets.zero,
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'delete', child: Text(deleteLabel)),
                ],
                onSelected: (v) {
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
