import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'pane_drag.dart';

/// Wraps [child] so the WHOLE widget can be dragged. The drag carries the in-app
/// [PaneDragData] as `localData` (read back by [NativePaneDropRegion]) AND, for
/// local files, a real `Formats.fileUri` — so the SAME gesture can be dropped
/// in-app (copy into a folder/pane) OR onto the OS (Explorer/Finder/desktop) to
/// copy the file out.
///
/// Replaces Flutter's `Draggable`. Besides enabling OS drag-out, this fixes the
/// "list jumps to the top when you start dragging" behavior that Flutter's
/// `Draggable` exhibited inside the scrollable list.
class NativePaneDraggable extends StatelessWidget {
  const NativePaneDraggable({
    super.key,
    required this.data,
    required this.child,
  });

  final PaneDragData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      allowedOperations: () => const [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        final item = DragItem(
          localData: data.toJson(),
          suggestedName: data.files.length == 1 ? data.files.first.name : null,
        );
        // Plain text doubles as the in-app marker: it makes our DropRegions
        // engage, while OS-file drops (which carry no plain text) fall through
        // to the existing `desktop_drop` upload path.
        item.add(Formats.plainText(data.files.map((f) => f.name).join('\n')));
        // Local files also carry a real file URI, so the drag can drop OUT to
        // the OS as a copy. (v1 carries the first file; in-app drops still get
        // ALL files via localData.)
        if (data.remote.isLocal && data.files.isNotEmpty) {
          final f = data.files.first;
          final os = '${data.remote.fs}${joinPath(data.parentPath, f.name)}';
          final native = Platform.isWindows ? os.replaceAll('/', r'\') : os;
          item.add(
            Formats.fileUri(Uri.file(native, windows: Platform.isWindows)),
          );
        }
        return item;
      },
      child: DraggableWidget(child: child),
    );
  }
}

/// Wraps [child] as a drop target for in-app pane drags. Accepts ONLY drags that
/// carry [PaneDragData] in their `localData` — OS-file drops are ignored here
/// (no `localData`) so the existing `desktop_drop` upload handles them. Calls
/// [onDrop] with the reconstructed payload and highlights while a valid drag
/// hovers.
class NativePaneDropRegion extends StatefulWidget {
  const NativePaneDropRegion({
    super.key,
    required this.onDrop,
    required this.child,
    this.highlightColor,
    this.borderRadius,
  });

  final void Function(PaneDragData data) onDrop;
  final Widget child;
  final Color? highlightColor;
  final BorderRadius? borderRadius;

  @override
  State<NativePaneDropRegion> createState() => _NativePaneDropRegionState();
}

class _NativePaneDropRegionState extends State<NativePaneDropRegion> {
  bool _over = false;

  void _setOver(bool v) {
    if (_over != v && mounted) setState(() => _over = v);
  }

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [Formats.plainText],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        final items = event.session.items;
        final ok = items.isNotEmpty && items.first.localData is Map;
        return ok ? DropOperation.copy : DropOperation.none;
      },
      onDropEnter: (_) => _setOver(true),
      onDropLeave: (_) => _setOver(false),
      onPerformDrop: (event) async {
        _setOver(false);
        final items = event.session.items;
        if (items.isEmpty) return;
        final ld = items.first.localData;
        if (ld is Map) {
          widget.onDrop(PaneDragData.fromJson(Map<String, dynamic>.from(ld)));
        }
      },
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        (widget.highlightColor ??
                                Theme.of(context).colorScheme.primary)
                            .withValues(alpha: 0.12),
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
