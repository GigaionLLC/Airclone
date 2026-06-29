import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/rclone_file.dart';
import 'theme/tokens.dart';

/// Which column the file list is currently sorted by.
enum SortKey { name, size, modified }

/// Comparator for [RcloneFile] entries used to drive sortable columns.
///
/// Folders are ALWAYS grouped before files, regardless of [key] or
/// [ascending]. Within the same type, entries are compared by [key]:
/// - [SortKey.name]: case-insensitive name.
/// - [SortKey.size]: byte size.
/// - [SortKey.modified]: [RcloneFile.modTime], with `null` modTimes sorted
///   last (after all dated entries) irrespective of direction.
///
/// The [ascending] flag reverses the primary comparison when `false`. A final
/// case-insensitive ascending name tie-break keeps the ordering stable.
int compareRcloneFiles(
  RcloneFile a,
  RcloneFile b,
  SortKey key,
  bool ascending,
) {
  // Folders first — this is independent of sort key/direction.
  if (a.isDir != b.isDir) {
    return a.isDir ? -1 : 1;
  }

  int primary;
  switch (key) {
    case SortKey.name:
      primary = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    case SortKey.size:
      primary = a.size.compareTo(b.size);
    case SortKey.modified:
      // Nulls last, regardless of direction.
      final am = a.modTime;
      final bm = b.modTime;
      if (am == null && bm == null) {
        primary = 0;
      } else if (am == null) {
        return 1;
      } else if (bm == null) {
        return -1;
      } else {
        primary = am.compareTo(bm);
      }
  }

  if (!ascending) primary = -primary;
  if (primary != 0) return primary;

  // Stable tie-break: case-insensitive name ascending.
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// User-adjustable widths (in logical pixels) for the two fixed Details
/// columns. The Name column is flexible and takes the remaining space.
class ColumnWidths {
  const ColumnWidths({required this.size, required this.modified});

  /// Width of the "Size" column.
  final double size;

  /// Width of the "Modified" column.
  final double modified;

  ColumnWidths copyWith({double? size, double? modified}) => ColumnWidths(
    size: size ?? this.size,
    modified: modified ?? this.modified,
  );
}

/// Persisted controller for the resizable Details column widths.
///
/// Widths are clamped to sane ranges and saved to [SharedPreferences] under
/// [_keySize] / [_keyModified]. The prefs-load idiom mirrors
/// `advanced_mode.dart`.
class ColumnWidthsController extends Notifier<ColumnWidths> {
  static const _keySize = 'col_w_size';
  static const _keyModified = 'col_w_modified';

  static const _defaultSize = 92.0;
  static const _defaultModified = 132.0;

  static const _minSize = 60.0;
  static const _maxSize = 220.0;
  static const _minModified = 90.0;
  static const _maxModified = 260.0;

  @override
  ColumnWidths build() {
    _load();
    return const ColumnWidths(size: _defaultSize, modified: _defaultModified);
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final size = (p.getDouble(_keySize) ?? _defaultSize).clamp(
        _minSize,
        _maxSize,
      );
      final modified = (p.getDouble(_keyModified) ?? _defaultModified).clamp(
        _minModified,
        _maxModified,
      );
      state = ColumnWidths(size: size, modified: modified);
    } catch (_) {
      // keep defaults
    }
  }

  Future<void> setSize(double v) async {
    final clamped = v.clamp(_minSize, _maxSize);
    state = state.copyWith(size: clamped);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_keySize, clamped);
    } catch (_) {
      // best-effort
    }
  }

  Future<void> setModified(double v) async {
    final clamped = v.clamp(_minModified, _maxModified);
    state = state.copyWith(modified: clamped);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_keyModified, clamped);
    } catch (_) {
      // best-effort
    }
  }
}

final columnWidthsProvider =
    NotifierProvider<ColumnWidthsController, ColumnWidths>(
      ColumnWidthsController.new,
    );

/// A 28px-tall header row that sits directly above the file [ListView] and
/// mirrors its column layout (checkbox slot, name, size, modified).
///
/// Tapping a label invokes [onSort] with that column's [SortKey]. The active
/// column is tinted with the primary color and shows an up/down arrow matching
/// [ascending]. The Size and Modified columns are user-resizable via the thin
/// draggable divider on each cell's left edge; widths are read from
/// [columnWidthsProvider].
class ColumnHeader extends ConsumerWidget {
  const ColumnHeader({
    super.key,
    required this.sortKey,
    required this.ascending,
    required this.onSort,
  });

  /// The column the list is currently sorted by.
  final SortKey sortKey;

  /// Whether the active column is sorted ascending.
  final bool ascending;

  /// Invoked with the tapped column's key.
  final void Function(SortKey) onSort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final widths = ref.watch(columnWidthsProvider);
    final controller = ref.read(columnWidthsProvider.notifier);

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
      child: Row(
        children: [
          // Aligns with the file-row checkbox column.
          const SizedBox(width: 22),
          const SizedBox(width: Space.x2),
          Expanded(
            child: _HeaderLabel(
              label: 'Name',
              column: SortKey.name,
              activeKey: sortKey,
              ascending: ascending,
              onSort: onSort,
              colors: c,
            ),
          ),
          _ResizeHandle(
            colors: c,
            onDelta: (d) => controller.setSize(widths.size - d),
          ),
          SizedBox(
            width: widths.size,
            child: _HeaderLabel(
              label: 'Size',
              column: SortKey.size,
              activeKey: sortKey,
              ascending: ascending,
              onSort: onSort,
              colors: c,
              alignEnd: true,
            ),
          ),
          _ResizeHandle(
            colors: c,
            onDelta: (d) => controller.setModified(widths.modified - d),
          ),
          SizedBox(
            width: widths.modified,
            child: _HeaderLabel(
              label: 'Modified',
              column: SortKey.modified,
              activeKey: sortKey,
              ascending: ascending,
              onSort: onSort,
              colors: c,
              alignEnd: true,
            ),
          ),
          // Mirrors the per-row actions button so columns line up with the list.
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

/// A thin draggable vertical divider placed on the LEFT edge of a fixed
/// column. Dragging horizontally reports the pointer delta via [onDelta];
/// a rightward drag (positive delta) shrinks the column to its right, so
/// callers subtract the delta from the current width.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.colors, required this.onDelta});

  final AircloneColors colors;
  final void Function(double delta) onDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        child: SizedBox(
          width: Space.x2,
          height: double.infinity,
          child: Center(
            child: Container(width: 1, height: 14, color: colors.border),
          ),
        ),
      ),
    );
  }
}

/// A single tappable column label with an optional sort-direction arrow.
class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel({
    required this.label,
    required this.column,
    required this.activeKey,
    required this.ascending,
    required this.onSort,
    required this.colors,
    this.alignEnd = false,
  });

  final String label;
  final SortKey column;
  final SortKey activeKey;
  final bool ascending;
  final void Function(SortKey) onSort;
  final AircloneColors colors;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final isActive = column == activeKey;
    final color = isActive ? colors.primary : colors.textMuted;

    final children = <Widget>[
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      if (isActive) ...[
        const SizedBox(width: Space.x1),
        Icon(
          ascending ? Icons.arrow_upward : Icons.arrow_downward,
          size: 12,
          color: colors.primary,
        ),
      ],
    ];

    return InkWell(
      onTap: () => onSort(column),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x1),
        child: Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: children,
        ),
      ),
    );
  }
}
