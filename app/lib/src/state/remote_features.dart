import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_controller.dart';

/// rclone backend capabilities for a remote (from `operations/fsinfo`'s
/// `Features` map) — e.g. `PublicLink`, `About`, `CanHaveEmptyDirectories`.
/// Cached per fs; used to capability-gate UI (a local backend has no public links).
final remoteFeaturesProvider = FutureProvider.family<Map<String, bool>, String>(
  (ref, fs) async {
    final client = ref.watch(engineControllerProvider).client;
    if (client == null) return const {};
    try {
      final res = await client.rpc('operations/fsinfo', {'fs': fs});
      final feats =
          (res['Features'] as Map?)?.cast<String, dynamic>() ?? const {};
      return {for (final e in feats.entries) e.key: e.value == true};
    } catch (_) {
      return const {};
    }
  },
);
