import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/transfer_options_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a host that opens the transfer-options dialog.
Future<void> _open(WidgetTester tester) async {
  // The dialog is 720x560; give it a window big enough to fully lay out.
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showTransferOptionsDialog(
                ctx,
                fromLabel: 'gdrive:Work',
                toLabel: 's3:backup',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings tab teaches the rclone flag on each option', (
    tester,
  ) async {
    await _open(tester);
    // Skip rules carry their flag in the help line.
    expect(find.textContaining('--update'), findsOneWidget);
    expect(find.textContaining('--ignore-existing'), findsOneWidget);
    // Dry run is a first-class footer button next to Run.
    expect(find.widgetWithText(OutlinedButton, 'Dry run'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Run'), findsOneWidget);
  });

  testWidgets('Filters tab labels each field with its flag', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('--include'), findsOneWidget);
    expect(find.text('--exclude'), findsOneWidget);
    expect(find.text('--filter'), findsOneWidget);
  });
}
