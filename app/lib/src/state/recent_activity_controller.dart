import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/transferred_item.dart';
import 'engine_controller.dart';

/// Recently completed transfers (rclone keeps the last ~100, including
/// failures), fetched on demand via `core/transferred`. Read-only + historical,
/// so it's `autoDispose` (no permanent poller) — the panel refreshes by
/// invalidating this provider.
final recentTransfersProvider =
    FutureProvider.autoDispose<List<TransferredItem>>((ref) async {
      final client = ref.read(engineControllerProvider).client;
      if (client == null) return const [];
      final res = await client.rpc('core/transferred');
      return TransferredItem.listFromResponse(res);
    });
