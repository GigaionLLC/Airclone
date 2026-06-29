import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/bandwidth_controller.dart';
import 'theme/tokens.dart';

const _presets = ['off', '1M', '5M', '10M', '50M', '100M'];

/// Top-bar control for the global bandwidth limit (`core/bwlimit`).
class BandwidthButton extends ConsumerWidget {
  const BandwidthButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final bw = ref.watch(bandwidthControllerProvider);
    return PopupMenuButton<String>(
      tooltip: 'Bandwidth limit',
      onSelected: (v) =>
          ref.read(bandwidthControllerProvider.notifier).setLimit(v),
      itemBuilder: (_) => [
        for (final p in _presets)
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
