import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import 'cloud_placeholder.dart';
import 'engine_controller.dart';
import 'host_platform.dart';

/// Names already present in the rclone config, or null when they cannot be read.
///
/// EVERY `config/create` caller must consult this first and fail closed.
/// `config/create` on a name that already exists silently REPLACES that remote:
/// exit 0, no warning, no diff, nothing in the response to distinguish it from
/// creating a new one. On a `crypt` remote that is data loss with no error --
/// the files stay where they are, but the new key cannot decrypt their names,
/// so rclone skips them and returns an empty listing and the pane renders
/// "Empty folder". A user hit exactly that; the config was the cause and
/// nothing in the app had warned them.
Future<Set<String>?> existingRemoteNames(RcloneClient client) async {
  try {
    final dump = await client.rpc('config/dump');
    return dump.keys.toSet();
  } catch (_) {
    return null; // unreadable -> callers must refuse, not assume "free"
  }
}

/// Loads the list of browsable locations: every configured rclone remote (from
/// `config/dump`) plus a synthetic local-disk peer.
final remotesProvider = FutureProvider<List<Remote>>((ref) async {
  final engine = ref.watch(engineControllerProvider);
  final client = engine.client;
  if (client == null) return const [];

  final dump = await client.rpc('config/dump');
  final remotes = <Remote>[];
  dump.forEach((name, cfg) {
    final type = (cfg is Map && cfg['type'] is String)
        ? cfg['type'] as String
        : 'unknown';
    remotes.add(Remote(name: name, type: type, fs: '$name:'));
  });
  // Resolve every wrapper remote (crypt/alias/...) to the local path it is
  // ultimately backed by, and hand the map to the placeholder guard. Without
  // this a crypt-over-Proton-Drive remote reports type "crypt", the guard sees
  // "not local", and reading its files silently hydrates them.
  // resolveBackingRoots owns which names are omitted; building this map inline
  // here published union/combine as present-with-null, which reads as a
  // definitive "not local" instead of "unknown".
  setRemoteBackingRoots(resolveBackingRoots(dump.cast<String, dynamic>()));
  remotes.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  // Android has no meaningful $HOME — and the phone shell already offers
  // "Internal storage", so the synthetic local peer would just be noise.
  if (!HostPlatform.isAndroid) remotes.add(localHomeRemote());
  return remotes;
});

/// A synthetic peer pointing at the user's home directory via the rclone `local`
/// backend, so the file browser is demonstrable before any remote is configured.
Remote localHomeRemote() {
  final home = HostPlatform.isWindows
      ? (HostPlatform.environment['USERPROFILE'] ?? 'C:\\')
      : (HostPlatform.environment['HOME'] ?? '/');
  final fs = '${home.replaceAll('\\', '/')}/';
  return Remote(name: 'This device', type: 'local', fs: fs, isLocal: true);
}
