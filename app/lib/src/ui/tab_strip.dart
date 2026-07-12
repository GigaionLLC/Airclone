import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/advanced_mode.dart';
import '../state/browser_controller.dart';
import 'theme/tokens.dart';

/// The per-pane tab strip, shared by the desktop pane header and the phone
/// browser. Each chip switches tabs; its ✕ closes it (hidden when only one tab
/// is left, since the last tab can't be closed); the trailing + opens a new
/// tab. All state comes from `paneProvider(index)` so it is dual-pane-safe.
///
/// [touch] enlarges the tap targets (height, close ✕, +) for phone use; the
/// default reproduces the desktop strip exactly.
class PaneTabStrip extends ConsumerWidget {
  const PaneTabStrip({super.key, required this.index, this.touch = false});
  final int index;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(paneProvider(index));
    final ctrl = ref.read(paneProvider(index).notifier);
    final tabs = state.tabs;
    // The last remaining tab can't be closed (controller no-ops) — hide its ✕
    // so it doesn't read as a dead control on the phone's always-on strip.
    final canClose = tabs.length > 1;
    final height = touch ? 40.0 : 30.0;
    final closeSize = touch ? 18.0 : 13.0;
    final addSize = touch ? 20.0 : 15.0;

    return Container(
      height: height,
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: Space.x1),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (_, i) {
                final on = i == state.activeTab;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: touch ? 5 : 3,
                    horizontal: 1,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    onTap: () => ctrl.switchTab(i),
                    child: Container(
                      constraints: BoxConstraints(maxWidth: touch ? 180 : 168),
                      padding: EdgeInsets.only(
                        left: Space.x2,
                        right: canClose ? 2 : Space.x2,
                      ),
                      decoration: BoxDecoration(
                        color: on ? c.surfaceRaised : c.surfaceSunken,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(
                          color: on ? c.border : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (tabs[i].kind == PaneKind.console) ...[
                            Icon(
                              Icons.terminal,
                              size: touch ? 14 : 12,
                              color: on ? c.text : c.textMuted,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              tabs[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: on ? c.text : c.textMuted,
                                fontSize: touch ? 13 : 12,
                                fontWeight: on
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (canClose) ...[
                            const SizedBox(width: 2),
                            InkWell(
                              borderRadius: BorderRadius.circular(Radii.full),
                              onTap: () => ctrl.closeTab(i),
                              child: Padding(
                                padding: EdgeInsets.all(touch ? 4 : 0),
                                child: Icon(
                                  Icons.close,
                                  size: closeSize,
                                  color: c.textFaint,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            onPressed: ctrl.newTab,
            icon: Icon(Icons.add, size: addSize),
            tooltip: 'New tab (Ctrl+T)',
            visualDensity: VisualDensity.compact,
          ),
          // Advanced, desktop-only: open the rclone command console in a new tab.
          if (_consoleAvailable(ref))
            IconButton(
              onPressed: ctrl.newConsoleTab,
              icon: Icon(Icons.terminal, size: addSize),
              tooltip: 'New console tab',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  // The console runs on every engine — streaming `core/command` on the spawned
  // binary (desktop + Android), the RC-method path on the in-process/FFI engine
  // (iOS/MAS). So it's available anywhere Advanced mode is on, not desktop-only.
  static bool _consoleAvailable(WidgetRef ref) =>
      ref.watch(advancedModeProvider);
}
