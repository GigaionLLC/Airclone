import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import 'column_header.dart';
import 'file_row.dart';
import 'pane_drag.dart';
import 'theme/tokens.dart';
import 'touch.dart';

/// Per-level indentation in the tree.
const double kTreeIndent = 18;

/// Width of the disclosure slot that precedes every tree row's icon.
const double _disclosureWidth = 18;

/// The narrowest the Name column may get before indentation stops growing
/// (plan §5: the name is what tells a folder apart, and a tree makes an
/// overflowing name the common case).
const double _minNameWidth = 140;

/// The tree view (tree-view plan §4.B): ONE flat `ListView` over the
/// flattened forest — never a scrollable per level — with a disclosure arrow
/// on folders, indentation by depth, and the Details columns.
///
/// Every callback hands back the [TreeRow], and a row carries the folder it
/// was listed from. The pane resolves paths from that, never from
/// `state.path`, which in this view is only the root the tree hangs from.
///
/// Keyboard (plan §4.E), while the tree has focus:
/// - Up / Down move the cursor (and select it); Home / End jump.
/// - Left collapses an open folder, else climbs to the parent row.
/// - Right expands a closed folder, else steps to its first child.
/// - Enter / Space toggle a folder, or preview a file.
/// - Delete, F2, Ctrl+C / Ctrl+X act on the selection through the pane, the
///   same handlers the toolbar uses. Ctrl+A and Escape are left to the shell,
///   whose select-all / clear are already tree-aware.
class TreeView extends ConsumerStatefulWidget {
  const TreeView({
    super.key,
    required this.index,
    required this.state,
    required this.rows,
    required this.paneRemote,
    required this.scrollController,
    required this.onPreview,
    required this.onContextMenu,
    required this.onDropInto,
    required this.onDeleteKey,
    required this.onRenameKey,
    required this.onClipKey,
    this.physics,
  });

  final int index;
  final BrowserState state;

  /// The flattened forest, top to bottom — see `flattenTree`.
  final List<TreeRow> rows;
  final Remote paneRemote;
  final ScrollController scrollController;
  final void Function(TreeRow row) onPreview;
  final void Function(TreeRow row, Offset globalPosition) onContextMenu;
  final void Function(TreeRow row, PaneDragData data) onDropInto;
  final VoidCallback onDeleteKey;
  final VoidCallback onRenameKey;
  final void Function({required bool cut}) onClipKey;
  final ScrollPhysics? physics;

  @override
  ConsumerState<TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends ConsumerState<TreeView> {
  final _focus = FocusNode(debugLabel: 'tree view');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  BrowserController get _ctrl => ref.read(paneProvider(widget.index).notifier);

  TreeState get _tree => widget.state.tree;

  int get _cursorIndex {
    final cur = _tree.cursor;
    if (cur == null) return -1;
    return widget.rows.indexWhere((r) => r.isEntry && r.path == cur);
  }

  @override
  void didUpdateWidget(TreeView old) {
    super.didUpdateWidget(old);
    // Type-to-jump and the search dialog move the cursor from outside; keep
    // the row it landed on in view, as the flat list does for its selection.
    if (old.state.tree.cursor != _tree.cursor) _revealCursor();
  }

  void _revealCursor() {
    final i = _cursorIndex;
    if (i < 0) return;
    final sc = widget.scrollController;
    if (!sc.hasClients) return;
    final rowH = AircloneTheme.tokensOf(context).rowHeight;
    final top = i * rowH;
    final bottom = top + rowH;
    final pos = sc.position;
    double? target;
    if (top < pos.pixels) {
      target = top;
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      target = bottom - pos.viewportDimension;
    }
    if (target == null) return;
    sc.animateTo(
      target.clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  // ── keyboard ───────────────────────────────────────────────────────────────

  /// The next entry row after [from] in [step] direction (skipping the
  /// "Empty" / error placeholders), or -1.
  int _step(int from, int step) {
    var i = from + step;
    while (i >= 0 && i < widget.rows.length) {
      if (widget.rows[i].isEntry) return i;
      i += step;
    }
    return -1;
  }

  int _firstEntry() => _step(-1, 1);
  int _lastEntry() => _step(widget.rows.length, -1);

  void _moveTo(int i) {
    if (i < 0 || i >= widget.rows.length) return;
    _ctrl.selectTreeOnly(widget.rows[i].path);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hk = HardwareKeyboard.instance;
    final ctrl = hk.isControlPressed || hk.isMetaPressed;
    final plain = !ctrl && !hk.isAltPressed && !hk.isShiftPressed;
    final key = event.logicalKey;

    if (ctrl && !hk.isAltPressed && !hk.isShiftPressed) {
      if (key == LogicalKeyboardKey.keyC) {
        widget.onClipKey(cut: false);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        widget.onClipKey(cut: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!plain) return KeyEventResult.ignored;

    final i = _cursorIndex;
    final row = i >= 0 ? widget.rows[i] : null;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveTo(i < 0 ? _firstEntry() : _step(i, 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveTo(i < 0 ? _lastEntry() : _step(i, -1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _moveTo(_firstEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _moveTo(_lastEntry());
      return KeyEventResult.handled;
    }
    if (row == null) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (row.isDir && _tree.expanded.contains(row.path)) {
        _ctrl.collapseNode(row.path);
      } else if (row.depth > 0) {
        // Climb to the parent row: the nearest entry above at depth - 1.
        for (var j = i - 1; j >= 0; j--) {
          final r = widget.rows[j];
          if (r.isEntry && r.depth == row.depth - 1) {
            _moveTo(j);
            break;
          }
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!row.isDir) return KeyEventResult.handled;
      if (!_tree.expanded.contains(row.path)) {
        _ctrl.expandNode(row.path);
      } else {
        final next = _step(i, 1);
        if (next >= 0 && widget.rows[next].depth == row.depth + 1) {
          _moveTo(next);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (row.isDir) {
        _ctrl.toggleExpand(row.path);
      } else {
        widget.onPreview(row);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      widget.onDeleteKey();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2) {
      widget.onRenameKey();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── rows ───────────────────────────────────────────────────────────────────

  /// What dragging [row] carries: the selected rows that share ITS folder when
  /// it is selected (one source folder — the shape a drop target can take),
  /// else the row alone. Rows selected in other folders are not silently
  /// included under the wrong parent.
  PaneDragData _dragData(TreeRow row) {
    final files = <RcloneFile>[row.file];
    if (widget.state.isTreeSelected(row.path)) {
      files.clear();
      for (final r in widget.state.selectedTreeRows) {
        if (r.parentPath == row.parentPath) files.add(r.file);
      }
      if (files.isEmpty) files.add(row.file);
    }
    return PaneDragData(widget.paneRemote, row.parentPath, files);
  }

  Widget _disclosure(TreeRow row, AircloneColors c) {
    if (!row.isDir) return const SizedBox(width: _disclosureWidth);
    final path = row.path;
    final loading = _tree.loading.contains(path);
    final expanded = _tree.expanded.contains(path);
    final error = _tree.errors[path];
    final Widget glyph = loading
        ? const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        : Icon(
            expanded ? Icons.expand_more : Icons.chevron_right,
            size: 16,
            color: error != null ? c.error : c.textMuted,
          );
    Widget arrow = SizedBox(
      width: _disclosureWidth,
      height: double.infinity,
      child: InkWell(
        onTap: () {
          _focus.requestFocus();
          _ctrl.setTreeCursor(path);
          _ctrl.toggleExpand(path);
        },
        child: Center(child: glyph),
      ),
    );
    if (error != null) arrow = Tooltip(message: error, child: arrow);
    return arrow;
  }

  Widget _placeholder(TreeRow row, double indent, AircloneColors c) {
    final t = AircloneTheme.tokensOf(context);
    final isError = row.kind == TreeRowKind.error;
    return SizedBox(
      key: ValueKey(row.key),
      height: t.rowHeight,
      child: Padding(
        padding: EdgeInsets.only(
          left: Space.x3 + indent + _disclosureWidth + 22 + Space.x2,
          right: Space.x3,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            isError ? "Couldn't list this folder: ${row.message}" : 'Empty',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isError ? c.error : c.textFaint,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final widths = ref.watch(columnWidthsProvider);
    final state = widget.state;
    final selectionMode = isTouchPrimary && state.tree.selected.isNotEmpty;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, cons) {
          // Everything in a row that is not the Name column; indentation may
          // eat the name down to _minNameWidth and no further.
          final fixed =
              Space.x3 * 2 +
              _disclosureWidth +
              22 +
              Space.x2 * 3 +
              widths.size +
              widths.modified +
              28;
          final maxIndent = math.max(
            0.0,
            cons.maxWidth - fixed - _minNameWidth,
          );
          return ListView.builder(
            controller: widget.scrollController,
            physics: widget.physics,
            itemCount: widget.rows.length,
            itemBuilder: (_, i) {
              final row = widget.rows[i];
              final indent = math.min(row.depth * kTreeIndent, maxIndent);
              if (!row.isEntry) return _placeholder(row, indent, c);
              final path = row.path;
              return FileRow(
                key: ValueKey(row.key),
                file: row.file,
                selected: state.isTreeSelected(path),
                selectionMode: selectionMode,
                cursor: state.tree.cursor == path,
                dragData: _dragData(row),
                indent: indent,
                leading: _disclosure(row, c),
                tapOpensFolder: false,
                onOpen: () {
                  _focus.requestFocus();
                  _ctrl.setTreeCursor(path);
                  _ctrl.toggleExpand(path);
                },
                onToggle: () {
                  _focus.requestFocus();
                  _ctrl.toggleTreeSelect(path);
                },
                onPreview: () => widget.onPreview(row),
                onContextMenu: (pos) => widget.onContextMenu(row, pos),
                onDropInto: (data) => widget.onDropInto(row, data),
              );
            },
          );
        },
      ),
    );
  }
}
