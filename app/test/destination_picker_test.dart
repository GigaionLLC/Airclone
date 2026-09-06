import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/local_locations.dart';
import 'package:airclone/src/state/remotes_provider.dart';
import 'package:airclone/src/ui/destination_picker.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Copy to / Move to doesn't show the option to copy to one of the internal or
/// local drives."
///
/// The picker listed `remotesProvider` alone — the rclone remotes plus one
/// synthetic home folder — so a local disk sitting in the sidebar two inches
/// away could not be chosen as a destination at all. The only way through was to
/// navigate a pane there by hand and paste.
LocalLocation _loc(String name, String fs, LocalKind kind) => LocalLocation(
  remote: Remote(name: name, type: 'local', fs: fs, isLocal: true),
  kind: kind,
);

class _FakeLocations extends UserLocations {
  _FakeLocations(this._items);
  final List<LocalLocation> _items;
  // The real build() hits SharedPreferences and seeds defaults.
  @override
  List<LocalLocation> build() => _items;
}

void main() {
  final drives = [
    _loc('Disk (C:)', 'C:/', LocalKind.drive),
    _loc('Disk (D:)', 'D:/', LocalKind.drive),
  ];
  final locations = [
    _loc('Documents', 'C:/Users/x/Documents', LocalKind.folder),
  ];
  const cloud = [Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:')];

  Future<void> pump(
    WidgetTester tester, {
    List<LocalLocation>? withDrives,
    List<LocalLocation>? withLocations,
    bool cloudFails = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          drivesProvider.overrideWithValue(withDrives ?? drives),
          userLocationsProvider.overrideWith(
            () => _FakeLocations(withLocations ?? locations),
          ),
          remotesProvider.overrideWith(
            (ref) async => cloudFails ? throw Exception('engine down') : cloud,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDestinationPicker(context),
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

  testWidgets('offers local disks and saved folders, not just remotes', (
    tester,
  ) async {
    await pump(tester);

    // The bug, directly: these were absent entirely.
    expect(find.text('Disk (C:)'), findsOneWidget);
    expect(find.text('Disk (D:)'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    // And the remotes are still there.
    expect(find.text('gdrive'), findsOneWidget);
  });

  testWidgets('groups them the way the sidebar does', (tester) async {
    await pump(tester);

    // Same three section names as the sidebar, so the dialog does not invent a
    // second vocabulary for the same things.
    expect(find.text('LOCATIONS'), findsOneWidget);
    expect(find.text('DISKS'), findsOneWidget);
    expect(find.text('CLOUD'), findsOneWidget);
  });

  testWidgets('a broken engine still leaves the local disks usable', (
    tester,
  ) async {
    // Local disks need no engine. Losing the cloud section is bad; losing the
    // whole dialog with it would strand a copy that never needed rclone.
    await pump(tester, cloudFails: true);

    expect(find.text('Disk (C:)'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('gdrive'), findsNothing);
  });

  testWidgets('an empty section is omitted rather than shown empty', (
    tester,
  ) async {
    await pump(tester, withLocations: const []);

    expect(find.text('LOCATIONS'), findsNothing);
    expect(find.text('DISKS'), findsOneWidget);
  });

  testWidgets('with nothing at all it says so instead of showing headers', (
    tester,
  ) async {
    await pump(tester, withDrives: const [], withLocations: const []);

    expect(find.text('DISKS'), findsNothing);
    expect(find.text('CLOUD'), findsOneWidget); // gdrive still resolves
    expect(find.text('gdrive'), findsOneWidget);
  });
}
