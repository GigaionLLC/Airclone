import 'package:airclone/src/ui/console_pane.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runtime-tree smoke for the console pane: it renders (empty state), and typing
/// a command surfaces the live exact-command preview with the right tier badge.
/// (The dispatch path needs a live engine and is covered by the pure-logic +
/// integration tests.)
void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ConsolePane(consoleId: 'test-console')),
        ),
      ),
    );
  }

  testWidgets('renders empty state + input', (tester) async {
    await pump(tester);
    expect(find.text('CONSOLE'), findsOneWidget);
    expect(find.textContaining('Type an rclone command'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
  });

  testWidgets('typing surfaces a live preview with a tier badge', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'lsjson gdrive:');
    await tester.pump();
    // Safe command → "runs" badge + rclone-prefixed exact preview.
    expect(find.text('runs'), findsOneWidget);
    expect(find.text('rclone lsjson gdrive:'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'delete gdrive:junk');
    await tester.pump();
    // Destructive verb → "destructive" badge.
    expect(find.text('destructive'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'config show');
    await tester.pump();
    // Blocked verb → "blocked" badge.
    expect(find.text('blocked'), findsOneWidget);
  });

  testWidgets('typing a verb prefix shows an autocomplete popover with docs', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'ls');
    await tester.pump();
    // Subcommand suggestions appear (lsjson, lsd, …) each with a docs link.
    expect(find.text('lsjson'), findsWidgets);
    expect(find.text('docs ↗'), findsWidgets);
  });
}
