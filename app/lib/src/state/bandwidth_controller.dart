import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_controller.dart';

@immutable
class BandwidthState {
  const BandwidthState({this.rate = 'off', this.loading = false});

  /// 'off' for unlimited, or an rclone rate like '10M'.
  final String rate;
  final bool loading;

  bool get isLimited => rate != 'off' && rate.isNotEmpty;

  BandwidthState copyWith({String? rate, bool? loading}) =>
      BandwidthState(rate: rate ?? this.rate, loading: loading ?? this.loading);
}

/// Live global bandwidth limit via `core/bwlimit`.
class BandwidthController extends Notifier<BandwidthState> {
  @override
  BandwidthState build() {
    _load();
    return const BandwidthState();
  }

  Future<void> _load() async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    try {
      final res = await client.rpc('core/bwlimit');
      final rate = (res['rate'] ?? 'off').toString();
      state = state.copyWith(rate: rate.isEmpty ? 'off' : rate);
    } catch (_) {
      /* engine not ready yet */
    }
  }

  Future<void> setLimit(String rate) async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) return;
    state = state.copyWith(loading: true);
    try {
      await client.rpc('core/bwlimit', {'rate': rate});
      state = BandwidthState(rate: rate);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }
}

final bandwidthControllerProvider =
    NotifierProvider<BandwidthController, BandwidthState>(
      BandwidthController.new,
    );
