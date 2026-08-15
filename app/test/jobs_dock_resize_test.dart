import 'package:airclone/src/state/pane_layout.dart';
import 'package:airclone/src/ui/pane_split.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bottom Transfers / Recent-activity dock is dragged by its top edge, so
/// pulling the handle UP must make it TALLER. That sign is the whole bug risk
/// in the wiring, and the clamp is what stops a drag from swallowing the file
/// panes — both are exercised here against the same [ResizeHandle] the shell
/// uses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A miniature of the shell's work area: panes on top, drag handle, dock.
  Widget harness({double viewport = 600}) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            height: viewport,
            child: Consumer(
              builder: (context, ref, _) {
                final height = clampJobsDockHeight(
                  ref.watch(jobsDockHeightProvider),
                  viewport,
                );
                return Column(
                  children: [
                    const Expanded(child: SizedBox.expand()),
                    ResizeHandle(
                      axis: Axis.vertical,
                      onDelta: (dy) => ref
                          .read(jobsDockHeightProvider.notifier)
                          .set(clampJobsDockHeight(height - dy, viewport)),
                    ),
                    SizedBox(
                      height: height,
                      child: const Text('dock', key: Key('dock')),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  double dockHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('dock'))).height;

  testWidgets('opens at the default height', (tester) async {
    await tester.pumpWidget(harness());
    expect(dockHeight(tester), kDefaultJobsDockHeight);
  });

  testWidgets('dragging the handle up grows the dock', (tester) async {
    await tester.pumpWidget(harness());
    // touchSlopY: 0 — a default drag swallows its first 20px as gesture slop,
    // which would make the arithmetic here look wrong for no real reason.
    await tester.drag(
      find.byType(ResizeHandle),
      const Offset(0, -100),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();
    expect(dockHeight(tester), kDefaultJobsDockHeight + 100);
  });

  testWidgets('dragging the handle down shrinks the dock', (tester) async {
    await tester.pumpWidget(harness());
    await tester.drag(
      find.byType(ResizeHandle),
      const Offset(0, 80),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();
    expect(dockHeight(tester), kDefaultJobsDockHeight - 80);
  });

  testWidgets('a drag past the floor stops at the minimum', (tester) async {
    await tester.pumpWidget(harness());
    await tester.drag(find.byType(ResizeHandle), const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(dockHeight(tester), kMinJobsDockHeight);
  });

  testWidgets('a drag past the ceiling leaves room for the panes', (
    tester,
  ) async {
    await tester.pumpWidget(harness(viewport: 600));
    await tester.drag(find.byType(ResizeHandle), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(dockHeight(tester), 600 * kMaxJobsDockFraction);
  });

  testWidgets('the dragged height is persisted', (tester) async {
    await tester.pumpWidget(harness());
    await tester.drag(
      find.byType(ResizeHandle),
      const Offset(0, -60),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('jobs_dock_height'), kDefaultJobsDockHeight + 60);
  });
}
