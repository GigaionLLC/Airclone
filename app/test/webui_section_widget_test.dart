/// Widget tests for Settings → Remote access → Web UI.
///
/// This panel cannot be verified by driving the real desktop app from here, so
/// it is pinned at real sizes instead. What is worth pinning is not that the
/// widgets exist but that the panel is honest about exposure: that it starts on
/// "this computer only", that picking "any network" is a visible choice, and
/// that the wording never implies the browser is doing the work.
library;

import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/webui_section.dart';
import 'package:airclone/src/webui/webui_controller.dart';
import 'package:airclone/src/webui/webui_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpSection(
  WidgetTester tester, {
  Size size = const Size(520, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(), // supplies the AircloneTheme extension
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: EdgeInsets.all(16), child: WebUiSection()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders and offers a way to start it', (tester) async {
    await pumpSection(tester);
    expect(find.text('Web UI'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    // Off until someone turns it on — never serving by merely existing.
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('says the work happens on this computer, not in the browser', (
    tester,
  ) async {
    await pumpSection(tester);
    // The single most important sentence in the panel. If this stops being
    // said, someone will mount a drive expecting it on their phone.
    expect(find.textContaining('happens on this computer'), findsOneWidget);
  });

  testWidgets('starts on "this computer only"', (tester) async {
    await pumpSection(tester);
    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    // true == isLoopback. A Web UI that were reachable from the network the
    // moment it was switched on would be a hole opened by a single click.
    expect(segmented.selected, {true});
  });

  testWidgets('both exposure choices are offered plainly', (tester) async {
    await pumpSection(tester);
    expect(find.text('This computer'), findsOneWidget);
    expect(find.text('Any network'), findsOneWidget);
    expect(find.text('Who can reach it'), findsOneWidget);
  });

  testWidgets('shows the address and port it will use', (tester) async {
    await pumpSection(tester);
    expect(find.widgetWithText(TextField, 'Address'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Port'), findsOneWidget);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.first.controller!.text, kDefaultWebUiBind);
    expect(fields.last.controller!.text, '$kDefaultWebUiPort');
  });

  testWidgets('nothing is revealed before it is running', (tester) async {
    await pumpSection(tester);
    // No URL, no username, no password row until there is a server.
    expect(find.text('Password'), findsNothing);
    expect(find.text('Address'), findsOneWidget); // the bind field's label only
    expect(find.text('New password'), findsNothing);
  });

  testWidgets('a bad address is rejected in place, not saved', (tester) async {
    await pumpSection(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Address'),
      'example.com',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('is not an IP address'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    // Storing it would make every future start fail, far from where it was
    // typed.
    expect(prefs.getString('webui.bind'), isNot('example.com'));
  });

  testWidgets('a valid address is accepted and persisted', (tester) async {
    await pumpSection(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Address'),
      '192.168.1.50',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('is not an IP address'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('webui.bind'), '192.168.1.50');
  });

  testWidgets('survives a narrow window without overflowing', (tester) async {
    // Settings is reachable in the phone shell too, and an overflow there is a
    // yellow-and-black bar across the panel.
    await pumpSection(tester, size: const Size(360, 900));
    expect(tester.takeException(), isNull);
  });

  group('WebUiUi', () {
    test('is only "exposed" when it is both running and off loopback', () {
      const stopped = WebUiUi(options: WebUiOptions(bindAddress: '0.0.0.0'));
      expect(stopped.exposed, isFalse, reason: 'not running yet');
      const running = WebUiUi(
        options: WebUiOptions(bindAddress: '0.0.0.0'),
        running: true,
      );
      expect(running.exposed, isTrue);
      const loopback = WebUiUi(options: WebUiOptions(), running: true);
      expect(loopback.exposed, isFalse);
    });
  });
}
