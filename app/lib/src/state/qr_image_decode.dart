import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Reads the first QR code out of a raster image (PNG/JPG/screenshot/photo) and
/// returns its text payload, or null if the bytes aren't a decodable image or
/// hold no readable QR.
///
/// This is the DESKTOP counterpart to the phone's live camera scan: a computer
/// has no camera to point at an Offline QR, and `mobile_scanner` ships no
/// Windows/Linux implementation, so importing on a desktop means decoding the QR
/// out of an image file the user picked (a screenshot, or a photo they were
/// sent). Everything here is pure Dart — `image` rasterises, `zxing2` reads — so
/// it runs the same on every platform with no native dependency.
///
/// Never throws: a corrupt image, an unsupported format, or an unreadable QR all
/// come back as null, which the caller ([config_import_dialog]) turns into a
/// friendly "couldn't find an Offline QR in that image" message rather than a
/// crash. It does NOT interpret the payload — the caller decides whether the
/// decoded string is an Airclone Offline QR (and unseals it with the code).
String? decodeQrFromImageBytes(Uint8List bytes) {
  // One catch-all so the never-throws contract holds through EVERY step — not
  // just the decode, but the pixel-buffer allocations below too. A corrupt image,
  // an unsupported format, or an out-of-memory on an oversized/decompression-bomb
  // image all come back as null rather than escaping to the caller.
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // zxing2 wants one Int32 per pixel in 0xAARRGGBB order (its
    // RGBLuminanceSource reads r=(p>>16)&0xff, g=(p>>8)&0xff, b=p&0xff).
    // Normalising to 4 channels first handles palette/grayscale/16-bit sources
    // uniformly. On little-endian, `ChannelOrder.bgra` lays out bytes [B,G,R,A]
    // which read back as 0xAARRGGBB — the order zxing expects. (The old `abgr`
    // produced 0xRRGGBBAA, so luminance was computed from (G,B,ALPHA): a black
    // module came out at ~63 instead of 0, halving contrast and eroding the
    // decode margin on noisier photos.)
    final rgba = decoded.numChannels == 4
        ? decoded
        : decoded.convert(numChannels: 4);
    final Int32List pixels = rgba
        .getBytes(order: img.ChannelOrder.bgra)
        .buffer
        .asInt32List();
    final source = RGBLuminanceSource(rgba.width, rgba.height, pixels);

    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    // Hybrid first — best for photos / uneven screen lighting; global histogram
    // second — best for a crisp synthetic render. NotFound/format/checksum on one
    // just falls through to the next; both failing means "no QR here" -> null.
    for (final binarizer in [
      HybridBinarizer(source),
      GlobalHistogramBinarizer(source),
    ]) {
      try {
        final result = QRCodeReader().decode(
          BinaryBitmap(binarizer),
          hints: hints,
        );
        if (result.text.isNotEmpty) return result.text;
      } catch (_) {
        // Try the next binarizer.
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// [decodeQrFromImageBytes] off the UI isolate. Decoding a full-resolution phone
/// photo with `tryHarder` is CPU-heavy and synchronous, so run it in a background
/// isolate to keep the import dialog responsive while a spinner shows.
Future<String?> decodeQrFromImage(Uint8List bytes) =>
    compute(decodeQrFromImageBytes, bytes);
