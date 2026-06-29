import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/stats_controller.dart';
import 'theme/tokens.dart';

/// Live transfer-statistics strip backed by [statsProvider] (`core/stats`).
class StatsPanel extends ConsumerWidget {
  const StatsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final stats = ref.watch(statsProvider);

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      padding: const EdgeInsets.all(Space.x3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(stats: stats),
          if (stats.isActive) ...[
            const SizedBox(height: Space.x3),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: stats.transferring.length,
                separatorBuilder: (_, _) => const SizedBox(height: Space.x2),
                itemBuilder: (_, i) =>
                    _TransferRow(item: stats.transferring[i]),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x4),
              child: Center(
                child: Text(
                  'No active transfers',
                  style: TextStyle(color: c.textFaint, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.stats});

  final CoreStats stats;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Row(
      children: [
        Icon(Icons.swap_vert, size: 14, color: c.primary),
        const SizedBox(width: Space.x1),
        Text(
          _rate(stats.speed),
          style: TextStyle(
            color: c.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: Space.x3),
        Expanded(
          child: Text(
            '${_size(stats.bytes)} transferred  ·  '
            '${stats.transferring.length} active'
            '${stats.eta != null ? '  ·  ETA ${_eta(stats.eta!)}' : ''}',
            style: TextStyle(color: c.textMuted, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (stats.errors > 0)
          Text(
            '${stats.errors} err',
            style: TextStyle(
              color: c.error,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.name,
                style: TextStyle(color: c.text, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Space.x1),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.full),
                child: LinearProgressIndicator(
                  value: (item.percentage / 100).clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: c.surfaceSunken,
                  valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.x3),
        Text(
          _rate(item.speed),
          style: TextStyle(color: c.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

String _rate(double bytesPerSec) => '${_size(bytesPerSec.round())}/s';

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(1)} ${units[i]}';
}

String _eta(double seconds) {
  final s = seconds.round();
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
  return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
}
