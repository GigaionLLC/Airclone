import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import 'preview_dialog.dart';
import 'theme/tokens.dart';

/// Opens an immersive Quick Look overlay over [entries] (a listing within
/// [parentPath] of [remote]), starting near [startIndex]. Only files are shown;
/// folders are skipped. Reuses [PreviewContent] for the body and adds keyboard
/// (Left/Right to move, Space/Esc to close) plus on-screen navigation.
///
/// Returns without showing anything when the listing has no files.
Future<void> showQuickLook(
  BuildContext context,
  Remote remote,
  String parentPath,
  List<RcloneFile> entries,
  int startIndex,
) {
  final files = entries.where((e) => !e.isDir).toList();
  if (files.isEmpty) return Future<void>.value();

  // Map the original entries index to the nearest files index: if the start
  // entry is a file, find it; otherwise pick the first file at/after it.
  var initial = 0;
  final clamped = startIndex.clamp(0, entries.length - 1);
  for (var i = clamped; i < entries.length; i++) {
    if (!entries[i].isDir) {
      initial = files.indexOf(entries[i]);
      break;
    }
  }
  if (initial < 0) initial = 0;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Quick Look',
    barrierColor: Colors.black.withValues(alpha: 0.82),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, _) => _QuickLook(
      remote: remote,
      parentPath: parentPath,
      files: files,
      initialIndex: initial,
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.96,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

/// The overlay body: a centered preview with header, framed [PreviewContent],
/// on-screen chevrons, and a keyboard hint.
class _QuickLook extends StatefulWidget {
  const _QuickLook({
    required this.remote,
    required this.parentPath,
    required this.files,
    required this.initialIndex,
  });

  final Remote remote;
  final String parentPath;
  final List<RcloneFile> files;
  final int initialIndex;

  @override
  State<_QuickLook> createState() => _QuickLookState();
}

class _QuickLookState extends State<_QuickLook> {
  late int _i = widget.initialIndex;

  void _go(int delta) {
    final next = (_i + delta).clamp(0, widget.files.length - 1);
    if (next != _i) setState(() => _i = next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.space) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final file = widget.files[_i];
    final many = widget.files.length > 1;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(Space.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    Text(
                      '${_i + 1} / ${widget.files.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: Space.x3),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(Radii.lg),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: PreviewContent(
                              key: ValueKey(file.path),
                              remote: widget.remote,
                              parentPath: widget.parentPath,
                              file: file,
                            ),
                          ),
                          if (many) ...[
                            Positioned(
                              left: Space.x3,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _NavButton(
                                  icon: Icons.chevron_left,
                                  onPressed: _i > 0 ? () => _go(-1) : null,
                                ),
                              ),
                            ),
                            Positioned(
                              right: Space.x3,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _NavButton(
                                  icon: Icons.chevron_right,
                                  onPressed: _i < widget.files.length - 1
                                      ? () => _go(1)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: Space.x2),
                  child: Text(
                    '< / >  ·  Space or Esc to close',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A large translucent-circle nav chevron; greyed out when [onPressed] is null.
class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.45 : 0.2),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, size: 34),
        color: Colors.white,
        disabledColor: Colors.white24,
        onPressed: onPressed,
      ),
    );
  }
}
