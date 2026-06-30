import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/clipboard_controller.dart';
import '../state/download_settings.dart';
import '../state/engine_controller.dart';
import '../state/file_ops.dart';
import '../state/os_integration.dart';
import '../state/remote_features.dart';
import '../state/thumbnail_prefs.dart';
import '../state/thumbnail_service.dart';
import '../state/transfer_service.dart';
import 'column_header.dart';
import 'context_menu.dart';
import 'destination_picker.dart';
import 'file_grid.dart';
import 'file_icon.dart';
import 'file_op_dialogs.dart';
import 'format.dart';
import 'inspector_panel.dart';
import 'media_gallery.dart';
import 'native_drag.dart';
import 'pane_drag.dart';
import 'path_bar.dart';
import 'quick_look.dart';
import 'theme/tokens.dart';
import 'transfer_options_dialog.dart';

/// One of the two dual-pane browsers. [index] 0 = A (left), 1 = B (right).
///
/// When [showToolbar] is false the address/command bar is omitted — the OS
/// skins hoist it to a full-width band above the sidebar (see [PaneToolbar]),
/// so the pane renders content only.
class BrowserPane extends ConsumerWidget {
  const BrowserPane({super.key, required this.index, this.showToolbar = true});
  final int index;
  final bool showToolbar;

  int get _other => index == 0 ? 1 : 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(paneProvider(index));
    final active = ref.watch(activePaneProvider) == index;

    return GestureDetector(
      onTap: () => ref.read(activePaneProvider.notifier).state = index,
      child: Container(
        color: c.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.tabs.length > 1) _TabStrip(index: index),
            if (showToolbar) ...[
              _PaneToolbar(index: index, active: active, state: state),
              Divider(height: 1, color: c.border),
            ],
            Expanded(
              child: state.remote == null
                  ? _empty(c)
                  : NativePaneDropRegion(
                      // In-app drag → copy into this pane.
                      onDrop: (data) =>
                          _dropOnto(ref, data, state.remote!, state.path),
                      // OS files dragged in from Explorer/Finder → upload.
                      onOsFiles: (paths) =>
                          _uploadLocal(ref, paths, state.remote!, state.path),
                      // Auto-scroll the list while dragging near its edges.
                      scrollController: ref.watch(paneScrollProvider(index)),
                      highlightColor: c.primary,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onSecondaryTapUp: (d) => _showEmptyMenu(
                          context,
                          ref,
                          state,
                          d.globalPosition,
                        ),
                        child: _body(context, ref, state, highlight: false),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(AircloneColors c) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_open_outlined, size: 36, color: c.textFaint),
        const SizedBox(height: Space.x2),
        Text(
          'Pick a remote on the left',
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    BrowserState state, {
    required bool highlight,
  }) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(paneProvider(index).notifier);
    Widget content;
    if (state.loading) {
      content = const Center(
        child: SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (state.error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.x6),
          child: Text(
            state.error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.error, fontSize: 13),
          ),
        ),
      );
    } else if (state.visibleEntries.isEmpty) {
      content = Center(
        child: Text(
          state.filter.isEmpty ? 'Empty folder' : 'No matches',
          style: TextStyle(color: c.textFaint, fontSize: 13),
        ),
      );
    } else {
      final visible = state.visibleEntries;
      final thumbsOn = thumbnailsOn(
        state.remote!,
        ref.watch(thumbnailsDisabledProvider),
      );
      final client = ref.read(engineControllerProvider).client;

      // Build a thumbnail request for an image OR video when thumbnails are on
      // for this remote — shared by the grid and media views.
      ThumbRequest? thumbReqFor(RcloneFile f) {
        if (!thumbsOn || client == null || f.isDir || !isThumbnailable(f)) {
          return null;
        }
        final oref = client.objectRef(
          state.remote!.fs,
          joinPath(state.path, f.name),
        );
        return ThumbRequest(
          url: oref.url,
          headers: oref.headers,
          cacheKey: thumbCacheKey(
            state.remote!.fs,
            f.path,
            f.modTime,
            f.size,
            256,
          ),
          cacheSecret: state.remote!.name,
          isVideo: isVideoThumbnailable(f),
        );
      }

      // Open the immersive Quick Look on [f], navigable across the listing.
      void quickLook(RcloneFile f) => showQuickLook(
        context,
        state.remote!,
        state.path,
        visible,
        visible.indexOf(f),
      );

      switch (state.viewMode) {
        case ViewMode.grid:
          content = FileGrid(
            entries: visible,
            state: state,
            remote: state.remote!,
            gridSize: state.gridSize,
            onOpen: (f) => ctrl.enterDir(f),
            onToggle: (f) => ctrl.toggleSelect(f.name),
            onPreview: quickLook,
            onContextMenu: (f, pos) =>
                _showFileMenu(context, ref, state, f, pos),
            onDropInto: (f, data) => _dropOnto(
              ref,
              data,
              state.remote!,
              joinPath(state.path, f.name),
            ),
            thumbRequestFor: thumbReqFor,
            folderPreviews: thumbsOn,
          );
        case ViewMode.media:
          content = MediaGallery(
            entries: visible,
            state: state,
            remote: state.remote!,
            gridSize: state.gridSize,
            onOpen: (f) => ctrl.enterDir(f),
            onToggle: (f) => ctrl.toggleSelect(f.name),
            onPreview: quickLook,
            onContextMenu: (f, pos) =>
                _showFileMenu(context, ref, state, f, pos),
            onDropInto: (f, data) => _dropOnto(
              ref,
              data,
              state.remote!,
              joinPath(state.path, f.name),
            ),
            thumbRequestFor: thumbReqFor,
          );
        case ViewMode.list:
          content = ListView.builder(
            controller: ref.watch(paneScrollProvider(index)),
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final f = visible[i];
              return _FileRow(
                file: f,
                state: state,
                paneRemote: state.remote!,
                onOpen: () => ctrl.enterDir(f),
                onToggle: () => ctrl.toggleSelect(f.name),
                onPreview: () => quickLook(f),
                onContextMenu: (pos) =>
                    _showFileMenu(context, ref, state, f, pos),
                onDropInto: (data) => _dropOnto(
                  ref,
                  data,
                  state.remote!,
                  joinPath(state.path, f.name),
                ),
              );
            },
          );
      }
    }
    return Container(
      decoration: highlight
          ? BoxDecoration(
              border: Border.all(color: c.primary, width: 2),
              color: c.primary.withValues(alpha: 0.04),
            )
          : null,
      child: Column(
        children: [
          if (!state.loading &&
              state.error == null &&
              state.viewMode == ViewMode.list)
            ColumnHeader(
              sortKey: state.sortKey,
              ascending: state.ascending,
              onSort: ctrl.setSort,
            ),
          Expanded(child: content),
        ],
      ),
    );
  }

  // ── context-menu dispatch ────────────────────────────────────────────────────

  List<RcloneFile> _targetFiles(BrowserState state, RcloneFile file) =>
      state.isSelected(file.name) && state.selected.isNotEmpty
      ? state.selectedEntries
      : [file];

  Future<void> _showFileMenu(
    BuildContext context,
    WidgetRef ref,
    BrowserState state,
    RcloneFile file,
    Offset pos,
  ) async {
    if (state.remote == null) return;
    final clip = ref.read(clipboardControllerProvider);
    final hasOther = ref.read(paneProvider(_other)).remote != null;
    // Read the cached backend capability synchronously — never block the menu on
    // an fsinfo RC call. Reading the provider also warms it for next time, so the
    // "Get public link" item appears once the capability is known.
    final feats = ref
        .read(remoteFeaturesProvider(state.remote!.fs))
        .valueOrNull;
    final action = await showFileContextMenu(
      context,
      pos,
      isDir: file.isDir,
      canPaste: clip.isNotEmpty,
      hasOtherPane: hasOther,
      canPublicLink: feats?['PublicLink'] == true,
      isLocal: state.remote!.isLocal,
    );
    if (action == null || state.remote == null) return;
    final files = _targetFiles(state, file);
    final clipCtrl = ref.read(clipboardControllerProvider.notifier);
    switch (action) {
      case FileMenuAction.open:
        if (file.isDir) ref.read(paneProvider(index).notifier).enterDir(file);
      case FileMenuAction.preview:
        if (!file.isDir && context.mounted) {
          await showQuickLook(
            context,
            state.remote!,
            state.path,
            state.visibleEntries,
            state.visibleEntries.indexOf(file),
          );
        }
      case FileMenuAction.openWith:
        await _openLocal(ref, state, file);
      case FileMenuAction.revealInFolder:
        await _revealLocal(ref, state, file);
      case FileMenuAction.copyPath:
        await _copyPath(ref, state, file);
      case FileMenuAction.download:
        await _download(ref, state, files);
      case FileMenuAction.copy:
        clipCtrl.copy(state.remote!, state.path, files);
      case FileMenuAction.cut:
        clipCtrl.cut(state.remote!, state.path, files);
      case FileMenuAction.paste:
        await _paste(
          ref,
          state.remote!,
          file.isDir ? joinPath(state.path, file.name) : state.path,
        );
      case FileMenuAction.copyTo:
        if (context.mounted) await _copyToPicker(context, ref, state, file);
      case FileMenuAction.moveTo:
        if (context.mounted) await _moveToPicker(context, ref, state, file);
      case FileMenuAction.openInOtherPane:
        await _openInOtherPane(ref, state, file);
      case FileMenuAction.rename:
        if (context.mounted) await _rename(context, ref, state, file);
      case FileMenuAction.delete:
        if (context.mounted) await _delete(context, ref, state, file);
      case FileMenuAction.publicLink:
        if (context.mounted) await _publicLink(context, ref, state, file);
    }
  }

  Future<void> _showEmptyMenu(
    BuildContext context,
    WidgetRef ref,
    BrowserState state,
    Offset pos,
  ) async {
    if (state.remote == null) return;
    final ctrl = ref.read(paneProvider(index).notifier);
    final clip = ref.read(clipboardControllerProvider);
    final action = await showEmptyContextMenu(
      context,
      pos,
      canPaste: clip.isNotEmpty,
    );
    if (action == null) return;
    switch (action) {
      case EmptyMenuAction.paste:
        await _paste(ref, state.remote!, state.path);
      case EmptyMenuAction.newFolder:
        if (context.mounted) await _newFolder(context, ref, state);
      case EmptyMenuAction.refresh:
        await ctrl.refresh();
      case EmptyMenuAction.selectAll:
        ctrl.selectAll();
    }
  }

  // ── handlers ─────────────────────────────────────────────────────────────────

  Future<void> _newFolder(
    BuildContext context,
    WidgetRef ref,
    BrowserState state,
  ) async {
    final name = await showNewFolderDialog(context);
    if (name == null || state.remote == null) return;
    await ref.read(fileOpsProvider).newFolder(state.remote!, state.path, name);
    await ref.read(paneProvider(index).notifier).refresh();
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    final name = await showRenameDialog(context, f.name);
    if (name == null || name == f.name || state.remote == null) return;
    await ref.read(fileOpsProvider).rename(state.remote!, f.path, name);
    await ref.read(paneProvider(index).notifier).refresh();
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    final ok = await showDeleteConfirm(context, f.name, isDir: f.isDir);
    if (!ok || state.remote == null) return;
    await ref.read(fileOpsProvider).deleteEntry(state.remote!, f, state.path);
    await ref.read(paneProvider(index).notifier).refresh();
  }

  Future<void> _copyToPicker(
    BuildContext context,
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    final dst = await showDestinationPicker(context, title: 'Copy to…');
    if (dst == null || state.remote == null) return;
    await ref
        .read(transferServiceProvider)
        .transfer(
          srcRemote: state.remote!,
          srcPath: joinPath(state.path, f.name),
          dstRemote: dst.remote,
          dstPath: joinPath(dst.path, f.name),
          type: JobType.copy,
        );
  }

  Future<void> _moveToPicker(
    BuildContext context,
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    final dst = await showDestinationPicker(context, title: 'Move to…');
    if (dst == null || state.remote == null) return;
    await ref
        .read(transferServiceProvider)
        .transfer(
          srcRemote: state.remote!,
          srcPath: joinPath(state.path, f.name),
          dstRemote: dst.remote,
          dstPath: joinPath(dst.path, f.name),
          type: JobType.move,
        );
    await ref.read(paneProvider(index).notifier).refresh();
  }

  Future<void> _download(
    WidgetRef ref,
    BrowserState state,
    List<RcloneFile> files,
  ) async {
    if (state.remote == null || files.isEmpty) return;
    final dir = await resolveDownloadDir(ref); // prompts / uses saved default
    if (dir == null) return; // cancelled
    final local = Remote(
      name: 'Download',
      type: 'local',
      fs: '$dir/',
      isLocal: true,
    );
    final svc = ref.read(transferServiceProvider);
    for (final f in files) {
      await svc.transfer(
        srcRemote: state.remote!,
        srcPath: joinPath(state.path, f.name),
        dstRemote: local,
        dstPath: f.name,
        type: JobType.copy,
      );
    }
  }

  Future<void> _paste(WidgetRef ref, Remote dstRemote, String dstPath) async {
    final clip = ref.read(clipboardControllerProvider);
    if (clip.isEmpty || clip.remote == null) return;
    final svc = ref.read(transferServiceProvider);
    for (final f in clip.files) {
      await svc.transfer(
        srcRemote: clip.remote!,
        srcPath: joinPath(clip.parentPath, f.name),
        dstRemote: dstRemote,
        dstPath: joinPath(dstPath, f.name),
        type: clip.isCut ? JobType.move : JobType.copy,
      );
    }
    if (clip.isCut) ref.read(clipboardControllerProvider.notifier).clear();
    await ref.read(paneProvider(index).notifier).refresh();
  }

  Future<void> _openInOtherPane(
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    final otherCtrl = ref.read(paneProvider(_other).notifier);
    await otherCtrl.open(state.remote!);
    await otherCtrl.navigateTo(
      f.isDir ? joinPath(state.path, f.name) : state.path,
    );
    ref.read(activePaneProvider.notifier).state = _other;
  }

  Future<void> _publicLink(
    BuildContext context,
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      final res = await client.rpc('operations/publiclink', {
        'fs': state.remote!.fs,
        'remote': joinPath(state.path, f.name),
      });
      final url = (res['url'] ?? '').toString();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Public link'),
          content: SelectableText(url.isEmpty ? 'No link returned.' : url),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Public link failed: $e')));
    }
  }

  /// The real on-disk path for [f] on a local-disk remote (else null).
  String? _localOsPath(BrowserState state, RcloneFile f) {
    final remote = state.remote;
    if (remote == null || !remote.isLocal) return null;
    return '${remote.fs}${joinPath(state.path, f.name)}';
  }

  Future<void> _openLocal(
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    final p = _localOsPath(state, f);
    if (p == null) return;
    await ref.read(osIntegrationProvider).openWithDefaultApp(p);
  }

  Future<void> _revealLocal(
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    final p = _localOsPath(state, f);
    if (p == null) return;
    await ref.read(osIntegrationProvider).revealInFileManager(p);
  }

  Future<void> _copyPath(
    WidgetRef ref,
    BrowserState state,
    RcloneFile f,
  ) async {
    // Local → OS path; cloud → the rclone `remote:path` form.
    final p =
        _localOsPath(state, f) ??
        '${state.remote!.name}:${joinPath(state.path, f.name)}';
    await ref.read(osIntegrationProvider).copyToClipboard(p);
  }

  Future<void> _dropOnto(
    WidgetRef ref,
    PaneDragData data,
    Remote dstRemote,
    String dstPath,
  ) async {
    final sameRemote = data.remote == dstRemote;
    // No-op: dropping items back into the folder they already live in
    // (e.g. releasing a drag over the current pane) — avoids a copy-to-self.
    if (sameRemote && data.parentPath == dstPath) return;
    final svc = ref.read(transferServiceProvider);
    for (final f in data.files) {
      final srcPath = joinPath(data.parentPath, f.name);
      // No-op: dropping a folder onto itself or into its own subtree.
      if (sameRemote &&
          (dstPath == srcPath || dstPath.startsWith('$srcPath/'))) {
        continue;
      }
      await svc.transfer(
        srcRemote: data.remote,
        srcPath: srcPath,
        dstRemote: dstRemote,
        dstPath: joinPath(dstPath, f.name),
        type: JobType.copy,
      );
    }
  }

  Future<void> _uploadLocal(
    WidgetRef ref,
    List<String> paths,
    Remote dst,
    String dstPath,
  ) async {
    final svc = ref.read(transferServiceProvider);
    for (final p in paths) {
      final norm = p.replaceAll('\\', '/');
      final slash = norm.lastIndexOf('/');
      final dir = slash >= 0 ? norm.substring(0, slash) : '.';
      final name = slash >= 0 ? norm.substring(slash + 1) : norm;
      final local = Remote(
        name: 'local',
        type: 'local',
        fs: '$dir/',
        isLocal: true,
      );
      await svc.transfer(
        srcRemote: local,
        srcPath: name,
        dstRemote: dst,
        dstPath: joinPath(dstPath, name),
        type: JobType.copy,
      );
    }
  }
}

/// Toolbar above a pane: nav buttons + editable path bar + selection actions.
/// Icon-size presets for the View menu (label → grid `maxCrossAxisExtent`).
const List<(String, double)> _viewSizePresets = [
  ('Extra large icons', 168.0),
  ('Large icons', 128.0),
  ('Medium icons', 96.0),
  ('Small icons', 72.0),
];

double _nearestPreset(double size) {
  var best = _viewSizePresets.first.$2;
  for (final (_, s) in _viewSizePresets) {
    if ((s - size).abs() < (best - size).abs()) best = s;
  }
  return best;
}

/// A Finder/Adwaita-style segmented view switcher — three icon cells
/// (List · Icons · Gallery) with the active one highlighted. Pure presentation:
/// the caller passes its own pane's [mode] + [onChanged] so it stays
/// dual-pane-safe (no Riverpod reads inside). Grid icon-size stays in the
/// "View" menu — tapping Icons just switches mode, preserving the saved size.
class _ViewSegmented extends StatelessWidget {
  const _ViewSegmented({
    required this.mode,
    required this.onChanged,
    required this.c,
  });
  final ViewMode mode;
  final ValueChanged<ViewMode> onChanged;
  final AircloneColors c;

  static const _segments = <(ViewMode, IconData, String)>[
    (ViewMode.list, Icons.format_list_bulleted, 'List'),
    (ViewMode.grid, Icons.grid_view_rounded, 'Icons'),
    (ViewMode.media, Icons.photo_library_outlined, 'Gallery'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: Space.x1),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _segments.length; i++) ...[
            if (i > 0) Container(width: 1, height: 28, color: c.border),
            Tooltip(
              message: _segments[i].$3,
              child: InkWell(
                onTap: () => onChanged(_segments[i].$1),
                child: Container(
                  color: mode == _segments[i].$1
                      ? c.primary.withValues(alpha: 0.14)
                      : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.x2,
                    vertical: 4,
                  ),
                  child: Icon(
                    _segments[i].$2,
                    size: 15,
                    color: mode == _segments[i].$1 ? c.primary : c.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The per-pane tab strip (shown only when a pane has more than one tab).
/// Each chip switches tabs; its ✕ closes it; the trailing + opens a new tab.
class _TabStrip extends ConsumerWidget {
  const _TabStrip({required this.index});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(paneProvider(index));
    final ctrl = ref.read(paneProvider(index).notifier);
    final tabs = state.tabs;

    return Container(
      height: 30,
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: Space.x1),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (_, i) {
                final on = i == state.activeTab;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 1,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    onTap: () => ctrl.switchTab(i),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 168),
                      padding: const EdgeInsets.only(left: Space.x2, right: 2),
                      decoration: BoxDecoration(
                        color: on ? c.surfaceRaised : c.surfaceSunken,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(
                          color: on ? c.border : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              tabs[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: on ? c.text : c.textMuted,
                                fontSize: 12,
                                fontWeight: on
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          InkWell(
                            borderRadius: BorderRadius.circular(Radii.full),
                            onTap: () => ctrl.closeTab(i),
                            child: Icon(
                              Icons.close,
                              size: 13,
                              color: c.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            onPressed: ctrl.newTab,
            icon: const Icon(Icons.add, size: 15),
            tooltip: 'New tab (Ctrl+T)',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// The active pane's toolbar hoisted to a full-width band, for the OS skins
/// that put their toolbar across the top above the sidebar (Explorer/Finder)
/// rather than beside it. Reads the same pane state [BrowserPane] does, so the
/// hoisted bar and the (toolbar-less) pane below it stay in lock-step.
class PaneToolbar extends ConsumerWidget {
  const PaneToolbar({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(paneProvider(index));
    final active = ref.watch(activePaneProvider) == index;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PaneToolbar(index: index, active: active, state: state, hoisted: true),
        Divider(height: 1, color: c.border),
      ],
    );
  }
}

/// The per-pane header — two Explorer-style rows: an **address row** (nav +
/// breadcrumb path + filter) and a **command bar** (New · Cut/Copy/Paste ·
/// Rename · Delete · Sort ▾ · View ▾).
class _PaneToolbar extends ConsumerWidget {
  const _PaneToolbar({
    required this.index,
    required this.active,
    required this.state,
    this.hoisted = false,
  });
  final int index;
  final bool active;
  final BrowserState state;

  /// True only for the full-width band hoisted above the sidebar (the public
  /// [PaneToolbar] wrapper). The Finder single-row layout is gated on this so a
  /// narrow per-pane toolbar (dual-pane) never collapses to one row.
  final bool hoisted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final chrome = AircloneTheme.chromeOf(context);
    final unified = chrome.unifiedToolbar && hoisted;
    return Container(
      // Finder's unified bar reads as one flat surface, not a raised band.
      color: unified ? c.surface : (active ? c.surfaceRaised : c.surface),
      child: unified
          ? _unifiedRow(context, ref, c)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _addressRow(context, ref, c),
                Divider(height: 1, color: c.border),
                _commandRow(context, ref, c),
              ],
            ),
    );
  }

  // ── Row 1: nav + breadcrumb path + filter ────────────────────────────────
  Widget _addressRow(BuildContext context, WidgetRef ref, AircloneColors c) {
    final ctrl = ref.read(paneProvider(index).notifier);
    final chrome = AircloneTheme.chromeOf(context);
    final segs = state.segments;
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
        child: Row(
          children: [
            if (chrome.showActivePaneDot)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: Space.x2),
                decoration: BoxDecoration(
                  color: active ? c.primary : c.border,
                  shape: BoxShape.circle,
                ),
              ),
            IconButton(
              onPressed: ctrl.canBack ? ctrl.back : null,
              icon: const Icon(Icons.arrow_back, size: 15),
              tooltip: 'Back (Alt+←)',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: ctrl.canForward ? ctrl.forward : null,
              icon: const Icon(Icons.arrow_forward, size: 15),
              tooltip: 'Forward (Alt+→)',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: segs.isEmpty ? null : ctrl.up,
              icon: const Icon(Icons.arrow_upward, size: 15),
              tooltip: 'Up (Alt+↑)',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: state.remote == null ? null : ctrl.refresh,
              icon: const Icon(Icons.refresh, size: 15),
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: ctrl.newTab,
              icon: const Icon(Icons.add, size: 15),
              tooltip: 'New tab (Ctrl+T)',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: Space.x1),
            Expanded(
              child: PathBar(
                remote: state.remote,
                path: state.path,
                onSegment: ctrl.goToSegment,
                onNavigate: ctrl.navigateTo,
              ),
            ),
            if (state.remote != null)
              _FilterBox(
                index: index,
                width: chrome.searchAlwaysVisible ? 220 : 150,
              ),
            if (state.remote != null)
              IconButton(
                tooltip: 'Close pane (deselect remote)',
                onPressed: ctrl.clear,
                icon: const Icon(Icons.cancel_outlined, size: 15),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  // ── Row 2: command bar (file verbs + Sort/View menus) ────────────────────
  Widget _commandRow(BuildContext context, WidgetRef ref, AircloneColors c) {
    final ctrl = ref.read(paneProvider(index).notifier);
    final hasRemote = state.remote != null;
    final hasSel = state.selected.isNotEmpty;
    final oneSel = state.selected.length == 1;
    final clipFull = ref.watch(clipboardControllerProvider).isNotEmpty;
    final other = ref.watch(paneProvider(index == 0 ? 1 : 0));
    final chrome = AircloneTheme.chromeOf(context);

    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x1),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (chrome.newButtonLabel != null)
                      _cmdLabeled(
                        c,
                        Icons.add,
                        chrome.newButtonLabel!,
                        enabled: hasRemote,
                        onTap: () => _newFolder(context, ref),
                      )
                    else
                      _cmd(
                        c,
                        Icons.create_new_folder_outlined,
                        'New folder',
                        enabled: hasRemote,
                        onTap: () => _newFolder(context, ref),
                      ),
                    _sep(c),
                    _cmd(
                      c,
                      Icons.content_cut,
                      'Cut',
                      enabled: hasSel,
                      onTap: () => _clip(ref, cut: true),
                    ),
                    _cmd(
                      c,
                      Icons.copy_outlined,
                      'Copy',
                      enabled: hasSel,
                      onTap: () => _clip(ref, cut: false),
                    ),
                    _cmd(
                      c,
                      Icons.content_paste,
                      'Paste',
                      enabled: clipFull && hasRemote,
                      onTap: () => _paste(ref),
                    ),
                    _sep(c),
                    _cmd(
                      c,
                      Icons.drive_file_rename_outline,
                      'Rename',
                      enabled: oneSel,
                      onTap: () => _rename(context, ref),
                    ),
                    _cmd(
                      c,
                      Icons.delete_outline,
                      'Delete',
                      enabled: hasSel,
                      danger: true,
                      onTap: () => _delete(context, ref),
                    ),
                    _sep(c),
                    _sortMenu(context, ref, c),
                    // OS skins get the segmented List·Icons·Gallery switcher; the
                    // "View" menu stays alongside for icon-size + Thumbnails.
                    if (chrome.segmentedViewSwitcher) ...[
                      _ViewSegmented(
                        mode: state.viewMode,
                        onChanged: ctrl.setViewMode,
                        c: c,
                      ),
                      _viewMenu(context, ref, c),
                    ] else
                      _viewMenu(context, ref, c),
                  ],
                ),
              ),
            ),
            if (hasSel) ...[
              Text(
                '${state.selected.length} selected',
                style: TextStyle(
                  color: c.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _cmd(
                c,
                Icons.copy_all,
                'Copy to other pane',
                enabled: other.remote != null,
                onTap: () => _transferToOther(ref, JobType.copy),
              ),
              _cmd(
                c,
                Icons.drive_file_move_outline,
                'Move to other pane',
                enabled: other.remote != null,
                onTap: () => _transferToOther(ref, JobType.move),
              ),
              _cmd(
                c,
                Icons.tune,
                'Transfer with options… (Copy/Move/Sync · filters · dry-run)',
                enabled: hasSel,
                onTap: () => _advancedTransfer(context, ref),
              ),
              _cmd(
                c,
                Icons.close,
                'Clear selection',
                enabled: true,
                onTap: ctrl.clearSelection,
              ),
            ],
            // Explorer pins a "Details" pane toggle at the far right.
            if (chrome.showDetailsToggle)
              _cmdLabeled(
                c,
                Icons.view_sidebar_outlined,
                'Details',
                enabled: true,
                onTap: () => ref
                    .read(inspectorVisibleProvider.notifier)
                    .update((v) => !v),
              ),
          ],
        ),
      ),
    );
  }

  // ── Finder unified toolbar: a single row (hoisted full-width band only) ──
  // Back/Fwd · breadcrumb title · view switcher · size/sort menus · ⋯ overflow
  // (file verbs) · search. Only built when chrome.unifiedToolbar && hoisted, so
  // a narrow dual-pane never renders it.
  Widget _unifiedRow(BuildContext context, WidgetRef ref, AircloneColors c) {
    final ctrl = ref.read(paneProvider(index).notifier);
    final hasRemote = state.remote != null;
    final hasSel = state.selected.isNotEmpty;
    final oneSel = state.selected.length == 1;
    final clipFull = ref.watch(clipboardControllerProvider).isNotEmpty;
    final other = ref.watch(paneProvider(index == 0 ? 1 : 0));
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
        child: Row(
          children: [
            IconButton(
              onPressed: ctrl.canBack ? ctrl.back : null,
              icon: const Icon(Icons.arrow_back, size: 15),
              tooltip: 'Back (Alt+←)',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: ctrl.canForward ? ctrl.forward : null,
              icon: const Icon(Icons.arrow_forward, size: 15),
              tooltip: 'Forward (Alt+→)',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: Space.x1),
            Expanded(
              child: PathBar(
                remote: state.remote,
                path: state.path,
                onSegment: ctrl.goToSegment,
                onNavigate: ctrl.navigateTo,
              ),
            ),
            const SizedBox(width: Space.x1),
            _ViewSegmented(
              mode: state.viewMode,
              onChanged: ctrl.setViewMode,
              c: c,
            ),
            _viewMenu(context, ref, c),
            _sortMenu(context, ref, c),
            _overflowMenu(
              context,
              ref,
              c,
              hasRemote: hasRemote,
              hasSel: hasSel,
              oneSel: oneSel,
              clipFull: clipFull,
              other: other,
            ),
            if (hasRemote) _FilterBox(index: index, width: 220),
          ],
        ),
      ),
    );
  }

  /// The unified toolbar's overflow (⋯) menu — relocates every command-bar verb
  /// here, reusing the same handlers + enable predicates (no logic fork).
  Widget _overflowMenu(
    BuildContext context,
    WidgetRef ref,
    AircloneColors c, {
    required bool hasRemote,
    required bool hasSel,
    required bool oneSel,
    required bool clipFull,
    required BrowserState other,
  }) {
    final ctrl = ref.read(paneProvider(index).notifier);
    MenuItemButton item(IconData icon, String label, VoidCallback? onPressed) =>
        MenuItemButton(
          leadingIcon: Icon(icon, size: 16, color: c.textMuted),
          onPressed: onPressed,
          child: Text(label),
        );
    final toOther = hasSel && other.remote != null;
    return MenuAnchor(
      menuChildren: [
        item(
          Icons.create_new_folder_outlined,
          'New folder',
          hasRemote ? () => _newFolder(context, ref) : null,
        ),
        item(
          Icons.content_cut,
          'Cut',
          hasSel ? () => _clip(ref, cut: true) : null,
        ),
        item(
          Icons.copy_outlined,
          'Copy',
          hasSel ? () => _clip(ref, cut: false) : null,
        ),
        item(
          Icons.content_paste,
          'Paste',
          (clipFull && hasRemote) ? () => _paste(ref) : null,
        ),
        const Divider(height: 8),
        item(
          Icons.drive_file_rename_outline,
          'Rename',
          oneSel ? () => _rename(context, ref) : null,
        ),
        item(
          Icons.delete_outline,
          'Delete',
          hasSel ? () => _delete(context, ref) : null,
        ),
        const Divider(height: 8),
        item(
          Icons.copy_all,
          'Copy to other pane',
          toOther ? () => _transferToOther(ref, JobType.copy) : null,
        ),
        item(
          Icons.drive_file_move_outline,
          'Move to other pane',
          toOther ? () => _transferToOther(ref, JobType.move) : null,
        ),
        item(
          Icons.tune,
          'Transfer with options…',
          hasSel ? () => _advancedTransfer(context, ref) : null,
        ),
        const Divider(height: 8),
        item(Icons.refresh, 'Refresh', hasRemote ? ctrl.refresh : null),
        item(Icons.add, 'New tab', ctrl.newTab),
        item(
          Icons.view_sidebar_outlined,
          'Details',
          () => ref.read(inspectorVisibleProvider.notifier).update((v) => !v),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.more_horiz, size: 18),
        tooltip: 'More actions',
        color: c.textMuted,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// A labelled toolbar button (Explorer's "New", "Details"). Icon + text.
  Widget _cmdLabeled(
    AircloneColors c,
    IconData icon,
    String label, {
    required bool enabled,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: TextButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: c.textMuted,
        disabledForegroundColor: c.textFaint,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
      ),
    ),
  );

  Widget _cmd(
    AircloneColors c,
    IconData icon,
    String tip, {
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) => IconButton(
    onPressed: enabled ? onTap : null,
    icon: Icon(icon, size: 16),
    color: danger ? c.error : c.textMuted,
    tooltip: tip,
    visualDensity: VisualDensity.compact,
  );

  Widget _sep(AircloneColors c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.x1),
    child: Container(width: 1, height: 18, color: c.border),
  );

  Widget _menuButton(
    AircloneColors c,
    String label,
    IconData icon,
    MenuController controller,
  ) => InkWell(
    borderRadius: BorderRadius.circular(Radii.sm),
    onTap: () => controller.isOpen ? controller.close() : controller.open(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c.textMuted),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: c.text, fontSize: 12)),
          Icon(Icons.arrow_drop_down, size: 16, color: c.textMuted),
        ],
      ),
    ),
  );

  Widget _check(AircloneColors c, bool on) => on
      ? Icon(Icons.check, size: 16, color: c.primary)
      : const SizedBox(width: 16);

  Widget _sortMenu(BuildContext context, WidgetRef ref, AircloneColors c) {
    final ctrl = ref.read(paneProvider(index).notifier);
    return MenuAnchor(
      menuChildren: [
        for (final (key, label) in const [
          (SortKey.name, 'Name'),
          (SortKey.size, 'Size'),
          (SortKey.modified, 'Modified'),
        ])
          MenuItemButton(
            leadingIcon: _check(c, state.sortKey == key),
            trailingIcon: state.sortKey == key
                ? Icon(
                    state.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: c.textMuted,
                  )
                : null,
            onPressed: () => ctrl.setSort(key),
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) =>
          _menuButton(c, 'Sort', Icons.swap_vert, controller),
    );
  }

  Widget _viewMenu(BuildContext context, WidgetRef ref, AircloneColors c) {
    final ctrl = ref.read(paneProvider(index).notifier);
    final remote = state.remote;
    final isGrid = state.viewMode == ViewMode.grid;
    final near = _nearestPreset(state.gridSize);
    final disabled = ref.watch(thumbnailsDisabledProvider);
    final thumbsOn = remote != null && thumbnailsOn(remote, disabled);

    return MenuAnchor(
      menuChildren: [
        for (final (label, size) in _viewSizePresets)
          MenuItemButton(
            leadingIcon: _check(c, isGrid && near == size),
            onPressed: () {
              ctrl.setViewMode(ViewMode.grid);
              ctrl.setGridSize(size);
            },
            child: Text(label),
          ),
        MenuItemButton(
          leadingIcon: _check(c, state.viewMode == ViewMode.list),
          onPressed: () => ctrl.setViewMode(ViewMode.list),
          child: const Text('List'),
        ),
        MenuItemButton(
          leadingIcon: _check(c, state.viewMode == ViewMode.media),
          onPressed: () => ctrl.setViewMode(ViewMode.media),
          child: const Text('Media gallery'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: _check(c, thumbsOn),
          onPressed: (remote == null || remote.isLocal)
              ? null
              : () => ref
                    .read(thumbnailsDisabledProvider.notifier)
                    .toggle(remote.fs),
          child: Text(
            remote != null && remote.isLocal
                ? 'Thumbnails (always on)'
                : 'Thumbnails',
          ),
        ),
      ],
      builder: (context, controller, _) =>
          _menuButton(c, 'View', Icons.grid_view_rounded, controller),
    );
  }

  // ── handlers ─────────────────────────────────────────────────────────────
  Future<void> _newFolder(BuildContext context, WidgetRef ref) async {
    final name = await showNewFolderDialog(context);
    if (name == null || state.remote == null) return;
    await ref.read(fileOpsProvider).newFolder(state.remote!, state.path, name);
    await ref.read(paneProvider(index).notifier).refresh();
  }

  void _clip(WidgetRef ref, {required bool cut}) {
    if (state.remote == null || state.selectedEntries.isEmpty) return;
    final clip = ref.read(clipboardControllerProvider.notifier);
    final files = state.selectedEntries;
    cut
        ? clip.cut(state.remote!, state.path, files)
        : clip.copy(state.remote!, state.path, files);
  }

  Future<void> _paste(WidgetRef ref) async {
    final clip = ref.read(clipboardControllerProvider);
    if (clip.isEmpty || clip.remote == null || state.remote == null) return;
    final svc = ref.read(transferServiceProvider);
    for (final f in clip.files) {
      await svc.transfer(
        srcRemote: clip.remote!,
        srcPath: joinPath(clip.parentPath, f.name),
        dstRemote: state.remote!,
        dstPath: joinPath(state.path, f.name),
        type: clip.isCut ? JobType.move : JobType.copy,
      );
    }
    if (clip.isCut) ref.read(clipboardControllerProvider.notifier).clear();
    await ref.read(paneProvider(index).notifier).refresh();
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final files = state.selectedEntries;
    if (files.length != 1 || state.remote == null) return;
    final f = files.first;
    final name = await showRenameDialog(context, f.name);
    if (name == null || name == f.name) return;
    await ref.read(fileOpsProvider).rename(state.remote!, f.path, name);
    await ref.read(paneProvider(index).notifier).refresh();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final files = state.selectedEntries;
    if (files.isEmpty || state.remote == null) return;
    final ok = await showDeleteConfirm(
      context,
      files.length == 1 ? files.first.name : '${files.length} items',
      isDir: files.length == 1 && files.first.isDir,
    );
    if (!ok) return;
    final ops = ref.read(fileOpsProvider);
    for (final f in files) {
      await ops.deleteEntry(state.remote!, f, state.path);
    }
    await ref.read(paneProvider(index).notifier).refresh();
  }

  Future<void> _transferToOther(WidgetRef ref, JobType type) async {
    final from = ref.read(paneProvider(index));
    final to = ref.read(paneProvider(index == 0 ? 1 : 0));
    if (from.remote == null || to.remote == null) return;
    final svc = ref.read(transferServiceProvider);
    for (final f in from.selectedEntries) {
      await svc.transfer(
        srcRemote: from.remote!,
        srcPath: joinPath(from.path, f.name),
        dstRemote: to.remote!,
        dstPath: joinPath(to.path, f.name),
        type: type,
      );
    }
    ref.read(paneProvider(index).notifier).clearSelection();
  }

  /// Opens the advanced Copy/Move/Sync options dialog and runs the chosen
  /// transfer of the selection. Destination is the OTHER pane when it has a
  /// remote open, otherwise the user picks one — so this works in single-pane
  /// mode too (no Advanced Mode required).
  Future<void> _advancedTransfer(BuildContext context, WidgetRef ref) async {
    final from = ref.read(paneProvider(index));
    if (from.remote == null || from.selectedEntries.isEmpty) return;

    final other = ref.read(paneProvider(index == 0 ? 1 : 0));
    Remote dstRemote;
    String dstPath;
    if (other.remote != null) {
      dstRemote = other.remote!;
      dstPath = other.path;
    } else {
      final dst = await showDestinationPicker(context, title: 'Transfer to…');
      if (dst == null) return;
      dstRemote = dst.remote;
      dstPath = dst.path;
    }
    if (!context.mounted) return;

    final options = await showTransferOptionsDialog(
      context,
      fromLabel: '${from.remote!.name}:${from.path}',
      toLabel: '${dstRemote.name}:$dstPath',
    );
    if (options == null) return;
    final svc = ref.read(transferServiceProvider);
    for (final f in from.selectedEntries) {
      await svc.transferAdvanced(
        srcRemote: from.remote!,
        srcPath: joinPath(from.path, f.name),
        dstRemote: dstRemote,
        dstPath: joinPath(dstPath, f.name),
        options: options,
      );
    }
    ref.read(paneProvider(index).notifier).clearSelection();
  }
}

class _FileRow extends ConsumerStatefulWidget {
  const _FileRow({
    required this.file,
    required this.state,
    required this.paneRemote,
    required this.onOpen,
    required this.onToggle,
    required this.onPreview,
    required this.onContextMenu,
    required this.onDropInto,
  });
  final RcloneFile file;
  final BrowserState state;
  final Remote paneRemote;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final VoidCallback onPreview;
  final void Function(Offset globalPosition) onContextMenu;
  final void Function(PaneDragData) onDropInto;

  @override
  ConsumerState<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends ConsumerState<_FileRow> {
  bool _hover = false;

  void _setHover(bool v) {
    if (_hover != v) setState(() => _hover = v);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final state = widget.state;
    final paneRemote = widget.paneRemote;
    final onOpen = widget.onOpen;
    final onToggle = widget.onToggle;
    final onPreview = widget.onPreview;
    final onContextMenu = widget.onContextMenu;
    final onDropInto = widget.onDropInto;

    final c = AircloneTheme.of(context);
    final t = AircloneTheme.tokensOf(context);
    final widths = ref.watch(columnWidthsProvider);
    final selected = state.isSelected(file.name);

    // What gets dragged: the whole selection if this row is selected, else just this row.
    final dragFiles = selected ? state.selectedEntries : <RcloneFile>[file];
    final payload = PaneDragData(paneRemote, state.path, dragFiles);

    // Skins with dividers (Airclone) use a flat full-width fill + bottom line;
    // divider-less skins (Explorer/Finder) use a rounded selection + hover fill.
    final Color? rowColor = selected
        ? c.primary.withValues(alpha: 0.12)
        : (_hover ? c.surfaceSunken.withValues(alpha: 0.7) : null);

    final base = MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
        child: InkWell(
          onTap: file.isDir ? onOpen : onToggle,
          onDoubleTap: file.isDir ? onOpen : onPreview,
          child: Container(
            height: t.rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            decoration: BoxDecoration(
              color: rowColor,
              borderRadius: t.rowDividers
                  ? null
                  : BorderRadius.circular(t.selectionRadius),
              border: t.rowDividers
                  ? Border(
                      bottom: BorderSide(
                        color: c.border.withValues(alpha: 0.4),
                      ),
                    )
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: selected
                      ? Icon(Icons.check_box, size: 16, color: c.primary)
                      : Icon(
                          iconFor(file),
                          size: 17,
                          color: iconColorFor(file, c),
                        ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    file.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: t.bodySize),
                  ),
                ),
                const SizedBox(width: Space.x2),
                SizedBox(
                  width: widths.size,
                  child: Text(
                    file.isDir ? '' : humanSize(file.size),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: c.textFaint, fontSize: 12),
                  ),
                ),
                const SizedBox(width: Space.x2),
                SizedBox(
                  width: widths.modified,
                  child: Text(
                    relativeTime(file.modTime),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: c.textFaint, fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Builder(
                    builder: (bctx) => IconButton(
                      icon: Icon(Icons.more_vert, size: 15, color: c.textFaint),
                      tooltip: 'Actions',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final box = bctx.findRenderObject() as RenderBox?;
                        final pos = box == null
                            ? Offset.zero
                            : box.localToGlobal(box.size.center(Offset.zero));
                        onContextMenu(pos);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Folders accept in-app drops (copy INTO the folder). The whole row is the
    // drag source — drop it in-app OR onto the OS (local files copy out).
    Widget row = base;
    if (file.isDir) {
      row = NativePaneDropRegion(
        onDrop: onDropInto,
        highlightColor: c.primary,
        child: base,
      );
    }

    return NativePaneDraggable(data: payload, child: row);
  }
}

/// Compact client-side filter box (Ctrl+F focuses the active pane's box).
class _FilterBox extends ConsumerStatefulWidget {
  const _FilterBox({required this.index, this.width = 150});
  final int index;
  final double width;

  @override
  ConsumerState<_FilterBox> createState() => _FilterBoxState();
}

class _FilterBoxState extends ConsumerState<_FilterBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(paneProvider(widget.index).notifier);
    final focus = ref.watch(paneFilterFocusProvider(widget.index));
    final filter = ref.watch(
      paneProvider(widget.index).select((s) => s.filter),
    );
    // When navigation clears the filter, clear the text field too.
    ref.listen(paneProvider(widget.index).select((s) => s.filter), (_, next) {
      if (next.isEmpty && _controller.text.isNotEmpty) _controller.clear();
    });
    return SizedBox(
      width: widget.width,
      height: 28,
      child: TextField(
        controller: _controller,
        focusNode: focus,
        style: TextStyle(color: c.text, fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.x2),
          prefixIcon: Icon(Icons.search, size: 14, color: c.textFaint),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          hintText: 'Filter',
          hintStyle: TextStyle(color: c.textFaint, fontSize: 12),
          suffixIcon: filter.isEmpty
              ? null
              : InkWell(
                  onTap: () {
                    _controller.clear();
                    ctrl.setFilter('');
                  },
                  child: Icon(Icons.close, size: 14, color: c.textFaint),
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        onChanged: ctrl.setFilter,
      ),
    );
  }
}
