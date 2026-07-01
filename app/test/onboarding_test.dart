import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/remotes_provider.dart';
import 'package:airclone/src/ui/browser_pane.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, List<Remote> remotes) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [remotesProvider.overrideWith((ref) async => remotes)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: BrowserPane(index: 0, showToolbar: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first run (no remotes) shows the onboarding CTA', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Connect your first remote'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add a remote'), findsOneWidget);
    expect(find.text('Pick a remote on the left'), findsNothing);
  });

  testWidgets('with remotes configured, the neutral hint shows instead', (
    tester,
  ) async {
    await _pump(tester, const [Remote(name: 'g', type: 'drive', fs: 'g:')]);
    expect(find.text('Pick a remote on the left'), findsOneWidget);
    expect(find.text('Connect your first remote'), findsNothing);
  });
}
