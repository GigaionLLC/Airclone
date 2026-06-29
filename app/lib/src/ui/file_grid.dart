import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/thumbnail_service.dart';
import 'file_icon.dart';
import 'folder_thumbnail.dart';
import 'thumbnail_image.dart';
import 'pane_drag.dart';
import 'theme/tokens.dart';

/// Virtualized GRID of rclone entries — the alpha.7 hero view. Mirrors the list
/// rows' gestures and drag/drop as icon/thumbnail cards. Decoupled from the
/// rclone client: the parent supplies a [thumbRequestFor] builder.
class FileGrid extends ConsumerWidget {
  const FileGrid({
    super.key,
    required this.entries,
    required this.state,
    required this.remote,
    required this.gridSize,
    required this.onOpen,
    required this.onToggle,
    required this.onPreview,
    required this.onContextMenu,
    required this.onDropInto,
    required this.thumbRequestFor,
    this.folderPreviews = false,
  });

  /// Already filtered + sorted; rendered as-is.
  final List<RcloneFile> entries;

  /// Selection source.
  final BrowserState state;

  /// Drag payload owner; parentPath is [state].path.
  final Remote remote;

  /// Target tile width in px.
  final double gridSize;

  final void Function(RcloneFile) onOpen;
  final void Function(RcloneFile) onToggle;
  final void Function(RcloneFile) onPreview;
  final void Function(RcloneFile file, Offset globalPosition) onContextMenu;
  final void Function(RcloneFile dir, PaneDragData data) onDropInto;

  /// Null => render an icon only (no thumbnail).
  final ThumbRequest? Function(RcloneFile) thumbRequestFor;

  /// When true, folders render a composite preview of their first images.
  final bool folderPreviews;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.all(Space.x3),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: gridSize,
        mainAxisSpacing: Space.x2,
        crossAxisSpacing: Space.x2,
        childAspectRatio: 0.8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => _GridTile(
        file: entries[i],
        c: c,
        state: state,
        remote: remote,
        gridSize: gridSize,
        onOpen: onOpen,
        onToggle: onToggle,
        onPreview: onPreview,
        onContextMenu: onContextMenu,
        onDropInto: onDropInto,
        request: thumbRequestFor(entries[i]),
        folderPreviews: folderPreviews,
      ),
    );
  }
}

/// One card in the [FileGrid].
class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.file,
    required this.c,
    required this.state,
    required this.remote,
    required this.gridSize,
    required this.onOpen,
    required this.onToggle,
    required this.onPreview,
    required this.onContextMenu,
    required this.onDropInto,
    required this.request,
    required this.folderPreviews,
  });

  final RcloneFile file;
  final AircloneColors c;
  final BrowserState state;
  final Remote remote;
  final double gridSize;
  final void Function(RcloneFile) onOpen;
  final void Function(RcloneFile) onToggle;
  final void Function(RcloneFile) onPreview;
  final void Function(RcloneFile file, Offset globalPosition) onContextMenu;
  final void Function(RcloneFile dir, PaneDragData data) onDropInto;
  final ThumbRequest? request;
  final bool folderPreviews;

  @override
  Widget build(BuildContext context) {
    final selected = state.isSelected(file.name);
    final payload = PaneDragData(
      remote,
      state.path,
      selected ? state.selectedEntries : [file],
    );

    final tile = _tile(selected);

    final draggable = Draggable<PaneDragData>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _feedback(payload),
      child: tile,
    );

    if (!file.isDir) return draggable;

    return DragTarget<PaneDragData>(
      onAcceptWithDetails: (d) => onDropInto(file, d.data),
      builder: (context, candidate, rejected) => Stack(
        fit: StackFit.expand,
        children: [
          draggable,
          if (candidate.isNotEmpty)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(bool selected) {
    return GestureDetector(
      onSecondaryTapUp: (d) => onContextMenu(file, d.globalPosition),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: file.isDir ? () => onOpen(file) : () => onToggle(file),
        onDoubleTap: file.isDir ? () => onOpen(file) : () => onPreview(file),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? c.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Space.x1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(child: _thumbBox(selected)),
                const SizedBox(height: Space.x1),
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: c.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbBox(bool selected) {
    final icon = Icon(
      iconFor(file),
      color: iconColorFor(file, c),
      size: gridSize * 0.34,
    );

    final Widget content = request != null
        ? ThumbnailImage(
            request: request!,
            placeholder: Center(
              child: Icon(iconFor(file), color: iconColorFor(file, c)),
            ),
          )
        : (file.isDir && folderPreviews)
        ? FolderThumbnail(
            remote: remote,
            parentPath: state.path,
            folder: file,
            placeholder: Center(child: icon),
          )
        : Center(child: icon);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
        border: selected ? Border.all(color: c.primary, width: 2) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (selected)
              Positioned(
                top: Space.x1,
                left: Space.x1,
                child: Icon(Icons.check_circle, color: c.primary, size: 16),
              ),
          ],
        ),
      ),
    );
  }

  Widget _feedback(PaneDragData payload) {
    final count = payload.files.length;
    final label = count > 1 ? '$count items' : file.name;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: Space.x1,
        ),
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.circular(Radii.full),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: c.onPrimary),
        ),
      ),
    );
  }
}
