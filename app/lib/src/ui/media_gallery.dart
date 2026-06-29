import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/thumbnail_service.dart';
import 'file_icon.dart';
import 'native_drag.dart';
import 'thumbnail_image.dart';
import 'pane_drag.dart';
import 'theme/tokens.dart';

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Date-grouped MEDIA gallery (images + video only) with pinned day headers and
/// square thumbnail tiles. Same callback contract as [FileGrid], so the pane can
/// swap it in. Parent supplies a [thumbRequestFor] builder.
class MediaGallery extends ConsumerWidget {
  const MediaGallery({
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
  });

  /// Already sorted; we filter to media (images + video).
  final List<RcloneFile> entries;

  /// Selection source; [state].path is the parentPath.
  final BrowserState state;

  /// Drag payload owner.
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

  /// "MMM d, yyyy" via [_months] (no intl).
  static String _dayLabel(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);

    final media = entries
        .where(
          (f) =>
              !f.isDir &&
              (kindOf(f) == FileKind.image || kindOf(f) == FileKind.video),
        )
        .toList();

    if (media.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, color: c.textFaint, size: 40),
            const SizedBox(height: Space.x2),
            Text(
              'No photos or videos here',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
          ],
        ),
      );
    }

    // Group by local calendar day; null modTime collected separately (placed last).
    final groups = <DateTime, List<RcloneFile>>{};
    final unknown = <RcloneFile>[];
    for (final f in media) {
      final t = f.modTime?.toLocal();
      if (t == null) {
        unknown.add(f);
        continue;
      }
      final day = DateTime(t.year, t.month, t.day);
      (groups[day] ??= <RcloneFile>[]).add(f);
    }

    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: gridSize,
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      childAspectRatio: 1.0,
    );

    final slivers = <Widget>[];
    void addGroup(String label, List<RcloneFile> files) {
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _DateHeaderDelegate(label: label, c: c),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          sliver: SliverGrid(
            gridDelegate: gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, i) => _MediaTile(
                file: files[i],
                c: c,
                state: state,
                remote: remote,
                onToggle: onToggle,
                onPreview: onPreview,
                onContextMenu: onContextMenu,
                request: thumbRequestFor(files[i]),
              ),
              childCount: files.length,
            ),
          ),
        ),
      );
    }

    for (final day in days) {
      addGroup(_dayLabel(day), groups[day]!);
    }
    if (unknown.isNotEmpty) addGroup('Unknown date', unknown);

    return CustomScrollView(slivers: slivers);
  }
}

/// Pinned day header — fixed 30px, translucent surface band.
class _DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DateHeaderDelegate({required this.label, required this.c});

  final String label;
  final AircloneColors c;

  @override
  double get minExtent => 30;

  @override
  double get maxExtent => 30;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      alignment: Alignment.centerLeft,
      color: c.surface.withValues(alpha: 0.96),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.textMuted,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DateHeaderDelegate old) =>
      old.label != label || old.c != c;
}

/// One square media tile (all files — no DragTarget needed).
class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.file,
    required this.c,
    required this.state,
    required this.remote,
    required this.onToggle,
    required this.onPreview,
    required this.onContextMenu,
    required this.request,
  });

  final RcloneFile file;
  final AircloneColors c;
  final BrowserState state;
  final Remote remote;
  final void Function(RcloneFile) onToggle;
  final void Function(RcloneFile) onPreview;
  final void Function(RcloneFile file, Offset globalPosition) onContextMenu;
  final ThumbRequest? request;

  @override
  Widget build(BuildContext context) {
    final selected = state.isSelected(file.name);
    final isVideo = kindOf(file) == FileKind.video;
    final payload = PaneDragData(
      remote,
      state.path,
      selected ? state.selectedEntries : [file],
    );

    final Widget thumb = request != null
        ? ThumbnailImage(
            request: request!,
            placeholder: Center(
              child: Icon(iconFor(file), color: iconColorFor(file, c)),
            ),
          )
        : Container(
            color: c.surfaceSunken,
            child: Center(
              child: Icon(iconFor(file), color: iconColorFor(file, c)),
            ),
          );

    final clip = ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumb,
          if (isVideo)
            const Positioned(
              left: Space.x1,
              bottom: Space.x1,
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 22,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          if (selected)
            Positioned(
              top: Space.x1,
              right: Space.x1,
              child: Icon(Icons.check_circle, color: c.primary, size: 18),
            ),
        ],
      ),
    );

    final framed = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: selected ? Border.all(color: c.primary, width: 2) : null,
      ),
      child: clip,
    );

    final gestures = GestureDetector(
      onSecondaryTapUp: (d) => onContextMenu(file, d.globalPosition),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => onToggle(file),
        onDoubleTap: () => onPreview(file),
        child: framed,
      ),
    );

    return NativePaneDraggable(data: payload, child: gestures);
  }
}
