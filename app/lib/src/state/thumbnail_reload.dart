import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'thumbnail_service.dart';

/// A reload signal that mounted `ThumbnailImage`s listen to. Each [tick] bump
/// asks tiles to re-attempt; when [force] is set they also bypass (and
/// overwrite) the on-disk cache so a stale/corrupt thumbnail is regenerated.
///
/// This carries ONLY the reload epoch — not pre-warm progress — so tile
/// listeners are woken rarely (a per-completion progress counter here would fan
/// thousands of no-op notifications out across every tile).
@immutable
class ThumbnailReloadSignal {
  const ThumbnailReloadSignal({this.tick = 0, this.force = false});

  final int tick;
  final bool force;

  ThumbnailReloadSignal copyWith({int? tick, bool? force}) =>
      ThumbnailReloadSignal(tick: tick ?? this.tick, force: force ?? false);
}

/// Coordinates thumbnail reloads + whole-folder pre-warming across the app.
class ThumbnailReloadController extends Notifier<ThumbnailReloadSignal> {
  @override
  ThumbnailReloadSignal build() => const ThumbnailReloadSignal();

  /// Soft reload: mounted tiles that never resolved re-attempt; already-loaded
  /// (or disk-cached) tiles stay instant. This is the cheap "some didn't load"
  /// fix — it re-fetches only the placeholders.
  void reload() => state = state.copyWith(tick: state.tick + 1, force: false);

  /// Hard rebuild: every mounted tile re-fetches, bypassing + overwriting the
  /// cache. Use when a cached thumbnail is stale or wrong.
  void rebuild() => state = state.copyWith(tick: state.tick + 1, force: true);

  /// Warm the on-disk cache for [requests] (the whole folder, not just the
  /// viewport), then soft-reload so mounted placeholders display the new bytes.
  /// Real concurrency is bounded by the service; below-the-fold tiles land in
  /// the cache so scrolling to them is instant. Returns the number warmed.
  Future<int> prewarm(List<ThumbRequest> requests) async {
    if (requests.isEmpty) return 0;
    final service = ref.read(thumbnailServiceProvider);
    await Future.wait(requests.map((r) => service.load(r)));
    state = state.copyWith(tick: state.tick + 1, force: false);
    return requests.length;
  }
}

/// App-wide thumbnail reload / pre-warm coordinator.
final thumbnailReloadProvider =
    NotifierProvider<ThumbnailReloadController, ThumbnailReloadSignal>(
      ThumbnailReloadController.new,
    );
