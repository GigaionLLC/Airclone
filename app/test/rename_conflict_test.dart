import 'package:airclone/src/ui/file_op_dialogs.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renaming onto an existing name is blocked inline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showRenameDialog(ctx, 'a.txt', taken: const {'b.txt'}),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Try to rename onto b.txt → blocked, dialog stays, error shown.
    await tester.enterText(find.byType(TextField), 'b.txt');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(
      find.text('A file or folder named "b.txt" already exists here.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget); // still open

    // Fix to a free name → the error clears and it submits.
    await tester.enterText(find.byType(TextField), 'c.txt');
    await tester.pump();
    expect(
      find.text('A file or folder named "b.txt" already exists here.'),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing); // closed
  });

  testWidgets('keeping the same name is allowed (not a self-collision)', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result = await showRenameDialog(
                  ctx,
                  'a.txt',
                  taken: const {'b.txt'},
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
    // Leave the prefilled 'a.txt' unchanged and submit.
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(result, 'a.txt');
  });

  testWidgets('new folder with an existing name is blocked', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showNewFolderDialog(ctx, taken: const {'Work'}),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(
      find.text('A file or folder named "Work" already exists here.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
  });
}
