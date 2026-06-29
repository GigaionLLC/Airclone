import 'package:flutter/material.dart';

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

/// A 28px-tall header row that sits directly above the file [ListView] and
/// mirrors its column layout (checkbox slot, name, size, modified).
///
/// Tapping a label invokes [onSort] with that column's [SortKey]. The active
/// column is tinted with the primary color and shows an up/down arrow matching
/// [ascending].
class ColumnHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);

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
          SizedBox(
            width: 80,
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
          SizedBox(
            width: 50,
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
        ],
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
