import 'package:airclone/src/state/photo_backup.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/ui/photo_backup_section.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The photo-backup setup dialog, pumped at PHONE size. Every dialog in this
/// app used to be a fixed desktop width and clipped its action buttons at
/// 375dp — which is how "Import File Config" looked broken on Android. This
/// pins that the one flow that only exists on a phone actually fits on one.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    TransferTask? existing,
  }) async {
    // Pixel-ish phone: 375 x 812 logical.
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (existing != null) {
      container.read(tasksProvider.notifier).add(existing);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showPhotoBackupDialog(ctx, existing: existing),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('fits a phone: no overflow, camera roll pre-filled, videos on', (
    tester,
  ) async {
    await pump(tester);
    expect(tester.takeException(), isNull, reason: 'overflow = clipped button');
    expect(find.text('Back up your photos'), findsOneWidget);
    expect(find.text('Camera roll'), findsOneWidget);
    expect(find.text('Include videos'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Include videos'),
          )
          .value,
      isTrue,
    );
    // The primary action is on screen, not drawn past the edge.
    final start = find.widgetWithText(FilledButton, 'Start backing up');
    expect(start, findsOneWidget);
    final rect = tester.getRect(start);
    expect(rect.right, lessThanOrEqualTo(375));
    expect(rect.bottom, lessThanOrEqualTo(812));
  });

  testWidgets('refuses to save without a destination, and says why', (
    tester,
  ) async {
    final container = await pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Start backing up'));
    await tester.pumpAndSettle();
    expect(find.text('Choose where to keep the photos first.'), findsOneWidget);
    expect(find.text('Back up your photos'), findsOneWidget); // still open
    expect(container.read(tasksProvider), isEmpty);
  });

  testWidgets('editing: removing a folder and toggling videos saves in place', (
    tester,
  ) async {
    final existing = buildPhotoBackupTask(
      storageRoot: '/storage/emulated/0',
      spec: const PhotoBackupSpec(
        folders: ['DCIM', 'Pictures/Screenshots'],
        includeVideos: true,
      ),
      dstFs: 'gdrive:Airclone/Photos/Pixel 7',
    );
    final container = await pump(tester, existing: existing);
    expect(tester.takeException(), isNull);
    expect(find.text('Edit photo backup'), findsOneWidget);
    expect(find.text('gdrive:Airclone/Photos/Pixel 7'), findsOneWidget);
    expect(find.text('Pictures/Screenshots'), findsOneWidget);

    // Drop the extra folder via its chip (its only icon is the delete one),
    // turn videos off, save.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InputChip, 'Pictures/Screenshots'),
        matching: find.byType(Icon),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Include videos'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final tasks = container.read(tasksProvider);
    expect(tasks, hasLength(1), reason: 'updated in place, not duplicated');
    expect(tasks.single.id, existing.id);
    final spec = photoBackupSpecOf(tasks.single)!;
    expect(spec.folders, ['DCIM']);
    expect(spec.includeVideos, isFalse);
    expect(tasks.single.dstFs, existing.dstFs, reason: 'kept, not re-picked');
  });
}
