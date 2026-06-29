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
  static const _bg = Color(0xFF101216); // surfaceSunken-ish
  static const _maxConcurrent = 3;
  static const _gap = 2.0;

  int _active = 0;
  final _queue = <Completer<void>>[];

  /// Composite up to 4 [images] into a square [size] PNG. Returns cached bytes
  /// on a disk hit, else fetches/decodes/draws/writes. Null on any failure or
  /// when no image could be loaded.
  Future<Uint8List?> compose({
    required String cacheKey,
    required List<FolderImageRef> images,
    int size = 256,
  }) async {
    try {
      final file = await _cacheFile(cacheKey);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {
      // Fall through to recompute on any cache-read failure.
    }

    await _acquire();
    try {
      final bytes = await _build(images, size);
      if (bytes == null) return null;
      try {
        final file = await _cacheFile(cacheKey);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // Cache write is best-effort; still return the bytes.
      }
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _release();
    }
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
    return File('${dir.path}/airclone_folderthumbs/$safe.png');
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
  (ref) => FolderPreviewService(),
);
