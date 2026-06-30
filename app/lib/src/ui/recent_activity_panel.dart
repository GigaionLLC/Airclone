import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/transferred_item.dart';
import '../state/recent_activity_controller.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// Read-only list of recently completed transfers (`core/transferred`), with a
/// success/error indicator per file. Fetch-on-open + manual refresh.
class RecentActivityPanel extends ConsumerWidget {
  const RecentActivityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final items = ref.watch(recentTransfersProvider);
    return Column(
      children: [
        SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.x3, right: Space.x1),
            child: Row(
              children: [
                Text(
                  'Recently completed',
                  style: TextStyle(color: c.textMuted, fontSize: 11),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => ref.invalidate(recentTransfersProvider),
                  icon: const Icon(Icons.refresh, size: 15),
                  color: c.textMuted,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: items.when(
            loading: () => const Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (e, _) => Center(
              child: Text(
                '$e',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
            ),
            data: (list) => list.isEmpty
                ? Center(
                    child: Text(
                      'No recent transfers',
                      style: TextStyle(color: c.textFaint, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => _row(c, list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _row(AircloneColors c, TransferredItem it) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 3),
    child: Row(
      children: [
        Icon(
          it.succeeded ? Icons.check_circle_outline : Icons.error_outline,
          size: 15,
          color: it.succeeded ? c.success : c.error,
        ),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                it.name,
                style: TextStyle(color: c.text, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (it.failed)
                Text(
                  it.error!,
                  style: TextStyle(color: c.error, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: Space.x2),
        Text(
          humanSize(it.size),
          style: TextStyle(color: c.textFaint, fontSize: 11),
        ),
      ],
    ),
  );
}
