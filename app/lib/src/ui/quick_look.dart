import 'checksum_dialog.dart';
import 'public_link_dialog.dart';
import 'file_op_dialogs.dart';
import '../state/file_ops.dart';
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
  int startIndex, {

  /// Called when something in here CHANGED the folder — a delete, today. The
  /// pane cannot see an edit made inside an overlay, and a pop result would be
  /// lost when the barrier is tapped, so this fires the moment it happens.
  VoidCallback? onChanged,
}) {
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
      onChanged: onChanged,
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
    this.onChanged,
  });

  final Remote remote;
  final String parentPath;
  final List<RcloneFile> files;
  final int initialIndex;

  /// Touch platforms: render edge-to-edge with the system bars hidden.
  final bool fullscreen;

  /// See showQuickLook.
  final VoidCallback? onChanged;

  @override
  ConsumerState<_QuickLook> createState() => _QuickLookState();
}

class _QuickLookState extends ConsumerState<_QuickLook> {
  late int _i = widget.initialIndex;

  /// The files still on screen. A copy of `_files`, because Quick Look can
  /// now DELETE one and the list has to shrink under the pager without closing
  /// the overlay — issue #4 asked for delete first, and deleting by leaving the
  /// preview to go and find the file in the list is the thing it was asking to
  /// avoid.
  late final List<RcloneFile> _files = [...widget.files];

  /// The file's path within its remote, which most operations want.
  String get _currentPath => widget.parentPath.isEmpty
      ? _files[_i].name
      : '${widget.parentPath}/${_files[_i].name}';

  /// A shareable link, for backends that can mint one.
  ///
  /// Offered from the preview because that is where somebody decides a file is
  /// the one they want to send — the alternative is closing the preview to find
  /// the same file in the list and right-click it.
  Future<void> _publicLink() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    await showPublicLinkDialog(
      context,
      client,
      fs: widget.remote.fs,
      remote: _currentPath,
      name: _files[_i].name,
    );
  }

  /// Checksums for the file on screen.
  ///
  /// Hash types are narrowed for a LOCAL remote for the reason the browser
  /// gives: a local file is hashed by READING it, and the unrestricted call
  /// computes about thirteen of them over the whole file.
  Future<void> _checksums() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    await showChecksumDialog(
      context,
      client,
      remoteInfo: widget.remote,
      fs: widget.remote.fs,
      remote: _currentPath,
      name: _files[_i].name,
      hashTypes: widget.remote.isLocal ? localHashTypes : null,
    );
  }

  /// Renames the file on screen, then keeps showing it under its new name.
  ///
  /// The rename dialog is given the CURRENT sibling names so it can refuse a
  /// collision before the engine does — the same set the file list passes, minus
  /// this file itself.
  ///
  /// The entry is replaced in place rather than the overlay closing: a rename is
  /// not a reason to lose your place in a folder you are working through.
  Future<void> _renameCurrent() async {
    final file = _files[_i];
    final name = await showRenameDialog(
      context,
      file.name,
      taken: {
        for (final f in _files)
          if (f.name != file.name) f.name,
      },
    );
    if (name == null || name == file.name || !mounted) return;
    final path = widget.parentPath.isEmpty
        ? file.name
        : '${widget.parentPath}/${file.name}';
    try {
      await ref.read(fileOpsProvider).rename(widget.remote, path, name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not rename ${file.name}.')));
      return;
    }
    if (!mounted) return;
    widget.onChanged?.call();
    setState(() {
      _files[_i] = RcloneFile(
        name: name,
        path: widget.parentPath.isEmpty ? name : '${widget.parentPath}/$name',
        isDir: file.isDir,
        size: file.size,
        mimeType: file.mimeType,
        modTime: file.modTime,
      );
    });
  }

  /// Copies the file's full `remote:path` to the clipboard — the string you
  /// paste into the console, a script, or a message to somebody else.
  Future<void> _copyPath() async {
    final file = _files[_i];
    final within = widget.parentPath.isEmpty
        ? file.name
        : '${widget.parentPath}/${file.name}';
    await Clipboard.setData(ClipboardData(text: '${widget.remote.fs}$within'));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Path copied.')));
  }

  /// Deletes the file on screen, after asking.
  ///
  /// Destructive, so it goes through the same [showDeleteConfirm] the browser
  /// uses rather than a bespoke prompt — one confirmation wording for the whole
  /// app, and rule 4 is not satisfied by an icon that looks dangerous.
  ///
  /// On success the overlay STAYS OPEN and moves to the next file, which is what
  /// makes this worth having: culling a folder of photos is one keystroke per
  /// file instead of preview, close, find, delete, reopen. It closes only when
  /// the last one is gone.
  Future<void> _deleteCurrent() async {
    final file = _files[_i];
    final ok = await showDeleteConfirm(context, file.name, isDir: file.isDir);
    if (!ok || !mounted) return;
    try {
      await ref
          .read(fileOpsProvider)
          .deleteEntry(widget.remote, file, widget.parentPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete ${file.name}.')));
      return;
    }
    if (!mounted) return;
    widget.onChanged?.call();
    setState(() {
      _files.removeAt(_i);
      // Step back only at the end of the list; otherwise the index already
      // points at what was the next file.
      if (_i >= _files.length) _i = _files.length - 1;
    });
    if (_files.isEmpty && mounted) Navigator.of(context).pop();
  }

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
    final next = (_i + delta).clamp(0, _files.length - 1);
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
    final current = _files[_i];
    final images = <PopoutImageEntry>[];
    var initial = 0;
    var auth = '';
    for (final f in _files) {
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
      _files[_i],
      mode: mode,
    );
  }

  /// Every operation the preview offers, in menu order.
  ///
  /// ONE list, rendered by both shapes — the phone's bottom sheet and the
  /// desktop overflow. It was not shared before, and the sheet only exists on a
  /// phone, so public link, checksums and copy path were unreachable on a
  /// desktop even though the code behind them was platform-neutral. An action
  /// added here now appears everywhere by construction.
  List<_PreviewAction> _actions() => [
    for (final a in previewActionsFor(
      canOpenExternally: canOpenExternally,
      touch: widget.fullscreen,
    ))
      _bind(a),
  ];

  /// Gives one [PreviewAction] its icon, label and handler.
  ///
  /// An exhaustive switch on purpose: adding a case to the enum then fails to
  /// compile until it is wired to something, which is the check that keeps
  /// [previewActionsFor] and the rendered menu from drifting apart.
  _PreviewAction _bind(PreviewAction a) => switch (a) {
    PreviewAction.openExternally => (
      icon: Icons.open_in_new,
      label: 'Open in another app',
      danger: false,
      run: () => _openExternally(ExternalOpenMode.view),
    ),
    PreviewAction.share => (
      icon: Icons.ios_share,
      label: 'Share…',
      danger: false,
      run: () => _openExternally(ExternalOpenMode.share),
    ),
    PreviewAction.publicLink => (
      icon: Icons.link_outlined,
      label: 'Public link',
      danger: false,
      run: _publicLink,
    ),
    PreviewAction.checksums => (
      icon: Icons.tag_outlined,
      label: 'Checksums',
      danger: false,
      run: _checksums,
    ),
    PreviewAction.rename => (
      icon: Icons.drive_file_rename_outline,
      label: 'Rename',
      danger: false,
      run: _renameCurrent,
    ),
    PreviewAction.copyPath => (
      icon: Icons.content_copy_outlined,
      label: 'Copy path',
      danger: false,
      run: _copyPath,
    ),
    PreviewAction.delete => (
      icon: Icons.delete_outline,
      label: 'Delete',
      danger: true,
      run: _deleteCurrent,
    ),
  };

  /// Touch overflow: the actions that don't fit a slim top bar.
  Future<void> _showActions() async {
    final c = AircloneTheme.of(context);
    final actions = _actions();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in actions) ...[
              if (a.danger) const Divider(height: 1),
              ListTile(
                leading: Icon(a.icon, color: a.danger ? c.error : c.textMuted),
                title: Text(
                  a.label,
                  style: a.danger ? TextStyle(color: c.error) : null,
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  a.run();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Pointer overflow: the same [_actions] as a menu under a `⋯` button.
  Widget _overflowButton(BuildContext context) {
    final c = AircloneTheme.of(context);
    final actions = _actions();
    return PopupMenuButton<int>(
      icon: const Icon(Icons.more_horiz, color: Colors.white),
      tooltip: 'More',
      // The toolbar sits on near-black, so the menu needs the app surface
      // rather than inheriting the overlay's palette.
      color: c.surface,
      onSelected: (i) => actions[i].run(),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++) ...[
          if (actions[i].danger) const PopupMenuDivider(),
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(
                  actions[i].icon,
                  size: 18,
                  color: actions[i].danger ? c.error : c.textMuted,
                ),
                const SizedBox(width: Space.x2),
                Text(
                  actions[i].label,
                  style: actions[i].danger ? TextStyle(color: c.error) : null,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The swipeable page stack, shared by both shapes.
  Widget _pagerView() => PageView.builder(
    controller: _pager,
    itemCount: _files.length,
    onPageChanged: (p) => setState(() => _i = p),
    itemBuilder: (context, p) {
      final f = _files[p];
      return PreviewContent(
        key: ValueKey(f.path),
        remote: widget.remote,
        parentPath: widget.parentPath,
        file: f,
        // Fullscreen mattes photos on black like a phone gallery; the desktop
        // card keeps the themed sunken surface.
        imageBackground: widget.fullscreen ? Colors.black : null,
        // Null at the ends, so the media players can disable rather than
        // pretend. A swipe and the arrow keys already move the pager; these
        // exist for a device that has neither, which is a television remote.
        onPrevious: p > 0 ? () => _go(-1) : null,
        onNext: p < _files.length - 1 ? () => _go(1) : null,
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return widget.fullscreen ? _buildFullscreen() : _buildWindowed(context);
  }

  // ── touch: edge-to-edge ────────────────────────────────────────────────────

  Widget _buildFullscreen() {
    final file = _files[_i];
    final many = _files.length > 1;
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
                  counter: many ? '${_i + 1} / ${_files.length}' : null,
                  onClose: () => Navigator.of(context).pop(),
                  onActions: _showActions,
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
    final file = _files[_i];
    final many = _files.length > 1;

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
                  '${_i + 1} / ${_files.length}',
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
                _overflowButton(context),
                IconButton(
                  icon: const Icon(
                    Icons.drive_file_rename_outline,
                    color: Colors.white,
                  ),
                  tooltip: 'Rename',
                  onPressed: _renameCurrent,
                ),
                // Issue #4: delete without leaving the preview. Placed BEFORE
                // Close and separated from it, because the two sit next to
                // each other and only one of them is undoable.
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Delete',
                  onPressed: _deleteCurrent,
                ),
                const SizedBox(width: Space.x2),
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
                              onPressed: _i < _files.length - 1
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

/// Everything the preview can do to the file on screen, in menu order.
///
/// An enum, and a pure function to select from it, so the SET of offered
/// actions can be asserted without standing up an overlay, an engine and a
/// remote. That is worth the indirection because the set is exactly what went
/// wrong: the menu used to be shown only where files can be handed to another
/// app, so on iOS — which has no such route — the whole menu vanished, taking
/// delete and rename with it.
enum PreviewAction {
  openExternally,
  share,
  publicLink,
  checksums,
  rename,
  copyPath,

  /// Always last: destructive, and rendered apart from the rest in both shapes.
  delete,
}

/// The actions to offer, given what the platform can do.
///
/// [canOpenExternally] is whether files can be handed to another app at all;
/// [touch] is the edge-to-edge phone shape. Neither may gate anything but the
/// two entries that genuinely depend on it.
@visibleForTesting
List<PreviewAction> previewActionsFor({
  required bool canOpenExternally,
  required bool touch,
}) => [
  if (canOpenExternally) PreviewAction.openExternally,
  // Touch only: desktop has no share sheet, and [ExternalOpenMode.share]
  // degrades there to a plain open — an entry that quietly does something else
  // is worse than no entry.
  if (canOpenExternally && touch) PreviewAction.share,
  // canPublicLink is not consulted: the dialog itself reports a backend that
  // cannot mint one, and hiding the entry would leave a user wondering whether
  // Airclone or their provider lacks the feature.
  PreviewAction.publicLink,
  PreviewAction.checksums,
  PreviewAction.rename,
  PreviewAction.copyPath,
  PreviewAction.delete,
];

/// One entry in the preview's action menu, rendered by both shapes.
typedef _PreviewAction = ({
  IconData icon,
  String label,

  /// Destructive: shown in the error colour and separated from everything else.
  bool danger,
  VoidCallback run,
});

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
