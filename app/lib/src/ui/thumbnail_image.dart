import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/thumbnail_service.dart';
import 'theme/tokens.dart';

/// Cache keys that have loaded at least once this session, so a re-mount
/// (scroll back into view) renders instantly off the disk cache.
final Set<String> _loadedKeys = <String>{};

/// Lazy thumbnail tile: shows [placeholder] until bytes resolve, then fades
/// in the decoded image. Loads only when mounted (visible-window-only).
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
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final bytes = await ref
          .read(thumbnailServiceProvider)
          .load(widget.request);
      if (!mounted) return;
      if (bytes != null) {
        _loadedKeys.add(widget.request.cacheKey);
        setState(() => _bytes = bytes);
      }
    } catch (_) {
      // keep placeholder
    }
  }

  @override
  Widget build(BuildContext context) {
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
