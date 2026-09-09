import 'package:airclone/src/ui/media_preview.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// From a Google TV user, 2026-09-09: *"When we open any movie on any cloud
/// provider there is a small blue rectangle on the middle of the screen. this
/// blue rectangle do not disappear when we watch any movie."*
///
/// The rectangle was [TvFocusOverlay]'s own ring. media_kit's controls wrap the
/// video in a `Focus(autofocus: true)` that takes focus the instant a film
/// opens; at that instant the surface was a 36px box under the loading spinner
/// (a loose Stack sizes to its non-positioned child), and the ring measured
/// once and never again. Two fixes, each pinned here on its own:
///
///  1. [VideoSurfaceFrame] keeps the surface full-size while loading;
///  2. [TvFocusOverlay] re-measures after every frame while anything holds
///     focus, and draws nothing for a target that covers the whole shell.
///
/// Neither needs a television or libmpv: the overlay only cares about the
/// focused widget's geometry, and the frame only about constraints.
void main() {
  Widget shell(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: TvFocusOverlay(child: child),
  );

  // The ring is the only DecoratedBox the overlay itself adds; every host
  // below is built from widgets that add none.
  Finder ring() => find.descendant(
    of: find.byType(TvFocusOverlay),
    matching: find.byType(DecoratedBox),
  );

  /// A focused box whose size can change with NO focus change: the builder
  /// updates the same `Focus` element in place, so its node is untouched.
  Widget growable(ValueNotifier<double> size, Key target) => Center(
    child: ValueListenableBuilder<double>(
      valueListenable: size,
      builder: (_, s, _) => Focus(
        autofocus: true,
        child: SizedBox(key: target, width: s, height: s),
      ),
    ),
  );

  testWidgets('the ring follows a focused widget that is laid out again', (
    tester,
  ) async {
    final size = ValueNotifier<double>(36);
    addTearDown(size.dispose);
    final target = UniqueKey();

    await tester.pumpWidget(shell(growable(size, target)));
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus;
    expect(
      tester.getRect(ring()),
      tester.getRect(find.byKey(target)).inflate(3),
    );

    size.value = 200;
    await tester.pumpAndSettle();

    // Same node still focused: nothing told the overlay, and it must not need
    // telling.
    expect(FocusManager.instance.primaryFocus, same(focused));
    expect(tester.getSize(find.byKey(target)), const Size(200, 200));
    expect(
      tester.getRect(ring()),
      tester.getRect(find.byKey(target)).inflate(3),
    );
  });

  testWidgets('a target that covers the whole shell gets no ring', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(
      shell(
        Focus(focusNode: node, autofocus: true, child: const SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();

    expect(node.hasPrimaryFocus, isTrue);
    expect(ring(), findsNothing);
  });

  testWidgets('the film: a 36px autofocused box that grows to fill the screen '
      'loses its ring', (tester) async {
    // Exactly the reported sequence. The first frame of a cloud stream takes
    // seconds; focus lands in milliseconds, on a 36px box at dead centre.
    final size = ValueNotifier<double>(36);
    addTearDown(size.dispose);
    final target = UniqueKey();

    await tester.pumpWidget(shell(growable(size, target)));
    await tester.pumpAndSettle();
    expect(ring(), findsOneWidget);
    expect(
      tester.getCenter(ring()),
      tester.getCenter(find.byType(TvFocusOverlay)),
    );

    // The first frame arrives and the surface fills the screen.
    size.value = double.infinity;
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(target)),
      tester.getSize(find.byType(TvFocusOverlay)),
    );
    expect(ring(), findsNothing);
  });

  testWidgets('VideoSurfaceFrame keeps the surface full-size while loading', (
    tester,
  ) async {
    final surface = UniqueKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        // Loose constraints on purpose: that is the case a loose Stack
        // collapses under, and the old frame loosened them itself.
        home: Center(
          child: VideoSurfaceFrame(
            loading: true,
            surface: SizedBox.expand(key: surface),
          ),
        ),
      ),
    );
    // A single pump: the spinner animates forever, so there is no settling.
    await tester.pump();

    final full = tester.getSize(find.byType(MaterialApp));
    expect(tester.getSize(find.byType(VideoSurfaceFrame)), full);
    expect(tester.getSize(find.byKey(surface)), full);

    final spinner = tester.getRect(find.byType(CircularProgressIndicator));
    expect(spinner.size, const Size(36, 36));
    expect(spinner.center, tester.getCenter(find.byType(MaterialApp)));
  });
}
