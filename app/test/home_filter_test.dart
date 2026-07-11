import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/state/local_locations.dart';
import 'package:airclone/src/state/remotes_provider.dart';
import 'package:airclone/src/ui/home_view.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Home start page grew a filter field so Ctrl+F works there too (before, the
/// filter box only existed once a remote was open, so Ctrl+F was a no-op on Home).
/// The crux is that the field binds the SAME FocusNode the Ctrl+F shortcut targets
/// (paneFilterFocusProvider(activePane)), and that typing narrows the tiles.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        remotesProvider.overrideWith(
          (ref) => [
            const Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:'),
            const Remote(name: 's3backup', type: 's3', fs: 's3backup:'),
          ],
        ),
        drivesProvider.overrideWithValue(const <LocalLocation>[]),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: HomeView(index: 0, onOpen: (_, _) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('Ctrl+F focus node lands on the Home filter field', (
    tester,
  ) async {
    final container = await pump(tester);
    final node = container.read(paneFilterFocusProvider(0));

    // The single filter field binds the shared Ctrl+F node.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode, same(node));

    // Requesting focus on that node (what the Ctrl+F shortcut does) focuses it.
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);
  });

  testWidgets('typing in the Home filter narrows tiles across sections', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('gdrive'), findsOneWidget);
    expect(find.text('s3backup'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gdr');
    await tester.pumpAndSettle();
    expect(find.text('gdrive'), findsOneWidget);
    expect(find.text('s3backup'), findsNothing);

    // A no-match query shows the empty hint and hides "Add a remote".
    await tester.enterText(find.byType(TextField), 'zzz-nope');
    await tester.pumpAndSettle();
    expect(find.textContaining('No matches'), findsOneWidget);
    expect(find.text('Add a remote'), findsNothing);
  });
}
