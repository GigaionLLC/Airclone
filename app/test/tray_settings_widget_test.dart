/// Settings > Tray (#54): the close-to-tray switch is off by default, is
/// disabled when there is no tray, and the sign-in launch shows either a
/// switch or the reason it is not offered.
library;

import 'package:airclone/src/state/autostart.dart';
import 'package:airclone/src/state/close_to_tray.dart';
import 'package:airclone/src/state/host_platform.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/tray_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeTray extends TrayAvailable {
  FakeTray(this.up);
  final bool up;
  @override
  bool build() => up;
}

class FakeAutostart extends Autostart {
  FakeAutostart(this.initial);
  final AutostartState initial;
  final calls = <bool>[];
  @override
  AutostartState build() => initial;
  @override
  Future<bool> set(bool enabled) async {
    calls.add(enabled);
    state = AutostartState(support: state.support, enabled: enabled);
    return true;
  }
}

Future<ProviderContainer> pump(
  WidgetTester tester, {
  required bool trayUp,
  AutostartState autostart = const AutostartState(),
  FakeAutostart? fake,
}) async {
  final container = ProviderContainer(
    overrides: [
      trayAvailableProvider.overrideWith(() => FakeTray(trayUp)),
      autostartProvider.overrideWith(() => fake ?? FakeAutostart(autostart)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: TraySettingsSection(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Switch switchOf(WidgetTester tester, String key) => tester.widget<Switch>(
  find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Switch)),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('close-to-tray is off by default and can be turned on', (
    tester,
  ) async {
    final c = await pump(tester, trayUp: true);
    expect(
      find.text('Closing the window keeps Airclone running in the tray'),
      findsOneWidget,
    );
    expect(switchOf(tester, 'tray.closeToTray').value, isFalse);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tray.closeToTray')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.read(closeToTrayProvider), isTrue);
    expect(switchOf(tester, 'tray.closeToTray').value, isTrue);
  });

  testWidgets('no tray: the switch is disabled and says why', (tester) async {
    await pump(tester, trayUp: false);
    expect(switchOf(tester, 'tray.closeToTray').onChanged, isNull);
    expect(switchOf(tester, 'tray.closeToTray').value, isFalse);
    expect(find.textContaining('closing the window quits'), findsOneWidget);
  });

  testWidgets('minimize-to-tray is Windows only and needs a tray', (
    tester,
  ) async {
    final c = await pump(tester, trayUp: true);
    final row = find.byKey(const ValueKey('tray.minimizeToTray'));
    if (!HostPlatform.isWindows) {
      expect(row, findsNothing);
      return;
    }
    expect(row, findsOneWidget);
    expect(switchOf(tester, 'tray.minimizeToTray').value, isFalse);
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(c.read(minimizeToTrayProvider), isTrue);
    expect(switchOf(tester, 'tray.minimizeToTray').value, isTrue);
    c.read(trayAvailableProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(switchOf(tester, 'tray.minimizeToTray').onChanged, isNull);
    expect(switchOf(tester, 'tray.minimizeToTray').value, isFalse);
  });

  testWidgets('sign-in launch: a switch when supported', (tester) async {
    final fake = FakeAutostart(
      const AutostartState(support: AutostartSupport.supported()),
    );
    await pump(tester, trayUp: true, fake: fake);
    expect(find.byKey(const ValueKey('tray.autostart')), findsOneWidget);
    expect(switchOf(tester, 'tray.autostart').value, isFalse);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tray.autostart')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(fake.calls, [true]);
    expect(switchOf(tester, 'tray.autostart').value, isTrue);
  });

  testWidgets('sign-in launch: the reason when not offered', (tester) async {
    await pump(
      tester,
      trayUp: true,
      autostart: const AutostartState(
        support: AutostartSupport.unsupported('Snap builds cannot.'),
      ),
    );
    expect(find.byKey(const ValueKey('tray.autostart')), findsNothing);
    expect(
      find.text('Starting at sign-in is not offered here. Snap builds cannot.'),
      findsOneWidget,
    );
  });
}
