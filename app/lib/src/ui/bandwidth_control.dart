import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/bandwidth_controller.dart';
import '../state/bw_schedule.dart';
import '../state/bw_schedule_controller.dart';
import 'theme/tokens.dart';

const _presets = ['off', '256k', '512k', '1M', '5M', '10M', '50M', '100M'];

/// Top-bar control for the global bandwidth limit (`core/bwlimit`).
class BandwidthButton extends ConsumerWidget {
  const BandwidthButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final bw = ref.watch(bandwidthControllerProvider);
    final scheduled = ref.watch(
      bwScheduleControllerProvider.select((s) => s.enabled),
    );
    return PopupMenuButton<String>(
      tooltip: 'Bandwidth limit',
      onSelected: (v) {
        if (v == '__schedule__') {
          showBwScheduleDialog(context);
        } else {
          ref.read(bandwidthControllerProvider.notifier).setLimit(v);
        }
      },
      itemBuilder: (_) => [
        for (final p in ['off', '1M', '5M', '10M', '50M', '100M'])
          PopupMenuItem(
            value: p,
            child: Row(
              children: [
                Icon(
                  bw.rate == p ? Icons.check : Icons.speed_outlined,
                  size: 16,
                  color: bw.rate == p ? c.primary : c.textFaint,
                ),
                const SizedBox(width: Space.x2),
                Text(p == 'off' ? 'Unlimited' : '$p/s'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '__schedule__',
          child: Row(
            children: [
              Icon(
                Icons.schedule,
                size: 16,
                color: scheduled ? c.primary : c.textFaint,
              ),
              const SizedBox(width: Space.x2),
              Text(scheduled ? 'Schedule (on)…' : 'Schedule…'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x2,
          vertical: Space.x1,
        ),
        child: Row(
          children: [
            Icon(
              bw.isLimited ? Icons.speed : Icons.speed_outlined,
              size: 16,
              color: bw.isLimited ? c.warning : c.textMuted,
            ),
            const SizedBox(width: Space.x1),
            Text(
              bw.isLimited ? '${bw.rate}/s' : '∞',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor for the daily bandwidth timetable.
Future<void> showBwScheduleDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _BwScheduleDialog(),
);

class _BwScheduleDialog extends ConsumerWidget {
  const _BwScheduleDialog();

  String _hhmm(BwWindow w) =>
      '${w.hour.toString().padLeft(2, '0')}:${w.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final schedule = ref.watch(bwScheduleControllerProvider);
    final ctrl = ref.read(bwScheduleControllerProvider.notifier);
    final windows = [...schedule.windows]
      ..sort((a, b) => a.minutes.compareTo(b.minutes));

    void replace(List<BwWindow> w) => ctrl.setWindows(w);

    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: const Text('Bandwidth schedule'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Apply a daily bandwidth schedule'),
              value: schedule.enabled,
              onChanged: ctrl.setEnabled,
            ),
            const SizedBox(height: Space.x2),
            if (windows.isEmpty)
              Text(
                'No windows yet — add one (e.g. 08:00 → 512k, 18:00 → off).',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              )
            else
              for (var i = 0; i < windows.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        'From',
                        style: TextStyle(color: c.textMuted, fontSize: 12),
                      ),
                      const SizedBox(width: Space.x2),
                      OutlinedButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: windows[i].hour,
                              minute: windows[i].minute,
                            ),
                          );
                          if (t != null) {
                            final next = [...windows];
                            next[i] = windows[i].copyWith(
                              hour: t.hour,
                              minute: t.minute,
                            );
                            replace(next);
                          }
                        },
                        child: Text(_hhmm(windows[i])),
                      ),
                      const SizedBox(width: Space.x2),
                      DropdownButton<String>(
                        value: _presets.contains(windows[i].rate)
                            ? windows[i].rate
                            : 'off',
                        dropdownColor: c.surfaceRaised,
                        items: [
                          for (final p in _presets)
                            DropdownMenuItem(
                              value: p,
                              child: Text(p == 'off' ? 'Unlimited' : '$p/s'),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          final next = [...windows];
                          next[i] = windows[i].copyWith(rate: v);
                          replace(next);
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () => replace([...windows]..removeAt(i)),
                        icon: const Icon(Icons.close, size: 16),
                        color: c.textFaint,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: Space.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => replace([
                  ...windows,
                  const BwWindow(hour: 8, minute: 0, rate: '1M'),
                ]),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add window'),
              ),
            ),
            const SizedBox(height: Space.x2),
            Text(
              'Limits apply only while Airclone is open.',
              style: TextStyle(color: c.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
