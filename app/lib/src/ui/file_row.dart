import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import 'column_header.dart';
import 'file_icon.dart';
import 'format.dart';
import 'native_drag.dart';
import 'pane_drag.dart';
import 'theme/tokens.dart';
import 'touch.dart';
import 'tv_row_actions.dart';

/// One Details row: icon · name · size · modified · ⋯, shared by the flat list
/// and the tree so the two cannot drift apart (tree-view plan §4.B).
///
/// The row knows nothing about WHERE the file lives. The caller decides what
/// "selected" means, what a drag carries, and where a drop lands — which is
/// the point: in the tree those come from the row's own parent folder, and a
/// row that read `state.path` for itself would rebuild the v0.5.0 bug.
class FileRow extends ConsumerStatefulWidget {
  const FileRow({
    super.key,
    required this.file,
    required this.selected,
    required this.selectionMode,
    required this.dragData,
    required this.onOpen,
    required this.onToggle,
    required this.onPreview,
    required this.onContextMenu,
    required this.onDropInto,
    this.indent = 0,
    this.leading,
    this.cursor = false,
    this.tapOpensFolder = true,
    this.showDetails = true,
    this.onlineOnly = false,
  });

  final RcloneFile file;

  /// True when this is a cloud placeholder whose contents are not on this
  /// device. Shown with a cloud icon so the download prompt on opening it is
  /// expected rather than a surprise.
  final bool onlineOnly;

  final bool selected;

  /// Touch multi-select mode: a plain tap toggles the row (folders included)
  /// instead of opening/previewing — the phone convention.
  final bool selectionMode;

  /// What dragging this row carries. Built by the caller so the parent path
  /// inside it is the row's real folder.
  final PaneDragData dragData;

  /// Double-click (and single tap on a folder when [tapOpensFolder]).
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final VoidCallback onPreview;
  final void Function(Offset globalPosition) onContextMenu;
  final void Function(PaneDragData) onDropInto;

  /// Left inset before [leading] — the tree's depth indentation.
  final double indent;

  /// Whether to draw the Size and Modified columns.
  ///
  /// False only where the row genuinely has no room for them: the tree on a
  /// narrow pane, where those two fixed columns plus the indentation would
  /// leave the name nothing to occupy. Dropping them is what lets the tree
  /// keep its indentation on a phone, and the indentation IS the tree — a
  /// tree squeezed to zero indent is just a list with arrows.
  final bool showDetails;

  /// A slot before the icon — the tree's disclosure arrow. Null in the list.
  final Widget? leading;

  /// Draw the keyboard-cursor outline (the tree's focused row).
  final bool cursor;

  /// Whether a single tap on a folder opens it (the flat list navigates into
  /// it) rather than selecting it (the tree selects; expansion is the arrow
  /// or a double-click).
  final bool tapOpensFolder;

  @override
  ConsumerState<FileRow> createState() => _FileRowState();
}

class _FileRowState extends ConsumerState<FileRow> {
  bool _hover = false;

  /// The row's ⋯ button, kept out of D-pad traversal on a television — see
  /// [tvSkippableFocusNode] for why.
  late final FocusNode _menuFocus = tvSkippableFocusNode('file row actions');

  @override
  void dispose() {
    _menuFocus.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    if (_hover != v) setState(() => _hover = v);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final onOpen = widget.onOpen;
    final onToggle = widget.onToggle;
    final onPreview = widget.onPreview;
    final onContextMenu = widget.onContextMenu;
    final selected = widget.selected;

    final c = AircloneTheme.of(context);
    final t = AircloneTheme.tokensOf(context);
    final widths = ref.watch(columnWidthsProvider);

    // Skins with dividers (Airclone) use a flat full-width fill + bottom line;
    // divider-less skins (Explorer/Finder) use a rounded selection + hover fill.
    final Color? rowColor = selected
        ? c.primary.withValues(alpha: 0.12)
        : (_hover ? c.surfaceSunken.withValues(alpha: 0.7) : null);

    final BoxBorder? border;
    if (widget.cursor) {
      border = Border.all(color: c.primary.withValues(alpha: 0.7));
    } else if (t.rowDividers) {
      border = Border(
        bottom: BorderSide(color: c.border.withValues(alpha: 0.4)),
      );
    } else {
      border = null;
    }

    final VoidCallback onTap;
    if (widget.selectionMode) {
      onTap = onToggle;
    } else if (file.isDir) {
      onTap = widget.tapOpensFolder ? onOpen : onToggle;
    } else {
      onTap = isTouchPrimary ? onPreview : onToggle;
    }

    final base = MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: GestureDetector(
        onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
        // Touch: long-press = the row's context menu (no right button), and a
        // single tap opens/previews (phone file-manager convention) instead of
        // toggling selection.
        onLongPressStart: (d) => onContextMenu(d.globalPosition),
        child: InkWell(
          onTap: onTap,
          // Touch: no double-tap — a registered recognizer would delay every
          // single tap ~300 ms while the arena waits for a second tap.
          onDoubleTap: isTouchPrimary
              ? null
              : (file.isDir ? onOpen : onPreview),
          child: Container(
            height: t.rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            decoration: BoxDecoration(
              color: rowColor,
              borderRadius: t.rowDividers && !widget.cursor
                  ? null
                  : BorderRadius.circular(t.selectionRadius),
              border: border,
            ),
            child: Row(
              children: [
                if (widget.indent > 0) SizedBox(width: widget.indent),
                ?widget.leading,
                SizedBox(
                  width: 22,
                  child: selected
                      ? Icon(Icons.check_box, size: 16, color: c.primary)
                      : Icon(
                          widget.onlineOnly ? kOnlineOnlyIcon : iconFor(file),
                          size: 17,
                          color: widget.onlineOnly
                              ? c.textMuted
                              : iconColorFor(file, c),
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
                if (widget.showDetails) ...[
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
                ],
                SizedBox(
                  width: 28,
                  child: Builder(
                    builder: (bctx) => IconButton(
                      // A television reported the D-pad drifting onto this
                      // button while moving through the list. Directional
                      // traversal picks by geometry, and a second focusable in
                      // a right-hand column is a second thing UP/DOWN can land
                      // on - so on a TV this stops being a traversal stop and
                      // the row answers RIGHT instead (see [TvRowMenuKey]). It
                      // stays visible and clickable for a pointer.
                      focusNode: _menuFocus,
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
        onDrop: widget.onDropInto,
        highlightColor: c.primary,
        child: base,
      );
    }

    // TV only: RIGHT opens this row's actions, replacing the arrow-key route to
    // the ⋯ that [tvSkippableFocusNode] just removed. A no-op everywhere else.
    return TvRowMenuKey(
      onMenu: onContextMenu,
      child: NativePaneDraggable(data: widget.dragData, child: row),
    );
  }
}
