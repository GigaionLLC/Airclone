import 'dart:io';

import 'package:airclone/src/rclone/models/mount_info.dart';
import 'package:airclone/src/rclone/models/mount_options.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/mount_controller.dart';
import 'package:airclone/src/state/mount_point.dart';
import 'package:airclone/src/state/mount_policy.dart';
import 'package:airclone/src/state/remotes_provider.dart';
import 'package:airclone/src/ui/mount_panel.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The mount dialog offered drive letters on every platform, and rclone honours
/// those on Windows only, so mounting never worked on Linux or macOS through the
/// app. Proven on real Linux: "*" and "D:" fail with "cannot open", a folder
/// mounts (linux-runner.yml, mount-probe).
///
/// These run on whatever the test host is. That is deliberate rather than a
/// gap: `flutter test` runs on Windows for a developer here and on ubuntu-latest
/// in ci.yml, so each environment exercises the branch its own platform takes.
/// The Linux-only test is marked SKIPPED on Windows, not passed - a test that
/// returns early and reports success is how three hollow tests got through
/// earlier in this same change.
class _RecordingMounts extends MountController {
  final List<String> mountPoints = [];

  // The real build() starts a poll timer pumpAndSettle would never drain.
  @override
  List<MountInfo> build() => const [];

  @override
  Future<String> mount({
    required String fs,
    required String mountPoint,
    MountOptions options = MountOptions.defaults,
  }) async {
    mountPoints.add(mountPoint);
    return mountPoint;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _RecordingMounts mounts;

  Future<void> pumpDialog(WidgetTester tester) async {
    mounts = _RecordingMounts();
    final container = ProviderContainer(
      overrides: [
        mountEnabledProvider.overrideWithValue(true),
        mountControllerProvider.overrideWith(() => mounts),
        mountTypesProvider.overrideWith((ref) async => const ['mount']),
        remotesProvider.overrideWith(
          (ref) async => const [
            Remote(name: 'drive', type: 'drive', fs: 'drive:'),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMountDialog(context),
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

  testWidgets('the dialog offers the kind of mount point this platform takes', (
    tester,
  ) async {
    await pumpDialog(tester);
    if (mountsOntoDriveLetters(windows: Platform.isWindows)) {
      expect(find.text('Drive'), findsOneWidget);
      expect(find.text('Folder'), findsNothing);
    } else {
      expect(find.text('Folder'), findsOneWidget);
      expect(
        find.text('Drive'),
        findsNothing,
        reason: 'a drive letter is exactly what failed on Linux',
      );
    }
  });

  /// The regression itself: pressing Mount off Windows sends a FOLDER, never
  /// "*" and never a drive letter, and the folder exists by the time rclone is
  /// asked - because rclone stats it and will not create it.
  testWidgets(
    'off Windows, Mount sends an existing folder, never "*" or a letter',
    (tester) async {
      final home = Platform.environment['HOME']!;
      // A throwaway folder under HOME, because the folder rules refuse /tmp on
      // purpose, and removed afterwards so a Linux developer's home is not left
      // with test litter.
      final root = Directory('$home/.airclone-mount-test-$pid');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final target = '${root.path}/mnt';

      await pumpDialog(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('drive').last);
      await tester.pumpAndSettle();

      // Picking the remote fills in the default folder. Finding the field BY
      // that text both locates it exactly and proves the default was applied -
      // an empty folder field is what a user would otherwise have to fill in
      // before a first mount could work at all.
      final defaultFolder = defaultMountFolder(home: home, fs: 'drive:');
      final folderField = find.widgetWithText(TextField, defaultFolder);
      expect(
        folderField,
        findsOneWidget,
        reason: 'default folder not filled in',
      );

      await tester.enterText(folderField, target);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Mount'));
        // prepareMountFolder touches the real disk, which fake async will not
        // advance; let it finish in real time.
        for (var i = 0; i < 50 && mounts.mountPoints.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();

      expect(mounts.mountPoints, [target]);
      expect(mounts.mountPoints.single, isNot('*'));
      expect(mounts.mountPoints.single, isNot(matches(RegExp(r'^[A-Z]:$'))));
      expect(
        Directory(target).existsSync(),
        isTrue,
        reason: 'rclone requires the folder to exist and will not create it',
      );
    },
    skip: Platform.isWindows,
  );
}
