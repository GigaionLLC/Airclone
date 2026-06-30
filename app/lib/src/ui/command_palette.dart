import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/tokens.dart';

/// One entry in the command palette. [run] is invoked AFTER the palette closes,
/// so actions that open their own dialog don't get dismissed with it.
class PaletteAction {
  const PaletteAction({
    required this.label,
    required this.icon,
    required this.run,
    this.hint,
    this.keywords = '',
  });

  final String label;
  final IconData icon;
  final VoidCallback run;

  /// Right-aligned hint (a shortcut like `Ctrl+T`, or a remote's type).
  final String? hint;

  /// Extra words folded into the search text but not shown.
  final String keywords;

  bool matches(List<String> tokens) {
    if (tokens.isEmpty) return true;
    final hay = '$label ${hint ?? ''} $keywords'.toLowerCase();
    return tokens.every(hay.contains);
  }
}

/// A Ctrl+K launcher: fuzzy-filter every app action + jump to any remote.
Future<void> showCommandPalette(
  BuildContext context,
  List<PaletteAction> actions,
) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.45),
  builder: (_) => _CommandPalette(actions: actions),
);

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.actions});
  final List<PaletteAction> actions;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  int _selected = 0;

  List<PaletteAction> get _filtered {
    final tokens = _controller.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    return widget.actions.where((a) => a.matches(tokens)).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final n = _filtered.length;
    if (n == 0) return;
    // Dart's % is non-negative for a positive divisor, so this wraps both ways.
    setState(() => _selected = (_selected + delta) % n);
    // Keep the highlighted row in view (rows are ~44px tall).
    if (_scroll.hasClients) {
      final target = (_selected * 44.0).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  void _runSelected() {
    final list = _filtered;
    if (list.isEmpty) return;
    final action = list[_selected.clamp(0, list.length - 1)];
    Navigator.of(context).pop();
    action.run();
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final list = _filtered;
    if (_selected >= list.length) {
      _selected = list.isEmpty ? 0 : list.length - 1;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
      },
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 560,
            constraints: const BoxConstraints(maxHeight: 440),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: c.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.x4,
                    Space.x3,
                    Space.x4,
                    Space.x2,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18, color: c.textFaint),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          onChanged: (_) => setState(() => _selected = 0),
                          onSubmitted: (_) => _runSelected(),
                          style: TextStyle(color: c.text, fontSize: 15),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Search actions and remotes…',
                            hintStyle: TextStyle(color: c.textFaint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                Flexible(
                  child: list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(Space.x5),
                          child: Text(
                            'No matches',
                            style: TextStyle(color: c.textFaint),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                            vertical: Space.x1,
                          ),
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (_, i) => _row(c, list[i], i),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(AircloneColors c, PaletteAction a, int i) {
    final active = i == _selected;
    return InkWell(
      onTap: () {
        setState(() => _selected = i);
        _runSelected();
      },
      onHover: (h) {
        if (h) setState(() => _selected = i);
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        color: active ? c.primary.withValues(alpha: 0.12) : Colors.transparent,
        child: Row(
          children: [
            Icon(a.icon, size: 18, color: active ? c.primary : c.textMuted),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Text(
                a.label,
                style: TextStyle(color: c.text, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (a.hint != null)
              Text(a.hint!, style: TextStyle(color: c.textFaint, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
