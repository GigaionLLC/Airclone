import 'package:airclone/src/state/pane_layout.dart';
import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('clampSplitRatio', () {
    test('keeps an in-range ratio unchanged', () {
      expect(clampSplitRatio(0.5), 0.5);
      expect(clampSplitRatio(0.35), 0.35);
      expect(clampSplitRatio(kMinSplitRatio), kMinSplitRatio);
      expect(clampSplitRatio(kMaxSplitRatio), kMaxSplitRatio);
    });

    test('clamps below the min so the first pane never collapses', () {
      expect(clampSplitRatio(0.0), kMinSplitRatio);
      expect(clampSplitRatio(-1), kMinSplitRatio);
      expect(clampSplitRatio(0.05), kMinSplitRatio);
    });

    test('clamps above the max so the second pane never collapses', () {
      expect(clampSplitRatio(1.0), kMaxSplitRatio);
      expect(clampSplitRatio(2), kMaxSplitRatio);
      expect(clampSplitRatio(0.95), kMaxSplitRatio);
    });
  });

  group('resolveSplitAxis', () {
    test('adaptive splits by width at the breakpoint', () {
      expect(
        resolveSplitAxis(PaneSplitOrientation.adaptive, 800),
        Axis.horizontal,
      );
      // At exactly the breakpoint it goes side-by-side (>=).
      expect(
        resolveSplitAxis(PaneSplitOrientation.adaptive, kSideBySideBreakpoint),
        Axis.horizontal,
      );
      expect(
        resolveSplitAxis(
          PaneSplitOrientation.adaptive,
          kSideBySideBreakpoint - 1,
        ),
        Axis.vertical,
      );
      expect(
        resolveSplitAxis(PaneSplitOrientation.adaptive, 320),
        Axis.vertical,
      );
    });

    test('manual orientations ignore the width', () {
      expect(
        resolveSplitAxis(PaneSplitOrientation.sideBySide, 100),
        Axis.horizontal,
      );
      expect(
        resolveSplitAxis(PaneSplitOrientation.stacked, 4000),
        Axis.vertical,
      );
    });

    test('honours a custom breakpoint', () {
      expect(
        resolveSplitAxis(PaneSplitOrientation.adaptive, 500, breakpoint: 400),
        Axis.horizontal,
      );
      expect(
        resolveSplitAxis(PaneSplitOrientation.adaptive, 300, breakpoint: 400),
        Axis.vertical,
      );
    });
  });

  group('nextOrientation', () {
    test('cycles adaptive → side-by-side → stacked → adaptive', () {
      expect(
        nextOrientation(PaneSplitOrientation.adaptive),
        PaneSplitOrientation.sideBySide,
      );
      expect(
        nextOrientation(PaneSplitOrientation.sideBySide),
        PaneSplitOrientation.stacked,
      );
      expect(
        nextOrientation(PaneSplitOrientation.stacked),
        PaneSplitOrientation.adaptive,
      );
    });
  });

  group('paneSplitRatioProvider', () {
    test('defaults to a 50/50 split', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(paneSplitRatioProvider), 0.5);
    });

    test('set clamps out-of-range values', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(paneSplitRatioProvider.notifier);
      await n.set(0.95);
      expect(c.read(paneSplitRatioProvider), kMaxSplitRatio);
      await n.set(0.0);
      expect(c.read(paneSplitRatioProvider), kMinSplitRatio);
      await n.set(0.42);
      expect(c.read(paneSplitRatioProvider), 0.42);
    });

    test('restores a persisted value, re-clamped', () async {
      SharedPreferences.setMockInitialValues({'pane_split_ratio': 0.99});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(paneSplitRatioProvider); // build() kicks off the async load
      await pumpEventQueue();
      expect(c.read(paneSplitRatioProvider), kMaxSplitRatio);
    });
  });

  group('paneSplitOrientationProvider', () {
    test('defaults to adaptive', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(paneSplitOrientationProvider),
        PaneSplitOrientation.adaptive,
      );
    });

    test('cycle advances the choice', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(paneSplitOrientationProvider.notifier).cycle();
      expect(
        c.read(paneSplitOrientationProvider),
        PaneSplitOrientation.sideBySide,
      );
    });

    test('restores a persisted value', () async {
      SharedPreferences.setMockInitialValues({
        'pane_split_orientation': 'stacked',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(paneSplitOrientationProvider);
      await pumpEventQueue();
      expect(
        c.read(paneSplitOrientationProvider),
        PaneSplitOrientation.stacked,
      );
    });

    test(
      'tolerates a garbage persisted value (falls back to adaptive)',
      () async {
        SharedPreferences.setMockInitialValues({
          'pane_split_orientation': 'not-a-real-orientation',
        });
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c.read(paneSplitOrientationProvider);
        await pumpEventQueue();
        expect(
          c.read(paneSplitOrientationProvider),
          PaneSplitOrientation.adaptive,
        );
      },
    );
  });

  test('mobileSplitProvider defaults to single-pane (off)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(mobileSplitProvider), false);
  });
}
