import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rclone/models/remote.dart';
import 'theme/tokens.dart';

/// An editable, Explorer-style address bar for a browser pane.
///
/// It "morphs" between two modes like a native file-manager address bar:
///  * **Breadcrumb** (default) — a leading remote chip (icon + name) followed by
///    each path segment, separated by chevrons. Tapping the remote chip calls
///    [onSegment] with `-1`; tapping segment `i` calls `onSegment(i)`. Hovering a
///    crumb highlights it. When the trail is wider than the available width the
///    middle collapses into a `…` overflow affordance (a menu listing the hidden
///    segments) while keeping the remote root and the last couple of segments.
///    Clicking the empty space to the right (or the edit affordance) switches to
///    edit mode.
///  * **Edit** — a full-width [TextField] prefilled with the in-remote [path]
///    (e.g. `Work/Q1`), with the remote name shown as a non-editable prefix.
///    Submitting (Enter) calls [onNavigate] with the typed value and exits edit
///    mode; pressing Esc or losing focus exits without navigating. The field
///    autofocuses with its contents selected.
///
/// Self-contained: it owns the edit-mode flag and the [TextEditingController].
class PathBar extends StatefulWidget {
  const PathBar({
    super.key,
    required this.remote,
    required this.path,
    required this.onSegment,
    required this.onNavigate,
    this.editRequestTick = 0,
  });

  /// The remote whose name anchors the breadcrumb (`null` -> placeholder root).
  final Remote? remote;

  /// The current path within the remote (slash-separated, e.g. `Work/Q1`).
  final String path;

  /// Called when a breadcrumb segment is tapped. `segmentIndex == -1` is the
  /// remote root; `0..n-1` index into the path segments.
  final void Function(int segmentIndex) onSegment;

  /// Called when the user submits an edited path (the in-remote path string).
  final void Function(String newPath) onNavigate;

  /// External "start editing" trigger: whenever this value CHANGES the bar
  /// pops into edit mode (Ctrl+L / Alt+D route through a per-pane counter).
  final int editRequestTick;

  @override
  State<PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<PathBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    // Exiting edit mode whenever focus is lost (e.g. clicking elsewhere).
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the pane navigates underneath us, drop out of any stale edit session.
    if (oldWidget.path != widget.path || oldWidget.remote != widget.remote) {
      if (_editing) _stopEditing();
    }
    // Keyboard "focus the address bar" (Ctrl+L / Alt+D).
    if (widget.editRequestTick != oldWidget.editRequestTick && !_editing) {
      _startEditing();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _editing) _stopEditing();
  }

  /// Split [path] into non-empty segments.
  List<String> get _segments =>
      widget.path.split('/').where((s) => s.isNotEmpty).toList();

  void _startEditing() {
    if (widget.remote == null) return;
    _controller.text = widget.path;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
    // Focus on the next frame so the field is mounted first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focusNode.requestFocus();
    });
  }

  void _stopEditing() {
    if (!_editing) return;
    setState(() => _editing = false);
  }

  void _submit(String value) {
    // Normalise: trim, unify slashes, strip leading/trailing/duplicate slashes.
    final normalized = value
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .join('/');
    _stopEditing();
    widget.onNavigate(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: _editing ? _buildEditor(c) : _buildBreadcrumb(c),
    );
  }

  // ── breadcrumb mode ────────────────────────────────────────────────────────

  Widget _buildBreadcrumb(AircloneColors c) {
    final segs = _segments;
    final disabled = widget.remote == null;
    final rootLabel = widget.remote?.name ?? '—';
    final rootIcon = widget.remote == null
        ? Icons.cloud_off_outlined
        : (widget.remote!.isLocal
              ? Icons.computer_outlined
              : Icons.cloud_outlined);

    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final plan = _planCrumbs(
                c,
                rootLabel: rootLabel,
                segments: segs,
                maxWidth: constraints.maxWidth,
              );
              // The empty area to the right of the trail enters edit mode; the
              // trail itself is left-aligned and never scrolls.
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: disabled ? null : _startEditing,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _crumb(
                          c,
                          rootLabel,
                          disabled ? null : () => widget.onSegment(-1),
                          icon: rootIcon,
                          root: true,
                        ),
                        if (plan.overflow.isNotEmpty) ...[
                          _chevron(c),
                          _overflowCrumb(c, plan.overflow),
                        ],
                        for (final i in plan.tail) ...[
                          _chevron(c),
                          _crumb(c, segs[i], () => widget.onSegment(i)),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Edit affordance — also enters edit mode.
        IconButton(
          onPressed: disabled ? null : _startEditing,
          icon: const Icon(Icons.edit_outlined, size: 14),
          tooltip: 'Edit path',
          color: c.textFaint,
          splashRadius: 16,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// Decides which trailing segments stay visible and which collapse into the
  /// overflow menu, given the available [maxWidth]. The remote root is always
  /// shown; the last segment is always shown; earlier ones are kept until the
  /// trail no longer fits, then folded into a `…` affordance.
  _CrumbPlan _planCrumbs(
    AircloneColors c, {
    required String rootLabel,
    required List<String> segments,
    required double maxWidth,
  }) {
    if (segments.isEmpty) return const _CrumbPlan([], []);

    // Width of the always-present root chip and a chevron separator.
    final rootW = _crumbWidth(rootLabel, root: true, hasIcon: true);
    final chevronW = _chevronWidth;
    final overflowW = _crumbWidth('…');

    // Measure each segment crumb (label + its leading chevron).
    final segW = [for (final s in segments) _crumbWidth(s) + chevronW];

    // Try to show every segment first.
    var total = rootW;
    for (final w in segW) {
      total += w;
    }
    if (total <= maxWidth) {
      return _CrumbPlan(const [], [
        for (var i = 0; i < segments.length; i++) i,
      ]);
    }

    // Otherwise keep the LAST segment, then greedily add earlier ones from the
    // right while they fit, leaving room for the `…` overflow chip.
    final budget = maxWidth - rootW - chevronW - overflowW;
    final tail = <int>[];
    var used = 0.0;
    for (var i = segments.length - 1; i >= 0; i--) {
      final w = segW[i];
      if (tail.isEmpty || used + w <= budget) {
        tail.insert(0, i);
        used += w;
      } else {
        break;
      }
    }
    final overflow = [for (var i = 0; i < (tail.first); i++) i];
    return _CrumbPlan(overflow, tail);
  }

  // ── measurement helpers ─────────────────────────────────────────────────────

  static const _segFontSize = 13.0;
  static const _crumbHPad = Space.x2; // each side
  static const _iconSlot = 17.0; // icon (13) + gap (4)

  double _crumbWidth(String label, {bool root = false, bool hasIcon = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: _segFontSize,
          fontWeight: root ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width + _crumbHPad * 2 + (hasIcon ? _iconSlot : 0);
  }

  double get _chevronWidth => 15; // Icon size used for the chevron separator.

  // ── breadcrumb pieces ───────────────────────────────────────────────────────

  Widget _chevron(AircloneColors c) =>
      Icon(Icons.chevron_right, size: 15, color: c.textFaint);

  Widget _crumb(
    AircloneColors c,
    String label,
    VoidCallback? onTap, {
    IconData? icon,
    bool root = false,
  }) {
    return _HoverCrumb(
      colors: c,
      onTap: onTap,
      builder: (hovered) => Container(
        decoration: BoxDecoration(
          color: hovered && onTap != null
              ? c.primary.withValues(alpha: 0.10)
              : null,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: _crumbHPad,
          vertical: Space.x1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: root ? c.primary : c.textMuted),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                color: root ? c.text : c.textMuted,
                fontSize: _segFontSize,
                fontWeight: root ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The `…` chip whose menu lists the hidden middle segments; selecting one
  /// navigates to that depth via [onSegment].
  Widget _overflowCrumb(AircloneColors c, List<int> hidden) {
    final segs = _segments;
    return MenuAnchor(
      menuChildren: [
        for (final i in hidden)
          MenuItemButton(
            leadingIcon: Icon(
              Icons.subdirectory_arrow_right,
              size: 14,
              color: c.textFaint,
            ),
            onPressed: () => widget.onSegment(i),
            child: Text(segs[i]),
          ),
      ],
      builder: (context, controller, _) => _HoverCrumb(
        colors: c,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        builder: (hovered) => Container(
          decoration: BoxDecoration(
            color: hovered ? c.primary.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: _crumbHPad,
            vertical: Space.x1,
          ),
          child: Text(
            '…',
            style: TextStyle(
              color: c.textMuted,
              fontSize: _segFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ── edit mode ──────────────────────────────────────────────────────────────

  Widget _buildEditor(AircloneColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x1),
      child: Row(
        children: [
          // Non-editable remote prefix.
          Padding(
            padding: const EdgeInsets.only(left: Space.x1, right: Space.x1),
            child: Text(
              '${widget.remote?.name ?? '—'}/',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _stopEditing();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                style: TextStyle(color: c.text, fontSize: 13),
                cursorColor: c.primary,
                textInputAction: TextInputAction.go,
                onSubmitted: _submit,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: Space.x2,
                  ),
                  hintText: 'Type a path…',
                  hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _submit(_controller.text),
            icon: const Icon(Icons.subdirectory_arrow_left, size: 14),
            tooltip: 'Go',
            color: c.primary,
            splashRadius: 16,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// The outcome of laying out the breadcrumb trail for a given width.
///
/// [overflow] holds the indices of the hidden middle segments (folded into the
/// `…` chip); [tail] holds the indices of the segments shown after it. The
/// remote root is always rendered separately and is not part of either list.
@immutable
class _CrumbPlan {
  const _CrumbPlan(this.overflow, this.tail);
  final List<int> overflow;
  final List<int> tail;
}

/// A crumb wrapper that tracks pointer hover so the active segment can be
/// highlighted, and forwards taps. Shows a click cursor when interactive.
class _HoverCrumb extends StatefulWidget {
  const _HoverCrumb({
    required this.colors,
    required this.onTap,
    required this.builder,
  });

  final AircloneColors colors;
  final VoidCallback? onTap;
  final Widget Function(bool hovered) builder;

  @override
  State<_HoverCrumb> createState() => _HoverCrumbState();
}

class _HoverCrumbState extends State<_HoverCrumb> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: interactive ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(_hovered),
      ),
    );
  }
}
