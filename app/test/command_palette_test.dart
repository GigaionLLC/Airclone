import 'package:airclone/src/ui/command_palette.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PaletteAction _a(String label, VoidCallback run, {String keywords = ''}) =>
    PaletteAction(
      label: label,
      icon: Icons.circle,
      run: run,
      keywords: keywords,
    );

Future<void> _open(WidgetTester tester, List<PaletteAction> actions) async {
  tester.view.physicalSize = const Size(1000, 800);
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
              onPressed: () => showCommandPalette(ctx, actions),
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
  group('PaletteAction.matches', () {
    final a = PaletteAction(
      label: 'Mount as a drive',
      icon: Icons.usb,
      run: () {},
      keywords: 'winfsp vfs letter',
    );

    test('empty query matches everything', () {
      expect(a.matches(const []), isTrue);
    });

    test('every token must appear (across label + keywords)', () {
      expect(a.matches(['mount']), isTrue);
      expect(a.matches(['winfsp']), isTrue); // keyword-only hit
      expect(a.matches(['mount', 'drive']), isTrue);
      expect(a.matches(['mount', 'serve']), isFalse); // one token misses
    });
  });

  testWidgets('typing filters the list', (tester) async {
    await _open(tester, [
      _a('Settings', () {}),
      _a('Mount as a drive', () {}),
      _a('Go to gdrive', () {}, keywords: 'remote'),
    ]);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Mount as a drive'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mount');
    await tester.pumpAndSettle();
    expect(find.text('Mount as a drive'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Go to gdrive'), findsNothing);
  });

  testWidgets('tapping a row runs that action and closes the palette', (
    tester,
  ) async {
    var ran = '';
    await _open(tester, [
      _a('Settings', () => ran = 'settings'),
      _a('Mount as a drive', () => ran = 'mount'),
    ]);
    await tester.tap(find.text('Mount as a drive'));
    await tester.pumpAndSettle();
    expect(ran, 'mount');
    // Palette dismissed → search field gone.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Enter runs the top match', (tester) async {
    var ran = '';
    await _open(tester, [
      _a('Settings', () => ran = 'settings'),
      _a('Mount as a drive', () => ran = 'mount'),
    ]);
    await tester.enterText(find.byType(TextField), 'mou');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(ran, 'mount');
  });

  testWidgets('arrow-down moves selection so Enter runs the second item', (
    tester,
  ) async {
    var ran = '';
    await _open(tester, [
      _a('Settings', () => ran = 'settings'),
      _a('Mount as a drive', () => ran = 'mount'),
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(ran, 'mount');
  });
}
