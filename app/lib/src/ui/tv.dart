import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// Everything specific to running on a television.
///
/// It lives in one file on purpose: the TV affordances are then a single thing
/// to read and to audit against Google's TV quality requirements, rather than a
/// scatter of `if (tv)` branches across the shell.
///
/// The rule for this file: nothing here may run off a TV. Every caller gates on
/// `androidIsTelevision`, which is false on every other platform and on every
/// phone, so nothing below can regress a device that was already shipping.

/// Inset applied to the whole TV frame.
///
/// Televisions crop the edge of the picture ("overscan") by an amount an app
/// cannot query and that differs per set. Google's guidance is a 5% margin,
/// which at 1080p/xhdpi is 48dp across and 27dp down. Without it the wordmark
/// and the settings button sit hard against the bezel - the first TV capture
/// showed exactly that.
const EdgeInsets tvOverscan = EdgeInsets.symmetric(
  horizontal: 48,
  vertical: 27,
);

/// The tab bar, moved to the side for a remote.
///
/// A bottom bar is the wrong shape for a D-pad: reaching it means pressing DOWN
/// through every row of the file list first. From a side rail, one LEFT press
/// from anywhere in the list lands on it.
///
/// Hand-built rather than Material's NavigationRail because that widget draws
/// its own focus overlay and ignores ThemeData.focusColor. Focus traversed it
/// correctly and was INVISIBLE - screenshots before and after two D-pad presses
/// were byte-identical, while the press after them activated a different tab.
///
/// The focus RING comes from [TvFocusOverlay], which draws one for whatever
/// holds focus anywhere in the app; this only brightens its icon and label so a
/// focused item reads clearly inside the ring.
class TvNavRail extends StatelessWidget {
  const TvNavRail({super.key, required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  static const _items = <(IconData, IconData, String)>[
    (Icons.folder_outlined, Icons.folder, 'Files'),
    (Icons.swap_vert, Icons.swap_vert, 'Transfers'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        children: [
          for (var i = 0; i < _items.length; i++)
            _TvRailItem(
              icon: selected == i ? _items[i].$2 : _items[i].$1,
              label: _items[i].$3,
              selected: selected == i,
              onSelect: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _TvRailItem extends StatefulWidget {
  const _TvRailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_TvRailItem> createState() => _TvRailItemState();
}

class _TvRailItemState extends State<_TvRailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: widget.onSelect,
        onFocusChange: (f) => setState(() => _focused = f),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? c.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(
                widget.icon,
                size: 26,
                color: widget.selected || _focused ? c.primary : c.textMuted,
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.selected || _focused ? c.text : c.textMuted,
                  fontSize: 14,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Makes focus impossible to lose track of.
///
/// This is the single most important TV change and the one a review fails on:
/// with no pointer, the focus ring IS the cursor. Material's default focus
/// overlay is a ~10% wash designed to be noticed by someone already looking at
/// the button under their finger, which is far too quiet across a room.
///
/// Applied as a wrapper around the TV subtree rather than as an edit to the
/// app's ThemeData, so that no other platform's theme changes at all.
class TvFocusTheme extends StatelessWidget {
  const TvFocusTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The app's palette lives in AircloneTheme, not in colorScheme - reading the
    // latter gave the focus ring Material's default purple, which belongs to no
    // part of this app.
    final accent = AircloneTheme.of(context).primary;
    return Theme(
      data: theme.copyWith(
        // ListTile, InkWell and the rail all read their focus wash from here,
        // so this one value covers the whole subtree.
        focusColor: accent.withValues(alpha: 0.34),
      ),
      child: child,
    );
  }
}

/// Keeps focus from ever being nowhere.
///
/// Flutter moves focus by DIRECTIONAL traversal: an arrow key asks "what is
/// nearest, in this direction, to whatever holds focus now?". With nothing
/// focused there is no origin, so every arrow press is a no-op. That is not a
/// theory - a D-pad filmstrip caught it as seven consecutive byte-identical
/// frames, with dumpsys confirming the app window did hold key focus the whole
/// time. The keys arrive; there is simply nowhere for them to move from.
///
/// Touch and mouse never meet this, because the tap itself is the origin. A
/// remote has no equivalent, so something has to seed the first focus and
/// re-seed it whenever focus is lost - a dialog closing, a route popping, a
/// rebuild disposing the focused widget. On a TV "focus is nowhere" is a dead
/// end the user cannot escape, not a cosmetic glitch, so this re-checks on
/// every build rather than only once at startup.
class TvInitialFocus extends StatefulWidget {
  const TvInitialFocus({super.key, required this.child});

  final Widget child;

  @override
  State<TvInitialFocus> createState() => _TvInitialFocusState();
}

class _TvInitialFocusState extends State<TvInitialFocus> {
  // Owning the scope rather than looking one up with FocusScope.of(context):
  // the ambient scope at this point in the tree is the route's, whose
  // focusedChild can already be non-null for reasons that have nothing to do
  // with the file list - so the "is anything focused?" guard read as YES and
  // the seed never ran.
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'tv');

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Post-frame, because at build time the subtree to focus into does not
    // exist yet: the engine gate is still up on the first frames and there is
    // nothing focusable behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scope.focusedChild != null) return;
      _scope.nextFocus();
    });
    return FocusScope(node: _scope, child: widget.child);
  }
}

/// Draws the focus ring for the entire TV UI, once, from the outside.
///
/// Material widgets each decide their own focus appearance and several of the
/// ones this app is built from decline to show one: `NavigationRail` ignores
/// `ThemeData.focusColor` outright, and the file rows rendered nothing at all
/// while focus was demonstrably travelling through them - proven by pressing
/// the centre button after two arrow presses and watching a different tab
/// activate. Setting a theme colour and assuming looks identical to success.
///
/// Chasing it widget by widget re-opens the question on every screen added
/// later, so instead this tracks [FocusManager] and paints one ring over
/// whatever currently holds focus. Rows, buttons, dialogs and anything added
/// in future are covered without knowing this exists.
class TvFocusOverlay extends StatefulWidget {
  const TvFocusOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<TvFocusOverlay> createState() => _TvFocusOverlayState();
}

class _TvFocusOverlayState extends State<TvFocusOverlay> {
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_scheduleMeasure);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_scheduleMeasure);
    super.dispose();
  }

  // Post-frame: on a focus change the newly focused widget may not have been
  // laid out yet, and measuring it now would place the ring at its old size.
  void _scheduleMeasure() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

  void _measure() {
    if (!mounted) return;
    final focused = FocusManager.instance.primaryFocus?.context;
    final self = context.findRenderObject();
    Rect? next;
    if (focused != null && focused.mounted && self is RenderBox) {
      final box = focused.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        next = box.localToGlobal(Offset.zero, ancestor: self) & box.size;
      }
    }
    // A text field owns the keyboard while focused; ringing it would be noise
    // on top of its own caret and border.
    if (next != _rect) setState(() => _rect = next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AircloneTheme.of(context).primary;
    return NotificationListener<ScrollNotification>(
      // A list scrolling under a static ring leaves it pointing at the wrong
      // row, which is worse than no ring at all.
      onNotification: (_) {
        _scheduleMeasure();
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          if (_rect != null)
            Positioned.fromRect(
              rect: _rect!.inflate(3),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: accent, width: 3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
