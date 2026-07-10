import 'package:airclone/src/state/transfer_options.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/transfer_options_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps a host that opens the transfer-options dialog. [isRunNow] mirrors the
/// ad-hoc browser flow (true, destructive confirms apply) vs task definition
/// (false, Run just returns the options). [onResult] captures what the dialog
/// resolves to.
Future<void> _open(
  WidgetTester tester, {
  bool isRunNow = true,
  void Function(TransferOptions?)? onResult,
}) async {
  // The dialog is 720x560; give it a window big enough to fully lay out.
  tester.view.physicalSize = const Size(1200, 900);
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
                onPressed: () async {
                  final r = await showTransferOptionsDialog(
                    ctx,
                    fromLabel: 'gdrive:Work',
                    toLabel: 's3:backup',
                    isRunNow: isRunNow,
                  );
                  onResult?.call(r);
                },
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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('Sync mode reveals the --max-delete cap field', (tester) async {
    await _open(tester);
    // Copy is the default mode — the sync-only cap is hidden.
    expect(find.text('--max-delete'), findsNothing);
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    // The options list is a lazy, height-constrained ListView — the sync-only
    // cap sits below its fold and is only built once scrolled into view, so
    // drag the list until the field materialises.
    final target = find.text('Abort if more than N files would be deleted');
    final list = find.byType(ListView).first;
    var guard = 0;
    while (target.evaluate().isEmpty && guard++ < 10) {
      await tester.drag(list, const Offset(0, -250), warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    expect(target, findsOneWidget);
    expect(find.text('--max-delete'), findsOneWidget);
  });

  testWidgets('Run on a real Sync shows the destructive confirm first', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pumpAndSettle();
    // The confirm gate appears with a dry-run escape and a destructive action.
    expect(find.text('Sync deletes destination files'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Dry run first'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Run sync'), findsOneWidget);
  });

  testWidgets('Run on Copy does NOT show the sync confirm', (tester) async {
    await _open(tester);
    // Default mode is Copy; Run should pop straight through, no delete warning.
    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pumpAndSettle();
    expect(find.text('Sync deletes destination files'), findsNothing);
  });

  testWidgets(
    'Task definition (isRunNow: false) never confirms and never bakes dryRun',
    (tester) async {
      // Regression guard: the confirm used to fire for the task-definition
      // caller too, and its "Dry run first" nudge persisted dryRun: true into
      // the saved task — a scheduled backup that silently never ran.
      TransferOptions? result;
      await _open(tester, isRunNow: false, onResult: (r) => result = r);
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Run'));
      await tester.pumpAndSettle();
      expect(find.text('Sync deletes destination files'), findsNothing);
      expect(result, isNotNull);
      expect(result!.mode, TransferMode.sync);
      expect(result!.dryRun, isFalse);
    },
  );

  testWidgets('Filters tab labels each field with its flag', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('--include'), findsOneWidget);
    expect(find.text('--exclude'), findsOneWidget);
    expect(find.text('--filter'), findsOneWidget);
  });

  testWidgets('rclone cmd tab shows the command and Copy puts it on the '
      'clipboard', (tester) async {
    final clip = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clip.add(call);
          return null;
        });
    await _open(tester);
    await tester.tap(find.text('rclone cmd'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rclone copy'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsOneWidget);
    expect(clip, isNotEmpty);
    expect(
      (clip.first.arguments['text'] as String).startsWith('rclone copy'),
      isTrue,
    );
  });
}
