import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import '../state/engine_controller.dart';
import '../state/open_external.dart';
import 'open_external_action.dart';
import 'popout_image_app.dart';
import 'popout_image_args.dart';
import 'preview_dialog.dart';
import 'theme/tokens.dart';

/// Opens an immersive Quick Look overlay over [entries] (a listing within
/// [parentPath] of [remote]), starting near [startIndex]. Only files are shown;
/// folders are skipped. Reuses [PreviewContent] for the body.
///
/// Two shapes, chosen by platform:
///
///  * **Desktop** — fills the window on a dimmed barrier, with chevrons and
///    keyboard navigation (Left/Right to move, Space/Esc to close). A thin
///    margin keeps it reading as an overlay ON the app. It was previously a
///    card capped at 1100px, which stayed the same small size however large the
///    window or monitor got.
///  * **Touch (Android/iOS)** — EDGE-TO-EDGE fullscreen on opaque black, system
///    bars hidden, swipe between items, tap to hide the chrome. This is what a
///    phone photo/video viewer is expected to look like; the desktop card
///    letterboxed inside a phone screen was the old behaviour.
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

  // Resolved HERE (not in the state) so the barrier can be fully opaque for the
  // fullscreen variant — a translucent barrier would show the browser through it.
  final fullscreen = switch (Theme.of(context).platform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: !fullscreen,
    barrierLabel: 'Quick Look',
    // Desktop is nearly opaque, not the old 0.82. Now that the overlay fills
    // the window its header sits directly over the app's own toolbar, and at
    // 0.82 those icons showed through and competed with the preview's controls.
    // Still short of full black so it reads as an overlay ON the app.
    barrierColor: fullscreen
        ? Colors.black
        : Colors.black.withValues(alpha: 0.94),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, _) => _QuickLook(
      remote: remote,
      parentPath: parentPath,
      files: files,
      initialIndex: initial,
      fullscreen: fullscreen,
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: fullscreen
          // No scale-in when it fills the screen — a growing fullscreen page
          // reads as a glitch rather than a transition.
          ? child
          : ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
    ),
  );
}

/// The overlay body. A [ConsumerStatefulWidget] so it can read the engine client
/// for the desktop "Pop out" action and for handing a file to another app.
class _QuickLook extends ConsumerStatefulWidget {
  const _QuickLook({
    required this.remote,
    required this.parentPath,
    required this.files,
    required this.initialIndex,
    required this.fullscreen,
  });

  final Remote remote;
  final String parentPath;
  final List<RcloneFile> files;
  final int initialIndex;

  /// Touch platforms: render edge-to-edge with the system bars hidden.
  final bool fullscreen;

  @override
  ConsumerState<_QuickLook> createState() => _QuickLookState();
}

class _QuickLookState extends ConsumerState<_QuickLook> {
  late int _i = widget.initialIndex;
  late final PageController _pager = PageController(
    initialPage: widget.initialIndex,
  );

  /// Fullscreen only: whether the top bar and hint are showing.
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    if (widget.fullscreen) {
      // Sticky so an accidental edge swipe doesn't leave the bars stuck on.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    if (widget.fullscreen) {
      // Back to the app's normal chrome. Must happen even if the route is
      // popped by the OS back gesture rather than our close button.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _pager.dispose();
    super.dispose();
  }

  /// Move by [delta] pages. The [PageView] owns touch swipes directly; this is
  /// the path for the keyboard arrows and the on-screen chevrons (desktop),
  /// animating so it feels the same as a swipe.
  void _go(int delta) {
    final next = (_i + delta).clamp(0, widget.files.length - 1);
    if (next != _i) {
      _pager.animateToPage(
        next,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
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

  /// Desktop only: open the current image in its own independently-resizable OS
  /// window via [openPopoutImageWindow]. The pop-out viewer renders images only,
  /// so we hand it just the image files (in order) as its sibling set for
  /// prev/next, remembering where the current file lands. The overlay stays open
  /// — pop-out is additive. Does nothing if the engine is down or no image
  /// resolves (the trigger is also hidden in those cases).
  void _popOut() {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    final current = widget.files[_i];
    final images = <PopoutImageEntry>[];
    var initial = 0;
    var auth = '';
    for (final f in widget.files) {
      if (!isImagePreview(f)) continue;
      final ObjectRef r;
      try {
        // f.path is the fs-relative path (same target PreviewContent resolves).
        r = client.objectRef(widget.remote.fs, f.path);
      } catch (_) {
        continue;
      }
      if (identical(f, current)) initial = images.length;
      auth = r.headers['Authorization'] ?? auth;
      images.add(PopoutImageEntry(url: r.url, name: f.name));
    }
    if (images.isEmpty) return;
    // Fire-and-forget: window creation is async but the UI need not await it.
    openPopoutImageWindow(
      PopoutImageArgs(authorization: auth, images: images, index: initial),
    );
  }

  Future<void> _openExternally(ExternalOpenMode mode) async {
    await openFileInAnotherApp(
      context,
      ref,
      widget.remote,
      widget.parentPath,
      widget.files[_i],
      mode: mode,
    );
  }

  /// Phone overflow: the actions that don't fit a slim top bar.
  Future<void> _showActions() async {
    final c = AircloneTheme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(Icons.open_in_new, color: c.textMuted),
              title: const Text('Open in another app'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openExternally(ExternalOpenMode.view);
              },
            ),
            ListTile(
              leading: Icon(Icons.ios_share, color: c.textMuted),
              title: const Text('Share…'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openExternally(ExternalOpenMode.share);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The swipeable page stack, shared by both shapes.
  Widget _pagerView() => PageView.builder(
    controller: _pager,
    itemCount: widget.files.length,
    onPageChanged: (p) => setState(() => _i = p),
    itemBuilder: (context, p) {
      final f = widget.files[p];
      return PreviewContent(
        key: ValueKey(f.path),
        remote: widget.remote,
        parentPath: widget.parentPath,
        file: f,
        // Fullscreen mattes photos on black like a phone gallery; the desktop
        // card keeps the themed sunken surface.
        imageBackground: widget.fullscreen ? Colors.black : null,
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return widget.fullscreen ? _buildFullscreen() : _buildWindowed(context);
  }

  // ── touch: edge-to-edge ────────────────────────────────────────────────────

  Widget _buildFullscreen() {
    final file = widget.files[_i];
    final many = widget.files.length > 1;
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tap toggles the chrome. As an ANCESTOR detector this only fires
          // where nothing deeper claims the tap, so the video controls keep
          // their own tap handling and pinch-zoom is untouched (that's a
          // scale gesture, not a tap).
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _chrome = !_chrome),
            child: _pagerView(),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: _TopBar(
                  name: file.name,
                  counter: many ? '${_i + 1} / ${widget.files.length}' : null,
                  onClose: () => Navigator.of(context).pop(),
                  onActions: canOpenExternally ? _showActions : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── pointer: fills the window ───────────────────────────────────────────────

  Widget _buildWindowed(BuildContext context) {
    final c = AircloneTheme.of(context);
    final file = widget.files[_i];
    final many = widget.files.length > 1;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      // Fills the window, like the phone's fullscreen shape. This used to be a
      // card capped at 1100px wide, which meant the preview stayed the same
      // small size no matter how big the window or monitor was — the bigger
      // your screen, the more of it went to dimmed background. A thin margin is
      // kept (rather than going truly edge-to-edge as on touch) so it still
      // reads as an overlay ON the app rather than a separate screen, and so
      // the rounded content area keeps its shape.
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
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
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (canOpenExternally)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: Colors.white),
                    tooltip: 'Open in another app',
                    onPressed: () => _openExternally(ExternalOpenMode.view),
                  ),
                // Desktop only, images only: pop the current image into its
                // own resizable OS window (the in-app overlay stays open).
                if (isPopoutSupportedOn(Theme.of(context).platform) &&
                    isImagePreview(file))
                  IconButton(
                    icon: const Icon(
                      Icons.picture_in_picture_alt,
                      color: Colors.white,
                    ),
                    tooltip: 'Pop out to a new window',
                    onPressed: _popOut,
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
                      Positioned.fill(child: _pagerView()),
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
    );
  }
}

/// Fullscreen chrome: a scrimmed row over the media with the name, position,
/// an overflow for the hand-off actions, and close.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.counter,
    required this.onClose,
    required this.onActions,
  });

  final String name;
  final String? counter;
  final VoidCallback onClose;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x2, Space.x1, Space.x2, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: 'Close',
                onPressed: onClose,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (counter != null)
                      Text(
                        counter!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (onActions != null)
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  tooltip: 'More',
                  onPressed: onActions,
                ),
            ],
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
