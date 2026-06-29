import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// A small grip that drags the LOCAL file at [osPath] OUT to the OS as a copy
/// (drop it onto Explorer/Finder/the desktop). It deliberately lives OUTSIDE the
/// in-app `Draggable` (as a sibling/overlay) so the native OS drag and the
/// in-app pane drag never fight over the same gesture.
///
/// When the drag gesture actually initiates it shows a brief SnackBar. That's a
/// deliberate diagnostic: because an OS drag can't be observed by an automated
/// test, the toast tells us whether the *gesture* fired (toast appears, so any
/// failure is on the OS-drop/data side) or never started (no toast → the gesture
/// is being swallowed, e.g. by a scroll view).
class OsDragHandle extends StatelessWidget {
  const OsDragHandle({
    super.key,
    required this.osPath,
    required this.fileName,
    required this.color,
  });

  final String osPath;
  final String fileName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // explorer/Finder want native separators; build a proper file:// URI.
    final native = Platform.isWindows ? osPath.replaceAll('/', r'\') : osPath;
    final uri = Uri.file(native, windows: Platform.isWindows);
    final messenger = ScaffoldMessenger.of(context);

    return DragItemWidget(
      allowedOperations: () => const [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Dragging "$fileName" out…'),
              duration: const Duration(milliseconds: 1000),
            ),
          );
        final item = DragItem(suggestedName: fileName);
        item.add(Formats.fileUri(uri));
        return item;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: DraggableWidget(
          child: Tooltip(
            message: 'Drag to copy out',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Icon(Icons.drag_indicator, size: 16, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
