import 'package:airclone/src/state/pane_layout.dart';
import 'package:airclone/src/ui/pane_split.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Render coverage for [PaneSplit]: the persisted ratio drives the two panes'
/// sizes, and the clamp guarantees neither collapses. (The drag→ratio glue is
/// trivial over [PaneSplitRatio.set], whose clamp/persist is covered in
/// pane_layout_test.dart; the layout math is what warrants a widget test.)
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const extent = 1000.0;
  const handle = 8.0; // PaneResizeHandle band width/height

  Future<ProviderContainer> pumpSplit(
    WidgetTester tester,
    Axis axis, {
    double? ratio,
  }) async {
    // A 1000×1000 surface makes the ratio→size math exact (default is 800×600).
    tester.view.physicalSize = const Size(extent, extent);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    if (ratio != null) {
      await container.read(paneSplitRatioProvider.notifier).set(ratio);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(), // supplies the AircloneTheme extension
          home: Scaffold(
            body: SizedBox(
              width: extent,
              height: extent,
              child: PaneSplit(
                axis: axis,
                first: const ColoredBox(color: Colors.red, key: Key('first')),
                second: const ColoredBox(
                  color: Colors.blue,
                  key: Key('second'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('horizontal: pane widths track the ratio', (tester) async {
    await pumpSplit(tester, Axis.horizontal, ratio: 0.3);
    final first = tester.getSize(find.byKey(const Key('first'))).width;
    final second = tester.getSize(find.byKey(const Key('second'))).width;
    // 0.3 of the (extent − handle) share, within one flex rounding unit.
    expect(first, closeTo(0.3 * (extent - handle), 1.5));
    expect(second, closeTo(0.7 * (extent - handle), 1.5));
    expect(first + second + handle, closeTo(extent, 0.5));
  });

  testWidgets('vertical: pane heights track the ratio', (tester) async {
    await pumpSplit(tester, Axis.vertical, ratio: 0.65);
    final first = tester.getSize(find.byKey(const Key('first'))).height;
    final second = tester.getSize(find.byKey(const Key('second'))).height;
    expect(first, closeTo(0.65 * (extent - handle), 1.5));
    expect(second, closeTo(0.35 * (extent - handle), 1.5));
  });

  testWidgets('an out-of-range ratio is clamped so neither pane collapses', (
    tester,
  ) async {
    // The provider clamps on set(); PaneSplit also renders clamped defensively.
    final container = await pumpSplit(tester, Axis.horizontal, ratio: 0.99);
    expect(container.read(paneSplitRatioProvider), kMaxSplitRatio);
    final first = tester.getSize(find.byKey(const Key('first'))).width;
    // Even at the extreme, the SECOND pane keeps at least (1−max) of the space.
    expect(first, closeTo(kMaxSplitRatio * (extent - handle), 1.5));
    expect(
      extent - handle - first,
      greaterThan((1 - kMaxSplitRatio) * (extent - handle) - 1.5),
    );
  });

  testWidgets('the resize handle renders between the two panes', (
    tester,
  ) async {
    await pumpSplit(tester, Axis.horizontal, ratio: 0.5);
    expect(find.byType(PaneResizeHandle), findsOneWidget);
    // Its band sits between first and second horizontally.
    final hx = tester.getCenter(find.byType(PaneResizeHandle)).dx;
    final fx = tester.getCenter(find.byKey(const Key('first'))).dx;
    final sx = tester.getCenter(find.byKey(const Key('second'))).dx;
    expect(fx, lessThan(hx));
    expect(hx, lessThan(sx));
  });
}
