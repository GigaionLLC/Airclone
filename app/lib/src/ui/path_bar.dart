import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rclone/models/remote.dart';
import 'theme/tokens.dart';

/// An editable, Explorer-style address bar for a browser pane.
///
/// Two modes:
///  * **Breadcrumb** (default) — the remote name followed by each path segment,
///    separated by chevrons. Tapping the remote root calls [onSegment] with
///    `-1`; tapping segment `i` calls `onSegment(i)`. Clicking empty space (or
///    the edit affordance on the right) switches to edit mode.
///  * **Edit** — a full-width [TextField] prefilled with the in-remote [path]
///    (e.g. `Work/Q1`), with the remote name shown as a non-editable prefix.
///    Submitting (Enter) calls [onNavigate] with the typed value and exits edit
///    mode; pressing Esc or losing focus exits without navigating.
///
/// Self-contained: it owns the edit-mode flag and the [TextEditingController].
class PathBar extends StatefulWidget {
  const PathBar({
    super.key,
    required this.remote,
    required this.path,
    required this.onSegment,
    required this.onNavigate,
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
      child: _editing ? _buildEditor(c) : _buildBreadcrumb(c),
    );
  }

  // ── breadcrumb mode ────────────────────────────────────────────────────────

  Widget _buildBreadcrumb(AircloneColors c) {
    final segs = _segments;
    final disabled = widget.remote == null;

    // Empty-space click anywhere on the bar enters edit mode.
    return InkWell(
      onTap: disabled ? null : _startEditing,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: Space.x1),
              child: Row(
                children: [
                  _crumb(
                    c,
                    widget.remote?.name ?? '—',
                    disabled ? null : () => widget.onSegment(-1),
                    root: true,
                  ),
                  for (var i = 0; i < segs.length; i++) ...[
                    Icon(Icons.chevron_right, size: 15, color: c.textFaint),
                    _crumb(c, segs[i], () => widget.onSegment(i)),
                  ],
                ],
              ),
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
      ),
    );
  }

  Widget _crumb(
    AircloneColors c,
    String label,
    VoidCallback? onTap, {
    bool root = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x2,
          vertical: Space.x1,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: root ? c.text : c.textMuted,
            fontSize: 13,
            fontWeight: root ? FontWeight.w600 : FontWeight.w400,
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
