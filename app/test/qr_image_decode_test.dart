import 'dart:typed_data';

import 'package:airclone/src/state/qr_image_decode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// Renders [data] as a crisp black-on-white QR PNG — the same thing a user would
/// screenshot off the export screen — so we can prove the desktop decoder reads
/// its own output back with no camera involved.
Uint8List _renderQrPng(String data, {int scale = 8, int quiet = 4}) {
  final code = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qr = QrImage(code);
  final modules = code.moduleCount;
  final dim = (modules + quiet * 2) * scale;
  final image = img.Image(width: dim, height: dim);
  for (var y = 0; y < dim; y++) {
    for (var x = 0; x < dim; x++) {
      final mc = x ~/ scale - quiet;
      final mr = y ~/ scale - quiet;
      final dark =
          mr >= 0 &&
          mr < modules &&
          mc >= 0 &&
          mc < modules &&
          qr.isDark(mr, mc);
      final v = dark ? 0 : 255;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return img.encodePng(image);
}

void main() {
  group('decodeQrFromImageBytes', () {
    test('round-trips a short payload', () {
      const payload = 'AIRCLONE-CFG-Q1:HELLO WORLD 123';
      final png = _renderQrPng(payload, scale: 10);
      expect(decodeQrFromImageBytes(png), payload);
    });

    test('round-trips a long chunk-sized payload (high-version QR)', () {
      // A real multi-QR chunk is a fixed-width header + ~1400 base45 chars, all
      // in the QR alphanumeric charset. Prove a QR that big still reads back.
      const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final body = StringBuffer();
      for (var i = 0; i < 1400; i++) {
        body.write(charset[i % charset.length]);
      }
      final payload = 'AIRCLONE-CFG-Q1M:AB12010003$body';
      final png = _renderQrPng(payload, scale: 6);
      expect(decodeQrFromImageBytes(png), payload);
    });

    test('returns null for bytes that are not an image', () {
      expect(
        decodeQrFromImageBytes(Uint8List.fromList([0, 1, 2, 3, 4, 5])),
        isNull,
      );
    });

    test('returns null for an image with no QR in it', () {
      final blank = img.Image(width: 120, height: 120);
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 120; x++) {
          blank.setPixelRgb(x, y, 255, 255, 255);
        }
      }
      expect(decodeQrFromImageBytes(img.encodePng(blank)), isNull);
    });
  });
}
