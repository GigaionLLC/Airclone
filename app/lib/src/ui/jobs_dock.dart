import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/stats_controller.dart';
import 'jobs_panel.dart';
import 'recent_activity_panel.dart';
import 'stats_panel.dart';
import 'theme/tokens.dart';

/// The bottom dock: a "Transfers" tab (live stats + jobs) and a "Recent
/// activity" tab (completed-transfer history). Defaults to Transfers so the
/// Airclone default look is unchanged.
class JobsDock extends ConsumerStatefulWidget {
  const JobsDock({
    super.key,
    required this.atMaxHeight,
    required this.onToggleHeight,
  });

  /// Whether the dock is already as tall as the shell allows — the chevron
  /// flips to "put it back" rather than offering a no-op.
  final bool atMaxHeight;
  final VoidCallback onToggleHeight;

  @override
  ConsumerState<JobsDock> createState() => _JobsDockState();
}

class _JobsDockState extends ConsumerState<JobsDock> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 30,
          child: Row(
            children: [
              _tabButton(c, 0, 'Transfers'),
              _tabButton(c, 1, 'Recent activity'),
              const Spacer(),
              // Sized explicitly: the tab strip is 30px tall and an IconButton's
              // default 48px minimum would be squeezed by the parent rather than
              // fitting it.
              IconButton(
                onPressed: widget.onToggleHeight,
                icon: Icon(
                  widget.atMaxHeight
                      ? Icons.keyboard_double_arrow_down
                      : Icons.keyboard_double_arrow_up,
                  size: 16,
                ),
                color: c.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 26,
                ),
                tooltip: widget.atMaxHeight
                    ? 'Shrink the transfers dock'
                    : 'Expand the transfers dock',
              ),
              const SizedBox(width: Space.x1),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        Expanded(
          child: _tab == 0
              ? const TransfersTabBody()
              : const RecentActivityPanel(),
        ),
      ],
    );
  }

  Widget _tabButton(AircloneColors c, int index, String label) {
    final on = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? c.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? c.primary : c.textMuted,
            fontSize: 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// The Transfers surface: the live per-file strip over the job list.
///
/// Shared by the desktop dock and the phone/TV Transfers tab because both had
/// the same bug — the strip pinned in a HARD 100px box while the surface around
/// it grew. Making the dock taller (or opening the tab full-screen on a phone)
/// grew the job list underneath and left the files actually moving in the same
/// three-line slot, which is what "the transfers list is compacted and I
/// couldn't resize it" was.
class TransfersTabBody extends ConsumerWidget {
  const TransfersTabBody({super.key});

  /// Least height the strip can be given and still show its own header plus one
  /// file row. Below it the surface gives every pixel to the job list, which
  /// names the same files more compactly. A maximum the content cannot fit into
  /// is an overflow, not a small strip.
  static const double statsFloor = 72;

  /// However tall the surface is, the strip stops here — a full-screen phone
  /// tab would otherwise be all strip and no job list.
  static const double statsCap = 460;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, cons) {
      // Half the surface, less the padding around the strip.
      final statsMax = (cons.maxHeight * 0.5 - Space.x2 * 2).clamp(
        0.0,
        statsCap,
      );
      final showStats =
          statsMax >= statsFloor &&
          ref.watch(statsProvider.select((s) => s.isActive));
      return Column(
        children: [
          if (showStats)
            Padding(
              padding: const EdgeInsets.all(Space.x2),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: statsMax),
                child: const StatsPanel(),
              ),
            ),
          const Expanded(child: JobsPanel()),
        ],
      );
    },
  );
}
