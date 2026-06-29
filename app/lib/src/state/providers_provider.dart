import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/provider.dart';
import 'engine_controller.dart';

/// Backend types available from rclone (`config/providers`), cached once the engine
/// is ready. Powers the add-remote provider picker + dynamic forms.
final providersProvider = FutureProvider<List<RcloneProvider>>((ref) async {
  final client = ref.watch(engineControllerProvider).client;
  if (client == null) return const [];
  final res = await client.rpc('config/providers');
  final list =
      (res['providers'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(RcloneProvider.fromJson)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
});
