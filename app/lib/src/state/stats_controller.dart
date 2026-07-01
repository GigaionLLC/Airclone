import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/transfer_item.dart';
import '../state/engine_controller.dart';

export '../rclone/models/transfer_item.dart' show TransferItem;

/// Aggregate engine transfer statistics (a snapshot of `core/stats`).
@immutable
class CoreStats {
  const CoreStats({
    this.speed = 0,
    this.bytes = 0,
    this.totalBytes = 0,
    this.transfers = 0,
    this.checks = 0,
    this.errors = 0,
    this.eta,
    this.elapsedTime = 0,
    this.transferring = const [],
  });

  final double speed;
  final int bytes;
  final int totalBytes;
  final int transfers;
  final int checks;
  final int errors;
  final double? eta;
  final double elapsedTime;
  final List<TransferItem> transferring;

  bool get isActive => transferring.isNotEmpty;

  static const empty = CoreStats();
}

/// Polls rclone `core/stats` once a second and exposes a parsed [CoreStats].
/// On any RPC/parse failure it keeps the last good snapshot.
class StatsController extends Notifier<CoreStats> {
  Timer? _timer;

  @override
  CoreStats build() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    ref.onDispose(() => _timer?.cancel());
    return CoreStats.empty;
  }

  Future<void> _poll() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      final res = await client.rpc('core/stats');
      state = _parse(res);
    } catch (_) {
      // Keep the last good snapshot on any error.
    }
  }

  CoreStats _parse(Map<String, dynamic> m) {
    final transferring = TransferItem.listFrom(m['transferring']);
    return CoreStats(
      speed: _double(m['speed']),
      bytes: _int(m['bytes']),
      totalBytes: _int(m['totalBytes']),
      transfers: _int(m['transfers']),
      checks: _int(m['checks']),
      errors: _int(m['errors']),
      eta: m['eta'] is num ? (m['eta'] as num).toDouble() : null,
      elapsedTime: _double(m['elapsedTime']),
      transferring: transferring,
    );
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;
  static double _double(Object? v) => v is num ? v.toDouble() : 0;
}

final statsProvider = NotifierProvider<StatsController, CoreStats>(
  StatsController.new,
);
