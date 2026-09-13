import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../state/host_platform.dart';
import 'pane_drag.dart';
import 'touch.dart';

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
    // Phones don't drag between panes — and DraggableWidget's long-press drag
    // recognizer would swallow the long-press that opens the context menu.
    if (isTouchPrimary) return child;
    return DragItemWidget(
      allowedOperations: () => const [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        final item = DragItem(
          localData: data.toJson(),
          suggestedName: data.files.length == 1 ? data.files.first.name : null,
        );
        // Plain text doubles as the in-app marker: it makes our DropRegions
        // engage, while OS-file drops (which carry no plain text) are routed to
        // the OS-file branch instead.
        item.add(Formats.plainText(data.files.map((f) => f.name).join('\n')));
        // Local files also carry a real file URI, so the drag can drop OUT to
        // the OS as a copy. (v1 carries the first file; in-app drops still get
        // ALL files via localData.)
        if (data.remote.isLocal && data.files.isNotEmpty) {
          final f = data.files.first;
          final os = '${data.remote.fs}${joinPath(data.parentPath, f.name)}';
          final native = HostPlatform.isWindows ? os.replaceAll('/', r'\') : os;
          item.add(
            Formats.fileUri(Uri.file(native, windows: HostPlatform.isWindows)),
          );
        }
        return item;
      },
      child: DraggableWidget(child: child),
    );
  }
}

/// One dropped file delivered as BYTES rather than a filesystem path.
///
/// The path route is better wherever it exists - the host hands rclone a path
/// and nothing crosses the UI - but a browser never provides one, so the Web UI
/// needs this. [bytes] may be read ONCE, and only before the callback that
/// received this returns.
class DroppedBytes {
  const DroppedBytes({required this.name, required this.bytes, this.size});

  final String name;

  /// Byte length when the platform reports one; null is common and fine.
  final int? size;

  final Stream<List<int>> bytes;
}

/// Wraps [child] as a drop target. Handles two kinds of drops:
/// - **In-app** drags carrying [PaneDragData] in `localData` → [onDrop].
/// - **OS files** dragged in from Explorer/Finder → [onOsFiles] (their absolute
///   paths). Provide this only where uploads make sense (the pane / locations);
///   omit it and OS-file drops are ignored.
///
/// Since `super_native_extensions` owns native drops once any DropRegion exists,
/// OS-file drops are handled here rather than via a separate `desktop_drop`.
/// While an in-app drag hovers near the top/bottom edge, [scrollController] (if
/// given) auto-scrolls so you can reach off-screen folders — like Explorer.
class NativePaneDropRegion extends StatefulWidget {
  const NativePaneDropRegion({
    super.key,
    required this.child,
    this.onDrop,
    this.onOsFiles,
    this.onOsFileData,
    this.scrollController,
    this.highlightColor,
    this.borderRadius,
  });

  final void Function(PaneDragData data)? onDrop;
  final void Function(List<String> paths)? onOsFiles;
  final Future<void> Function(DroppedBytes file)? onOsFileData;
  final ScrollController? scrollController;
  final Widget child;
  final Color? highlightColor;
  final BorderRadius? borderRadius;

  @override
  State<NativePaneDropRegion> createState() => _NativePaneDropRegionState();
}

class _NativePaneDropRegionState extends State<NativePaneDropRegion> {
  bool _over = false;
  Timer? _autoScroll;
  double _dir = 0; // -1 up, +1 down, 0 idle

  static const _edge = 52.0; // px from an edge that triggers auto-scroll
  static const _step = 14.0; // px per ~60fps tick

  void _setOver(bool v) {
    if (_over != v && mounted) setState(() => _over = v);
  }

  void _updateAutoScroll(double localDy) {
    final sc = widget.scrollController;
    if (sc == null) return;
    final h = (context.findRenderObject() as RenderBox?)?.size.height;
    if (h == null) return;
    _dir = localDy < _edge ? -1 : (localDy > h - _edge ? 1 : 0);
    if (_dir == 0) {
      _stopAutoScroll();
    } else {
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!sc.hasClients || _dir == 0) return;
        final next = (sc.offset + _dir * _step).clamp(
          0.0,
          sc.position.maxScrollExtent,
        );
        if (next != sc.offset) sc.jumpTo(next);
      });
    }
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dir = 0;
  }

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  Future<List<String>> _readDroppedPaths(List<DropItem> items) async {
    final paths = <String>[];
    final waits = <Future<void>>[];
    for (final item in items) {
      final reader = item.dataReader;
      if (reader == null || !reader.canProvide(Formats.fileUri)) continue;
      final c = Completer<void>();
      reader.getValue<Uri>(Formats.fileUri, (uri) {
        if (uri != null) {
          try {
            paths.add(uri.toFilePath(windows: HostPlatform.isWindows));
          } catch (_) {
            /* not a file path; skip */
          }
        }
        c.complete();
      }, onError: (_) => c.complete());
      waits.add(c.future);
    }
    await Future.wait(waits);
    return paths;
  }

  /// Reads each dropped item as BYTES and hands it to [onOsFileData].
  ///
  /// Sequential, and awaited INSIDE the `onFile` callback, because the reader
  /// contract says the stream must be requested there and may be taken only
  /// once. Passing the stream outwards to consume later yields a closed one,
  /// which would look exactly like the silent failure this replaces.
  Future<void> _readDroppedData(List<DropItem> items) async {
    final sink = widget.onOsFileData;
    if (sink == null) return;
    for (final item in items) {
      final reader = item.dataReader;
      if (reader == null) continue;
      final done = Completer<void>();
      reader.getFile(
        null,
        (file) async {
          try {
            await sink(
              DroppedBytes(
                name:
                    file.fileName ?? await reader.getSuggestedName() ?? 'file',
                size: file.fileSize,
                bytes: file.getStream(),
              ),
            );
          } finally {
            if (!done.isCompleted) done.complete();
          }
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future;
    }
  }

  @override
  Widget build(BuildContext context) {
    // No drags can start on touch (see NativePaneDraggable), so the drop
    // machinery is dead weight there — skip it entirely.
    if (isTouchPrimary) return widget.child;
    return DropRegion(
      formats: widget.onOsFiles != null || widget.onOsFileData != null
          ? const [Formats.plainText, Formats.fileUri]
          : const [Formats.plainText],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        final items = event.session.items;
        final isInApp = items.isNotEmpty && items.first.localData is Map;
        if (isInApp) {
          if (widget.onDrop == null) return DropOperation.none;
          _updateAutoScroll(event.position.local.dy);
          return DropOperation.copy;
        }
        // OS files (no in-app localData): accept only where uploads happen.
        // BOTH routes count. Promising copy when only the PATH route exists is
        // what made a browser drop vanish: the badge said it would work, the
        // format was never provided, and nothing happened.
        return widget.onOsFiles != null || widget.onOsFileData != null
            ? DropOperation.copy
            : DropOperation.none;
      },
      onDropEnter: (_) => _setOver(true),
      onDropLeave: (_) {
        _setOver(false);
        _stopAutoScroll();
      },
      onPerformDrop: (event) async {
        _setOver(false);
        _stopAutoScroll();
        final items = event.session.items;
        if (items.isEmpty) return;
        final ld = items.first.localData;
        if (ld is Map) {
          widget.onDrop?.call(
            PaneDragData.fromJson(Map<String, dynamic>.from(ld)),
          );
          return;
        }
        // PATHS FIRST wherever they exist: the host then has rclone copy the
        // file itself and no bytes travel through the UI at all.
        if (widget.onOsFiles != null) {
          final paths = await _readDroppedPaths(items);
          if (paths.isNotEmpty) {
            widget.onOsFiles!(paths);
            return;
          }
        }
        // Nothing gave up a path. In a BROWSER nothing ever will - a page is
        // handed a File object and deliberately never the local path behind it -
        // so the Web UI reached exactly here on every drop and silently did
        // nothing, having already shown a copy badge. Read the bytes instead.
        await _readDroppedData(items);
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
