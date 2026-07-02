import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';
import 'engine_controller.dart';

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
  remotes.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  // Android has no meaningful $HOME — and the phone shell already offers
  // "Internal storage", so the synthetic local peer would just be noise.
  if (!Platform.isAndroid) remotes.add(localHomeRemote());
  return remotes;
});

/// A synthetic peer pointing at the user's home directory via the rclone `local`
/// backend, so the file browser is demonstrable before any remote is configured.
Remote localHomeRemote() {
  final home = Platform.isWindows
      ? (Platform.environment['USERPROFILE'] ?? 'C:\\')
      : (Platform.environment['HOME'] ?? '/');
  final fs = '${home.replaceAll('\\', '/')}/';
  return Remote(name: 'This device', type: 'local', fs: fs, isLocal: true);
}
