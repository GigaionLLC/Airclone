import 'package:flutter/material.dart';

/// A pannable + pinch/scroll-zoomable network image.
///
/// Shared verbatim by the in-app preview (preview_dialog `_ImageBody`, which
/// Quick Look reuses) AND the desktop pop-out window (popout_image_app.dart), so
/// zoom behaves IDENTICALLY in both — an `InteractiveViewer(maxScale: 8)` over a
/// letter-boxed `Image.network`. It renders its own loading spinner and a
/// self-contained error card so it can stand alone inside the pop-out engine,
/// which has none of the preview dialog's themed chrome to borrow.
class ZoomableNetworkImage extends StatelessWidget {
  const ZoomableNetworkImage({
    super.key,
    required this.url,
    required this.headers,
    this.backgroundColor,
    this.maxScale = 8,
    this.errorBuilder,
  });

  /// The image URL — on desktop an authenticated rcd loopback object URL.
  final String url;

  /// Request headers (typically the rcd per-session Basic `Authorization`).
  final Map<String, String> headers;

  /// Fill painted behind the letter-boxed image; transparent when null.
  final Color? backgroundColor;

  /// Maximum pinch/scroll zoom. 8× matches the inline preview.
  final double maxScale;

  /// Optional themed error widget (the in-app dialog passes its own so the
  /// error card matches the app). When null, a plain built-in card is used so
  /// the pop-out — which has no shared theme chrome — still shows something.
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      width: double.infinity,
      child: InteractiveViewer(
        maxScale: maxScale,
        child: Center(
          child: Image.network(
            url,
            headers: headers,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder:
                errorBuilder ??
                (context, error, stack) => _DefaultImageError(error: error),
          ),
        ),
      ),
    );
  }
}

/// Fallback error card, used when no themed [ZoomableNetworkImage.errorBuilder]
/// is supplied (i.e. the pop-out): a centered broken-image glyph + error text on
/// the dark image background.
class _DefaultImageError extends StatelessWidget {
  const _DefaultImageError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              size: 40,
              color: Colors.white54,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load image',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
