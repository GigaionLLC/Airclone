import 'package:airclone/src/ui/dialog_body.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/transfer_options_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A folding phone is a window that CHANGES WIDTH while the app is running, and
/// it spends time at sizes no fixed phone ever has: very narrow on a closed
/// cover display, near-square when opened flat, short and wide half-folded.
///
/// Airclone's layout is width-driven — `MediaQuery.sizeOf(context).width < 700`
/// picks the phone shell, and [DialogBody] clamps each dialog's desktop width
/// against the live screen — so it should follow a fold rather than break on
/// one. Both reads happen inside `build`, which is what makes them react to a
/// resize instead of latching the size the app launched at.
///
/// This pins that claim at the awkward sizes instead of assuming it. The
/// existing transfer-options tests all run at 1200x900, with a comment saying to
/// "give it a window big enough to fully lay out" — so the 720px-wide dialog had
/// never once been pumped at a width smaller than itself.
///
/// The sizes below deliberately BRACKET a range rather than model one device:
/// no unreleased hardware's exact geometry is known here, and a layout that
/// holds across the range holds for whatever the real numbers turn out to be.
const _poses = <String, Size>{
  // Narrower than any current iPhone — a closed cover display.
  'cover display (very narrow)': Size(320, 750),
  'phone, portrait': Size(390, 844),
  'large phone, portrait': Size(430, 932),
  // Half-folded, laid on its side: short and wide. Height is the scarce axis.
  'half-folded (short, wide)': Size(750, 380),
  // Opened flat. Crosses the 700px gate into the desktop shell.
  'unfolded (near-square)': Size(744, 1000),
  'unfolded, landscape': Size(1000, 744),
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the transfer-options dialog survives every pose', () {
    // It asks for 720x560. Every pose below is narrower than that except the
    // last two, so this is the fixed-desktop-width case at its worst.
    _poses.forEach((pose, size) {
      testWidgets('no overflow at $pose ($size)', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showTransferOptionsDialog(
                        ctx,
                        fromLabel: 'gdrive:Work',
                        toLabel: 's3:backup',
                        isRunNow: true,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // A RenderFlex/RenderBox overflow is reported as a FlutterError during
        // layout or paint, which the test binding records rather than throws.
        expect(
          tester.takeException(),
          isNull,
          reason: 'laying the dialog out at $pose overflowed',
        );
      });
    });
  });

  group('DialogBody clamps to the pose, not to the desktop', () {
    _poses.forEach((pose, size) {
      testWidgets('a 720px dialog fits at $pose', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: DialogBody(
                width: 720,
                child: Container(key: const Key('body'), height: 40),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final w = tester.getSize(find.byKey(const Key('body'))).width;
        expect(w, lessThanOrEqualTo(size.width));
        expect(w, lessThanOrEqualTo(720));
        expect(tester.takeException(), isNull);
      });
    });
  });

  testWidgets('a fold is a RESIZE: the same widget re-clamps without a rebuild '
      'from scratch', (tester) async {
    // The real risk of a folding device is not any single size, it is the
    // transition — a layout that reads the size once and keeps it is correct on
    // launch and wrong forever after the first fold.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: DialogBody(
            width: 720,
            child: SizedBox(key: Key('b'), height: 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('b'))).width, 720);

    // Fold it shut, with no new pumpWidget: exactly what the OS does.
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('b'))).width,
      lessThanOrEqualTo(360),
      reason: 'the dialog kept its unfolded width after the device folded',
    );

    // And back open again.
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('b'))).width, 720);
  });
}
