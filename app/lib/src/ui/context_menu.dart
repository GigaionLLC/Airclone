import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// Actions offered when right-clicking a file or folder row.
enum FileMenuAction {
  open,
  preview,
  openWith,
  revealInFolder,
  copyPath,
  download,
  copy,
  cut,
  paste,
  copyTo,
  moveTo,
  rename,
  delete,
  publicLink,
  openInOtherPane,
}

/// Actions offered when right-clicking empty space in a pane.
enum EmptyMenuAction { paste, newFolder, refresh, selectAll }

/// One row (or a separator) in a context menu.
class _Entry<T> {
  const _Entry.item(this.value, this.icon, this.label, {this.danger = false})
    : isDivider = false;
  const _Entry.divider()
    : value = null,
      icon = null,
      label = null,
      danger = false,
      isDivider = true;

  final T? value;
  final IconData? icon;
  final String? label;
  final bool danger;
  final bool isDivider;
}

_Entry<T> _item<T>(
  T value,
  IconData icon,
  String label, {
  bool danger = false,
}) => _Entry<T>.item(value, icon, label, danger: danger);

/// Shows the rich right-click menu for a file/folder row and resolves to the
/// chosen [FileMenuAction], or `null` if dismissed. Appears instantly (no fetch,
/// no scale-in) at [globalPosition].
Future<FileMenuAction?> showFileContextMenu(
  BuildContext context,
  Offset globalPosition, {
  required bool isDir,
  required bool canPaste,
  required bool hasOtherPane,
  bool canPublicLink = false,
  bool isLocal = false,
}) {
  final entries = <_Entry<FileMenuAction>>[
    if (isDir)
      _item(FileMenuAction.open, Icons.folder_open_outlined, 'Open')
    else
      _item(FileMenuAction.preview, Icons.visibility_outlined, 'Preview'),
    // Local files/folders interop with the OS via official, verifiable actions.
    if (isLocal) ...[
      if (!isDir)
        _item(
          FileMenuAction.openWith,
          Icons.open_in_new_outlined,
          'Open with default app',
        ),
      _item(
        FileMenuAction.revealInFolder,
        Icons.folder_open_outlined,
        'Show in File Explorer',
      ),
    ] else
      _item(FileMenuAction.download, Icons.download_outlined, 'Download'),
    _item(FileMenuAction.copyPath, Icons.content_copy_outlined, 'Copy path'),
    const _Entry.divider(),
    _item(FileMenuAction.copy, Icons.copy_outlined, 'Copy'),
    _item(FileMenuAction.cut, Icons.content_cut_outlined, 'Cut'),
    if (canPaste)
      _item(FileMenuAction.paste, Icons.content_paste_outlined, 'Paste'),
    const _Entry.divider(),
    _item(FileMenuAction.copyTo, Icons.drive_file_move_outline, 'Copy to…'),
    _item(
      FileMenuAction.moveTo,
      Icons.drive_file_move_rtl_outlined,
      'Move to…',
    ),
    if (hasOtherPane)
      _item(
        FileMenuAction.openInOtherPane,
        Icons.splitscreen_outlined,
        'Open in other pane',
      ),
    const _Entry.divider(),
    _item(FileMenuAction.rename, Icons.edit_outlined, 'Rename'),
    _item(FileMenuAction.delete, Icons.delete_outline, 'Delete', danger: true),
    if (canPublicLink) ...[
      const _Entry.divider(),
      _item(FileMenuAction.publicLink, Icons.link_outlined, 'Get public link'),
    ],
  ];
  return _show<FileMenuAction>(context, globalPosition, entries);
}

/// Shows the right-click menu for empty pane space and resolves to the chosen
/// [EmptyMenuAction], or `null` if dismissed. [canPaste] reveals Paste.
Future<EmptyMenuAction?> showEmptyContextMenu(
  BuildContext context,
  Offset globalPosition, {
  required bool canPaste,
}) {
  final entries = <_Entry<EmptyMenuAction>>[
    if (canPaste)
      _item(EmptyMenuAction.paste, Icons.content_paste_outlined, 'Paste'),
    _item(
      EmptyMenuAction.newFolder,
      Icons.create_new_folder_outlined,
      'New folder',
    ),
    _item(EmptyMenuAction.refresh, Icons.refresh_outlined, 'Refresh'),
    _item(EmptyMenuAction.selectAll, Icons.select_all_outlined, 'Select all'),
  ];
  return _show<EmptyMenuAction>(context, globalPosition, entries);
}

Future<T?> _show<T>(
  BuildContext context,
  Offset globalPosition,
  List<_Entry<T>> entries,
) {
  return Navigator.of(context).push(
    _ContextMenuRoute<T>(
      position: globalPosition,
      colors: AircloneTheme.of(context),
      entries: entries,
    ),
  );
}

/// A near-instant popup route for the context menu: no barrier tint, an almost
/// imperceptible fade, and no scale/grow animation — so it feels as snappy as a
/// native OS menu.
class _ContextMenuRoute<T> extends PopupRoute<T> {
  _ContextMenuRoute({
    required this.position,
    required this.colors,
    required this.entries,
  });

  final Offset position;
  final AircloneColors colors;
  final List<_Entry<T>> entries;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 60);

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return CustomSingleChildLayout(
      delegate: _MenuLayout(position, MediaQuery.of(context).size),
      child: _MenuPanel<T>(
        colors: colors,
        entries: entries,
        onSelected: (v) => Navigator.of(context).pop(v),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

/// Positions the menu at the cursor, nudged to stay on screen.
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.target, this.screen);
  final Offset target;
  final Size screen;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = target.dx;
    var y = target.dy;
    if (x + childSize.width > screen.width) {
      x = screen.width - childSize.width - 4;
    }
    if (y + childSize.height > screen.height) {
      y = screen.height - childSize.height - 4;
    }
    return Offset(x.clamp(4, screen.width), y.clamp(4, screen.height));
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.target != target || oldDelegate.screen != screen;
}

class _MenuPanel<T> extends StatelessWidget {
  const _MenuPanel({
    required this.colors,
    required this.entries,
    required this.onSelected,
  });

  final AircloneColors colors;
  final List<_Entry<T>> entries;
  final void Function(T value) onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: Space.x1),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in entries)
                if (e.isDivider)
                  Divider(
                    height: 9,
                    thickness: 1,
                    color: colors.border,
                    indent: Space.x2,
                    endIndent: Space.x2,
                  )
                else
                  _MenuRow<T>(
                    colors: colors,
                    entry: e,
                    onTap: () => onSelected(e.value as T),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({
    required this.colors,
    required this.entry,
    required this.onTap,
  });

  final AircloneColors colors;
  final _Entry<T> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = entry.danger ? colors.error : colors.text;
    return InkWell(
      onTap: onTap,
      hoverColor: colors.primary.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: Space.x2,
        ),
        child: Row(
          children: [
            Icon(
              entry.icon,
              size: 18,
              color: entry.danger ? colors.error : colors.textMuted,
            ),
            const SizedBox(width: Space.x3),
            Text(
              entry.label ?? '',
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: Space.x5),
          ],
        ),
      ),
    );
  }
}
