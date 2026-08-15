import 'dart:typed_data';

import 'package:airclone/src/state/thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A video capture that comes back as one flat shade is not a thumbnail — it's
/// the black leader a clip opens on, or a frame that never decoded (which is
/// exactly what Android produced before it stopped using libmpv for this). The
/// capture path treats such a frame as a failure so it is never cached, and
/// [isFlatRgba] is the test it applies.
void main() {
  Uint8List fill(int r, int g, int b, {int pixels = 64}) {
    final out = Uint8List(pixels * 4);
    for (var i = 0; i < pixels; i++) {
      out[i * 4] = r;
      out[i * 4 + 1] = g;
      out[i * 4 + 2] = b;
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  test('a solid black frame is flat', () {
    expect(isFlatRgba(fill(0, 0, 0)), isTrue);
  });

  test('a solid mid-grey or coloured frame is flat too', () {
    // Not just black: the emulator's failed renders came back green, and a
    // frame that is one uniform colour is useless whatever that colour is.
    expect(isFlatRgba(fill(128, 128, 128)), isTrue);
    expect(isFlatRgba(fill(0, 200, 0)), isTrue);
  });

  test('a frame with real content is not flat', () {
    final img = fill(0, 0, 0);
    // One bright pixel is enough to prove something decoded.
    img[0] = 255;
    img[1] = 255;
    img[2] = 255;
    expect(isFlatRgba(img), isFalse);
  });

  test('near-black noise still counts as flat', () {
    // Compression noise on a black leader must not read as content, or the
    // guard never fires on a real file.
    final img = fill(0, 0, 0);
    img[4] = 3;
    img[9] = 5;
    expect(isFlatRgba(img), isTrue);
  });

  test('the threshold is exclusive at the boundary', () {
    final img = fill(0, 0, 0);
    // Luma of (r=40,g=0,b=0) is (40*77)>>8 = 12 — exactly the allowed range,
    // so still flat; one shade brighter is content.
    img[0] = 40;
    expect(isFlatRgba(img), isTrue);
    img[0] = 48; // luma 14
    expect(isFlatRgba(img), isFalse);
  });

  test('a dark but detailed frame is kept', () {
    // A night shot is legitimately dark; only *uniformity* condemns a frame.
    final img = fill(4, 4, 6);
    img[0] = 60;
    img[1] = 70;
    img[2] = 90;
    expect(isFlatRgba(img), isFalse);
  });

  test('empty input is never called flat', () {
    expect(isFlatRgba(Uint8List(0)), isFalse);
    expect(isFlatRgba(Uint8List(3)), isFalse);
  });

  test('the range is tunable', () {
    final img = fill(0, 0, 0);
    img[0] = 255; // luma 76
    expect(isFlatRgba(img, range: 200), isTrue);
    expect(isFlatRgba(img, range: 1), isFalse);
  });
}
