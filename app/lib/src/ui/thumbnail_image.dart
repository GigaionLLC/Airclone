import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/thumbnail_reload.dart';
import '../state/thumbnail_service.dart';
import 'theme/tokens.dart';

/// Lazy thumbnail tile: shows [placeholder] until bytes resolve, then fades
/// in the decoded image. Loads only when mounted (visible-window-only), so
/// scrolling a tile into view triggers its fetch.
///
/// A single fetch can fail transiently — the object server may still be warming
/// up, the backend may be cold, or the engine may be mid-restart while the user
/// navigates. So the load **retries with backoff** instead of sticking on the
/// placeholder forever, and re-runs when the app broadcasts a
/// [thumbnailReloadProvider] reload (the "Reload / Rebuild thumbnails" actions).
class ThumbnailImage extends ConsumerStatefulWidget {
  const ThumbnailImage({
    super.key,
    required this.request,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  final ThumbRequest request;
  final Widget placeholder;
  final BoxFit fit;

  @override
  ConsumerState<ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends ConsumerState<ThumbnailImage> {
  /// Backoff between attempts; the last delay repeats if attempts exceed it.
  static const List<Duration> _backoff = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
    Duration(seconds: 3),
  ];
  static const int _maxAttempts = 4;

  Uint8List? _bytes;
  int _reloadTick = 0;

  /// Bumped on every [_start]; an in-flight attempt whose token is stale (a
  /// reload fired, or the tile was recycled onto a different file) bails instead
  /// of writing the wrong bytes.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _reloadTick = ref.read(thumbnailReloadProvider).tick;
    _start();
  }

  @override
  void didUpdateWidget(ThumbnailImage old) {
    super.didUpdateWidget(old);
    // A recycled tile (grid/gallery reuse) or a post-refresh mod-time change
    // gives this element a different object — drop the stale bytes and refetch.
    if (old.request.cacheKey != widget.request.cacheKey) {
      _bytes = null;
      _start();
    }
  }

  /// Fetch (with bounded retry) and, on success, fade the image in. [force]
  /// bypasses the on-disk cache for a hard rebuild. Each call supersedes any
  /// earlier in-flight attempt via [_gen].
  Future<void> _start({bool force = false}) async {
    final gen = ++_gen;
    final req = widget.request;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      Uint8List? bytes;
      try {
        bytes = await ref
            .read(thumbnailServiceProvider)
            .load(req, force: force);
      } catch (_) {
        bytes = null;
      }
      // Superseded (a newer _start ran) or gone — discard this result.
      if (!mounted || gen != _gen) return;
      if (bytes != null) {
        setState(() => _bytes = bytes);
        return;
      }
      // Transient miss — wait, then retry (unless this was the last attempt).
      if (attempt < _maxAttempts - 1) {
        final i = attempt < _backoff.length ? attempt : _backoff.length - 1;
        await Future<void>.delayed(_backoff[i]);
        if (!mounted || gen != _gen) return;
      }
    }
    // Exhausted: keep the placeholder. A manual reload can re-arm the fetch.
  }

  /// React to an app-wide reload/rebuild broadcast.
  void _onReload(ThumbnailReloadSignal sig) {
    if (sig.tick == _reloadTick) return;
    _reloadTick = sig.tick;
    // Soft reload only re-attempts tiles still showing the placeholder; a hard
    // rebuild always re-fetches (bypassing the cache).
    if (!sig.force && _bytes != null) return;
    if (sig.force && _bytes != null) setState(() => _bytes = null);
    _start(force: sig.force);
  }

  @override
  Widget build(BuildContext context) {
    // Listen (not watch): reload epochs are rare, and this avoids rebuilding
    // every tile on unrelated notifier churn.
    ref.listen<ThumbnailReloadSignal>(
      thumbnailReloadProvider,
      (_, next) => _onReload(next),
    );

    final c = AircloneTheme.of(context);
    final bytes = _bytes;
    final Widget child = bytes == null
        ? KeyedSubtree(
            key: const ValueKey('thumb-placeholder'),
            child: widget.placeholder,
          )
        : Image.memory(
            bytes,
            key: const ValueKey('thumb-image'),
            fit: widget.fit,
            gaplessPlayback: true,
            width: double.infinity,
            height: double.infinity,
          );

    return Container(
      color: c.surfaceSunken,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (w, anim) => FadeTransition(opacity: anim, child: w),
        child: child,
      ),
    );
  }
}
