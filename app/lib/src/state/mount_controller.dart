import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/mount_info.dart';
import '../rclone/rclone_client.dart';
import 'engine_controller.dart';
import 'mount_policy.dart';

/// The mount implementations the engine supports (`mount/types`). EMPTY on
/// Windows means WinFsp isn't installed — the UI then guides the user to it.
final mountTypesProvider = FutureProvider<List<String>>((ref) async {
  final client = ref.read(engineControllerProvider).client;
  if (client == null) return const [];
  try {
    final res = await client.rpc('mount/types');
    return (res['mountTypes'] as List?)?.whereType<String>().toList() ??
        const [];
  } catch (_) {
    return const [];
  }
});

/// Manages `rclone mount` instances (mount remotes as Windows drives/folders).
/// `mount/listmounts` is the source of truth (polled every 2s, mirroring
/// [ServeController]); nothing is persisted, so mounts never auto-resurrect.
class MountController extends Notifier<List<MountInfo>> {
  Timer? _timer;

  @override
  List<MountInfo> build() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    ref.onDispose(() => _timer?.cancel());
    return const [];
  }

  Future<void> _poll() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      final res = await client.rpc('mount/listmounts');
      final list = res['mountPoints'];
      state = list is List
          ? [for (final e in list) MountInfo.fromList(e)]
          : const [];
    } catch (_) {
      // keep last good snapshot
    }
  }

  /// Mounts [fs] at [mountPoint] (`*` = auto-assign a free drive letter). VFS
  /// cache mode defaults to writes (usable). Returns the actual mount point.
  /// Never sets a shared cache dir — rclone picks a per-mount one (no corruption).
  Future<String> mount({
    required String fs,
    required String mountPoint,
    String cacheMode = 'writes',
  }) async {
    if (!ref.read(mountEnabledProvider)) {
      throw RcloneException('mount/mount', 'Mounting is disabled by policy.');
    }
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      throw RcloneException('mount/mount', 'Engine not ready.');
    }
    final res = await client.rpc('mount/mount', {
      'fs': fs,
      'mountPoint': mountPoint,
      'vfsOpt': {'CacheMode': cacheModeValue(cacheMode)},
    });
    await _poll();
    return (res['mountPoint'] as String?) ?? mountPoint;
  }

  Future<void> unmount(String mountPoint) async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      await client.rpc('mount/unmount', {'mountPoint': mountPoint});
    } catch (_) {
      // may already be gone
    }
    await _poll();
  }

  Future<void> unmountAll() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      await client.rpc('mount/unmountall');
    } catch (_) {}
    await _poll();
  }
}

final mountControllerProvider =
    NotifierProvider<MountController, List<MountInfo>>(MountController.new);
