import 'package:airclone/src/state/name_conflict.dart';
import 'package:airclone/src/ui/copy_conflict_dialog.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ConflictChoice?> _openAndTap(WidgetTester tester, String label) async {
  ConflictChoice? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCopyConflictDialog(
                  ctx,
                  collisions: ['a.txt', 'b.txt'],
                  total: 3,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // The collision summary is shown.
  expect(find.text('2 of 3 already exist here'), findsOneWidget);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('each button returns its choice', (tester) async {
    expect(await _openAndTap(tester, 'Skip these'), ConflictChoice.skip);
    expect(await _openAndTap(tester, 'Replace'), ConflictChoice.overwrite);
    expect(await _openAndTap(tester, 'Keep both'), ConflictChoice.keepBoth);
    expect(await _openAndTap(tester, 'Cancel'), ConflictChoice.cancel);
  });
}
