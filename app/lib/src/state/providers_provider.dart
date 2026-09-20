import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:airclone_rc/airclone_rc.dart';
import 'engine_controller.dart';

/// Backend types available from rclone (`config/providers`), cached once the engine
/// is ready. Powers the add-remote provider picker + dynamic forms.
final providersProvider = FutureProvider<List<RcloneProvider>>((ref) async {
  final client = ref.watch(engineControllerProvider).client;
  if (client == null) return const [];
  // Copied before sorting: the typed call returns a fixed-length list.
  final list = [...await RcApi(client).config.providers()]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
});
