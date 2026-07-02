import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/android_native.dart';
import '../state/browser_controller.dart';
import '../state/clipboard_controller.dart';
import '../state/engine_controller.dart';
import '../state/local_locations.dart';
import '../state/remotes_provider.dart';
import '../state/stats_controller.dart';
import 'add_remote_dialog.dart';
import 'browser_pane.dart';
import 'connection_test_dialog.dart';
import 'encrypt_remote_dialog.dart';
import 'engine_gate.dart';
import 'jobs_panel.dart';
import 'paste_action.dart';
import 'recent_activity_panel.dart';
import 'search_dialog.dart';
import 'settings_screen.dart';
import 'stats_panel.dart';
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
    final browsing = ref.watch(paneProvider(0).select((s) => s.remote != null));
    // When the engine gate is on screen, pane state is irrelevant — back must
    // not get swallowed navigating a browser the user can't see.
    final gated = ref.watch(
      engineControllerProvider.select((e) => e.phase != EnginePhase.ready),
    );
    // System back: leave a folder, then leave the remote, then leave a non-Files
    // tab — only exit the app from the Files tab's locations list.
    final canPop = _tab == 0 && (!browsing || gated);
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != 0) {
          setState(() => _tab = 0);
          return;
        }
        final pane = ref.read(paneProvider(0));
        final ctrl = ref.read(paneProvider(0).notifier);
        if (pane.path.isNotEmpty) {
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
    final browsing = ref.watch(paneProvider(0).select((s) => s.remote != null));
    return browsing ? const _MobileBrowser() : const _MobileLocations();
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
            tooltip: 'Add or encrypt a remote',
            onSelected: (v) => v == 'add'
                ? showAddRemoteDialog(context)
                : showEncryptRemoteDialog(context),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add', child: Text('Add a remote…')),
              PopupMenuItem(value: 'encrypt', child: Text('Encrypt a remote…')),
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

  Widget _header(AircloneColors c, String label, {Widget? trailing}) =>
      Padding(
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

/// A slim phone header over the shared [BrowserPane] (its desktop toolbar is
/// hidden; navigation and folder actions live here and in the long-press
/// menus).
class _MobileBrowser extends ConsumerWidget {
  const _MobileBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(paneProvider(0));
    final ctrl = ref.read(paneProvider(0).notifier);
    final remote = state.remote;
    if (remote == null) return const SizedBox.shrink();

    final folder = state.path.isEmpty
        ? remote.name
        : state.path.split('/').last;
    final subtitle = state.path.isEmpty
        ? remote.type
        : '${remote.name}/${state.path}';
    final clipEmpty = ref.watch(
      clipboardControllerProvider.select((s) => s.isEmpty),
    );

    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: Space.x1),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () =>
                    state.path.isEmpty ? ctrl.clear() : ctrl.up(),
                icon: const Icon(Icons.arrow_back, size: 22),
                color: c.text,
                tooltip: state.path.isEmpty ? 'All locations' : 'Up',
              ),
              Expanded(
                child: Column(
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
              IconButton(
                onPressed: () => _search(context, ref),
                icon: const Icon(Icons.search, size: 20),
                color: c.textMuted,
                tooltip: 'Search this folder',
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: c.textMuted),
                onSelected: (v) async {
                  switch (v) {
                    case 'refresh':
                      await ctrl.refresh();
                    case 'paste':
                      if (context.mounted) {
                        await pasteClipboardInto(
                          context,
                          ref,
                          dest: ref.read(paneProvider(0)),
                          paneIndex: 0,
                        );
                      }
                    case 'view-list':
                      ctrl.setViewMode(ViewMode.list);
                    case 'view-grid':
                      ctrl.setViewMode(ViewMode.grid);
                    case 'view-media':
                      ctrl.setViewMode(ViewMode.media);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Text('Refresh'),
                  ),
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
              ),
            ],
          ),
        ),
        const Expanded(child: BrowserPane(index: 0, showToolbar: false)),
      ],
    );
  }

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
          child: state.viewMode == mode ? const Icon(Icons.check, size: 16) : null,
        ),
        Text(label),
      ],
    ),
  );

  /// Recursive search rooted at the current folder; opening a match navigates
  /// to it (same behavior as the desktop Ctrl+Shift+F).
  void _search(BuildContext context, WidgetRef ref) {
    final state = ref.read(paneProvider(0));
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
        final pane = ref.read(paneProvider(0).notifier);
        final abs = basePath.isEmpty ? m.path : '$basePath/${m.path}';
        if (m.isDir) {
          await pane.navigateTo(abs);
          return;
        }
        final slash = abs.lastIndexOf('/');
        final parent = slash < 0 ? '' : abs.substring(0, slash);
        if (parent != ref.read(paneProvider(0)).path) {
          await pane.navigateTo(parent);
        }
        pane.selectOnly(m.name);
      },
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
