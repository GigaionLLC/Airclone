import 'package:airclone/src/state/window_backdrop.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which window effect each backdrop asks for - and the one platform where it
/// must ask for nothing at all.
///
/// THE BUG THIS PINS. On Linux, calling the effect plugin cost the user their
/// keyboard. Its Linux implementation hides the window and the FlView and shows
/// them again, and a hidden widget stops being the toplevel's focus widget;
/// nothing gives that back, so key events reach a window with no focus widget
/// and the engine never sees them. Clicks, which go by position, keep working -
/// which is exactly how it was reported: "I can click but I cannot type
/// anywhere". Airclone called it at every startup.
///
/// Nothing is lost by not calling it: mica and acrylic are Windows 11 effects,
/// and on Linux every backdrop resolved to `disabled`, which is the state the
/// window is already in.
void main() {
  group('on Linux', () {
    test('no backdrop calls the plugin, whatever the user chose', () {
      for (final backdrop in WindowBackdrop.values) {
        expect(
          backdropEffectFor(backdrop, linux: true),
          isNull,
          reason: '$backdrop must not reach the plugin on Linux',
        );
      }
    });
  });

  group('on Windows and macOS', () {
    test('the plain backdrops ask for the standard window', () {
      expect(
        backdropEffectFor(WindowBackdrop.systemDefault, linux: false),
        WindowEffect.disabled,
      );
      expect(
        backdropEffectFor(WindowBackdrop.solid, linux: false),
        WindowEffect.disabled,
      );
    });

    test('the Windows 11 materials ask for themselves', () {
      expect(
        backdropEffectFor(WindowBackdrop.mica, linux: false),
        WindowEffect.mica,
      );
      expect(
        backdropEffectFor(WindowBackdrop.acrylic, linux: false),
        WindowEffect.acrylic,
      );
    });

    /// Every backdrop must resolve somewhere, or adding one to the enum would
    /// silently stop applying.
    test('every backdrop maps to an effect', () {
      for (final backdrop in WindowBackdrop.values) {
        expect(
          backdropEffectFor(backdrop, linux: false),
          isNotNull,
          reason: '$backdrop resolves to nothing',
        );
      }
    });
  });
}
