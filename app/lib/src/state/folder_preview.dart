import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cache_crypto.dart';

/// An authenticated reference to one image inside a folder, for thumbnailing.
@immutable
class FolderImageRef {
  const FolderImageRef({required this.url, required this.headers});
  final String url;
  final Map<String, String> headers;
}

/// Builds a Windows-style folder thumbnail by compositing a few of the
/// folder's images into a 2x2 grid on a subtle card background, disk-cached.
class FolderPreviewService {
  FolderPreviewService(this._ref);
  final Ref _ref;

  static const _bg = Color(0xFF101216); // surfaceSunken-ish
  static const _maxConcurrent = 3;
  static const _gap = 2.0;

  int _active = 0;
  final _queue = <Completer<void>>[];

  /// Composite up to 4 [images] into a square [size] PNG. Returns the cached
  /// (decrypted) bytes on a disk hit, else fetches/decodes/draws/seals/writes.
  /// Null on any failure or when no image could be loaded. [remoteSecret] seeds
  /// the at-rest key when the rclone config has no password.
  Future<Uint8List?> compose({
    required String cacheKey,
    required List<FolderImageRef> images,
    String remoteSecret = '',
    int size = 256,
  }) async {
    final memoryOnly = _ref.read(cacheMemoryOnlyProvider);

    if (!memoryOnly) {
      try {
        final file = await _cacheFile(cacheKey);
        if (await file.exists()) {
          final blob = await file.readAsBytes();
          final png = await _ref
              .read(cacheCryptoProvider)
              .open(blob, remoteSecret);
          if (png != null) return png;
        }
      } catch (_) {
        // Fall through to recompute on any cache-read failure.
      }
    }

    await _acquire();
    Uint8List? bytes;
    try {
      bytes = await _build(images, size);
    } catch (_) {
      bytes = null;
    } finally {
      _release();
    }
    if (bytes == null) return null;

    if (!memoryOnly) {
      try {
        final blob = await _ref
            .read(cacheCryptoProvider)
            .seal(bytes, remoteSecret);
        final file = await _cacheFile(cacheKey);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(blob, flush: true);
      } catch (_) {
        // Cache write is best-effort; still return the bytes.
      }
    }
    return bytes;
  }

  /// Fetch + decode the first 4 images and draw them into a grid.
  Future<Uint8List?> _build(List<FolderImageRef> images, int size) async {
    final tiles = <ui.Image>[];
    for (final ref in images.take(4)) {
      final img = await _load(ref, size ~/ 2);
      if (img != null) tiles.add(img);
    }
    if (tiles.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dim = size.toDouble();
    canvas.drawRect(Rect.fromLTWH(0, 0, dim, dim), Paint()..color = _bg);

    final cells = _cells(tiles.length, dim);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;
    for (var i = 0; i < tiles.length; i++) {
      final img = tiles[i];
      final src = Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      canvas.drawImageRect(img, src, cells[i], paint);
      img.dispose();
    }

    final picture = recorder.endRecording();
    try {
      final out = await picture.toImage(size, size);
      try {
        final data = await out.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        out.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// Destination rects for [count] tiles (1/2/3 laid out neatly, 4 as 2x2),
  /// with [_gap]px gaps.
  List<Rect> _cells(int count, double dim) {
    final half = (dim - _gap) / 2;
    switch (count) {
      case 1:
        return [Rect.fromLTWH(0, 0, dim, dim)];
      case 2:
        // Side by side, full height.
        return [
          Rect.fromLTWH(0, 0, half, dim),
          Rect.fromLTWH(half + _gap, 0, half, dim),
        ];
      case 3:
        // One full-height left, two stacked right.
        return [
          Rect.fromLTWH(0, 0, half, dim),
          Rect.fromLTWH(half + _gap, 0, half, half),
          Rect.fromLTWH(half + _gap, half + _gap, half, half),
        ];
      default:
        // 2x2 grid.
        return [
          Rect.fromLTWH(0, 0, half, half),
          Rect.fromLTWH(half + _gap, 0, half, half),
          Rect.fromLTWH(0, half + _gap, half, half),
          Rect.fromLTWH(half + _gap, half + _gap, half, half),
        ];
    }
  }

  /// HTTP GET + decode one image at [targetWidth]. Null on any failure.
  Future<ui.Image?> _load(FolderImageRef ref, int targetWidth) async {
    try {
      final resp = await http
          .get(Uri.parse(ref.url), headers: ref.headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final bytes = resp.bodyBytes;
      if (bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth < 1 ? 1 : targetWidth,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<File> _cacheFile(String cacheKey) async {
    final dir = await getApplicationCacheDirectory();
    final safe = sha1.convert(utf8.encode(cacheKey)).toString();
    return File('${dir.path}/airclone_folderthumbs/$safe.bin');
  }

  /// Concurrency gate: at most [_maxConcurrent] composites at once.
  Future<void> _acquire() {
    if (_active < _maxConcurrent) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _queue.add(completer);
    return completer.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else if (_active > 0) {
      _active--;
    }
  }
}

/// Stable cache key: sha1 hex of "fs|path|modtime-or-empty|childCount".
String folderThumbCacheKey(
  String fs,
  String path,
  DateTime? modTime,
  int childCount,
) {
  final mod = modTime?.toUtc().toIso8601String() ?? '';
  final raw = '$fs|$path|$mod|$childCount';
  return sha1.convert(utf8.encode(raw)).toString();
}

final folderPreviewServiceProvider = Provider<FolderPreviewService>(
  (ref) => FolderPreviewService(ref),
);
