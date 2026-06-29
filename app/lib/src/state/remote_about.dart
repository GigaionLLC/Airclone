import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_controller.dart';

/// Storage totals for a remote, from rclone `operations/about`. Any field may be
/// null when the backend doesn't report it (or doesn't support `about` at all).
@immutable
class RemoteAbout {
  const RemoteAbout({this.total, this.used, this.free});
  final int? total;
  final int? used;
  final int? free;
}

/// `operations/about` for a remote [fs], cached by Riverpod. Returns null when
/// the engine isn't ready or the backend doesn't support it.
final remoteAboutProvider = FutureProvider.family<RemoteAbout?, String>((
  ref,
  fs,
) async {
  final client = ref.read(engineControllerProvider).client;
  if (client == null) return null;
  try {
    final res = await client.rpc('operations/about', {'fs': fs});
    int? n(String k) => res[k] is num ? (res[k] as num).toInt() : null;
    return RemoteAbout(total: n('total'), used: n('used'), free: n('free'));
  } catch (_) {
    return null;
  }
});
