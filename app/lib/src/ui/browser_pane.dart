import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/clipboard_controller.dart';
import '../state/engine_controller.dart';
import '../state/file_ops.dart';
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
import 'media_gallery.dart';
import 'pane_drag.dart';
import 'path_bar.dart';
import 'quick_look.dart';
import 'theme/tokens.dart';

/// One of the two dual-pane browsers. [index] 0 = A (left), 1 = B (right).
class BrowserPane extends ConsumerWidget {
  const BrowserPane({super.key, required this.index});
  final int index;

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
            _PaneToolbar(index: index, active: active, state: state),
            Divider(height: 1, color: c.border),
            Expanded(
              child: state.remote == null
                  ? _empty(c)
                  : DropTarget(
                      onDragDone: (d) => _uploadLocal(
                        ref,
                        d.files.map((f) => f.path).toList(),
                        state.remote!,
                        state.path,
                      ),
                      child: DragTarget<PaneDragData>(
                        onAcceptWithDetails: (d) =>
                            _dropOnto(ref, d.data, state.remote!, state.path),
                        builder: (_, cand, _) => GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onSecondaryTapDown: (d) => _showEmptyMenu(
                            context,
                            ref,
                            state,
                            d.globalPosition,
                          ),
                          child: _body(
                            context,
                            ref,
                            state,
                            highlight: cand.isNotEmpty,
                          ),
                        ),
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
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final downloads = '${home.replaceAll('\\', '/')}/Downloads';
    final local = Remote(
      name: 'Downloads',
      type: 'local',
      fs: '$downloads/',
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

  Future<void> _dropOnto(
    WidgetRef ref,
    PaneDragData data,
    Remote dstRemote,
    String dstPath,
  ) async {
    final svc = ref.read(transferServiceProvider);
    for (final f in data.files) {
      await svc.transfer(
        srcRemote: data.remote,
        srcPath: joinPath(data.parentPath, f.name),
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
class _PaneToolbar extends ConsumerWidget {
  const _PaneToolbar({
    required this.index,
    required this.active,
    required this.state,
  });
  final int index;
  final bool active;
  final BrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(paneProvider(index).notifier);
    final segs = state.segments;
    final hasSel = state.selected.isNotEmpty;
    final other = ref.watch(paneProvider(index == 0 ? 1 : 0));

    return Container(
      height: 40,
      color: active ? c.surfaceRaised : c.surface,
      padding: const EdgeInsets.symmetric(horizontal: Space.x2),
      child: Row(
        children: [
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
            onPressed: state.remote == null
                ? null
                : () => _newFolder(context, ref),
            icon: const Icon(Icons.create_new_folder_outlined, size: 15),
            tooltip: 'New folder',
            visualDensity: VisualDensity.compact,
          ),
          if (state.remote != null) _ViewControls(index: index),
          const SizedBox(width: Space.x1),
          Expanded(
            child: PathBar(
              remote: state.remote,
              path: state.path,
              onSegment: ctrl.goToSegment,
              onNavigate: ctrl.navigateTo,
            ),
          ),
          if (state.remote != null) _FilterBox(index: index),
          if (hasSel) ...[
            Text(
              '${state.selected.length}',
              style: TextStyle(
                color: c.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              tooltip: 'Copy selected to the other pane',
              onPressed: other.remote == null
                  ? null
                  : () => _transferToOther(ref, JobType.copy),
              icon: const Icon(Icons.copy_all, size: 15),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: 'Move selected to the other pane',
              onPressed: other.remote == null
                  ? null
                  : () => _transferToOther(ref, JobType.move),
              icon: const Icon(Icons.drive_file_move_outline, size: 15),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: 'Clear selection',
              onPressed: ctrl.clearSelection,
              icon: const Icon(Icons.close, size: 15),
              visualDensity: VisualDensity.compact,
            ),
          ],
          if (state.remote != null)
            IconButton(
              tooltip: 'Close pane (deselect remote)',
              onPressed: ctrl.clear,
              icon: const Icon(Icons.cancel_outlined, size: 15),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Future<void> _newFolder(BuildContext context, WidgetRef ref) async {
    final name = await showNewFolderDialog(context);
    if (name == null || state.remote == null) return;
    await ref.read(fileOpsProvider).newFolder(state.remote!, state.path, name);
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
}

/// Compact list/grid toggle + a popover with grid density and the per-remote
/// Thumbnails switch. Lives in the pane toolbar (one per pane).
class _ViewControls extends ConsumerWidget {
  const _ViewControls({required this.index});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(paneProvider(index).notifier);
    final mode = ref.watch(paneProvider(index).select((s) => s.viewMode));

    Widget seg(ViewMode m, IconData icon, String tip) {
      final on = mode == m;
      return IconButton(
        tooltip: tip,
        icon: Icon(icon, size: 15),
        color: on ? c.primary : c.textMuted,
        visualDensity: VisualDensity.compact,
        onPressed: () => ctrl.setViewMode(m),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        seg(ViewMode.list, Icons.view_list_rounded, 'List view'),
        seg(ViewMode.grid, Icons.grid_view_rounded, 'Grid view'),
        seg(ViewMode.media, Icons.photo_library_rounded, 'Media view'),
        MenuAnchor(
          menuChildren: [_ViewSettingsPanel(index: index)],
          builder: (context, controller, _) => IconButton(
            tooltip: 'View settings',
            icon: const Icon(Icons.tune_rounded, size: 15),
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      ],
    );
  }
}

/// The popover body: grid-size slider + per-remote Thumbnails switch.
class _ViewSettingsPanel extends ConsumerWidget {
  const _ViewSettingsPanel({required this.index});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(paneProvider(index));
    final ctrl = ref.read(paneProvider(index).notifier);
    final remote = state.remote;
    final disabled = ref.watch(thumbnailsDisabledProvider);
    final isLocal = remote?.isLocal ?? false;
    final thumbsOn = remote != null && thumbnailsOn(remote, disabled);

    return SizedBox(
      width: 248,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.x4,
          Space.x3,
          Space.x4,
          Space.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GRID SIZE',
              style: TextStyle(
                color: c.textFaint,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            Slider(
              value: state.gridSize.clamp(80, 180),
              min: 80,
              max: 180,
              onChanged: ctrl.setGridSize,
            ),
            Divider(height: Space.x4, color: c.border),
            Row(
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 16,
                  color: thumbsOn ? c.primary : c.textMuted,
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    'Thumbnails',
                    style: TextStyle(color: c.text, fontSize: 13),
                  ),
                ),
                Switch(
                  // Local folders are always on (no bandwidth cost); the toggle
                  // disables previews for a cloud remote.
                  value: thumbsOn,
                  onChanged: (remote == null || isLocal)
                      ? null
                      : (_) => ref
                            .read(thumbnailsDisabledProvider.notifier)
                            .toggle(remote.fs),
                ),
              ],
            ),
            Text(
              remote == null
                  ? 'Image & video previews.'
                  : isLocal
                  ? 'Always on for local folders.'
                  : thumbsOn
                  ? 'On for "${remote.name}" · turn off to save bandwidth.'
                  : 'Off for "${remote.name}" · no preview downloads.',
              style: TextStyle(color: c.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final selected = state.isSelected(file.name);

    // What gets dragged: the whole selection if this row is selected, else just this row.
    final dragFiles = selected ? state.selectedEntries : <RcloneFile>[file];
    final payload = PaneDragData(paneRemote, state.path, dragFiles);

    final base = GestureDetector(
      onSecondaryTapDown: (d) => onContextMenu(d.globalPosition),
      child: InkWell(
        onTap: file.isDir ? onOpen : onToggle,
        onDoubleTap: file.isDir ? onOpen : onPreview,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          decoration: BoxDecoration(
            color: selected ? c.primary.withValues(alpha: 0.12) : null,
            border: Border(
              bottom: BorderSide(color: c.border.withValues(alpha: 0.4)),
            ),
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
                  style: TextStyle(color: c.text, fontSize: 13),
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  file.isDir ? '' : humanSize(file.size),
                  textAlign: TextAlign.right,
                  style: TextStyle(color: c.textFaint, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  relativeTime(file.modTime),
                  textAlign: TextAlign.right,
                  style: TextStyle(color: c.textFaint, fontSize: 12),
                ),
              ),
              Builder(
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
            ],
          ),
        ),
      ),
    );

    // Folders are drop targets (drop INTO the folder); everything is draggable.
    Widget row = base;
    if (file.isDir) {
      row = DragTarget<PaneDragData>(
        onAcceptWithDetails: (d) => onDropInto(d.data),
        builder: (_, cand, _) => Container(
          decoration: cand.isNotEmpty
              ? BoxDecoration(color: c.primary.withValues(alpha: 0.10))
              : null,
          child: base,
        ),
      );
    }

    return Draggable<PaneDragData>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _dragFeedback(c, dragFiles.length),
      child: row,
    );
  }

  Widget _dragFeedback(AircloneColors c, int count) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x3,
        vertical: Space.x2,
      ),
      decoration: BoxDecoration(
        color: c.primary,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.drive_file_move, size: 16, color: c.onPrimary),
          const SizedBox(width: Space.x2),
          Text(
            count == 1 ? file.name : '$count items',
            style: TextStyle(color: c.onPrimary, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

/// Compact client-side filter box (Ctrl+F focuses the active pane's box).
class _FilterBox extends ConsumerStatefulWidget {
  const _FilterBox({required this.index});
  final int index;

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
      width: 150,
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
