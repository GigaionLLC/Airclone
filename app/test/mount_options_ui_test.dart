import 'package:airclone/src/rclone/models/mount_info.dart';
import 'package:airclone/src/rclone/models/mount_options.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/mount_controller.dart';
import 'package:airclone/src/state/mount_defaults.dart';
import 'package:airclone/src/state/mount_policy.dart';
import 'package:airclone/src/state/remotes_provider.dart';
import 'package:airclone/src/ui/mount_options_editor.dart';
import 'package:airclone/src/ui/mount_panel.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mount options live in two places — Settings holds the defaults, the mount
/// dialog holds a transient copy for one mount — and that is exactly the shape
/// that becomes confusing if the relationship is not visible. These cover the
/// three promises that make it legible:
///
///  * the dialog SEEDS from the saved defaults;
///  * editing there does NOT write back to them;
///  * the collapsed line says when you are looking at a deviation, and offers
///    the way back.
class _FakeMounts extends MountController {
  // The real build() starts a 2s poll timer that pumpAndSettle would never
  // drain.
  @override
  List<MountInfo> build() => const [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpDialog(
    WidgetTester tester, {
    MountOptions? savedDefaults,
  }) async {
    final container = ProviderContainer(
      overrides: [
        mountEnabledProvider.overrideWithValue(true),
        mountControllerProvider.overrideWith(_FakeMounts.new),
        mountTypesProvider.overrideWith((ref) async => const ['mount']),
        remotesProvider.overrideWith(
          (ref) async => const [
            Remote(name: 'drive', type: 'drive', fs: 'drive:'),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    if (savedDefaults != null) {
      await container.read(mountDefaultsProvider.notifier).set(savedDefaults);
    }
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
    return container;
  }

  testWidgets('the collapsed line summarises what you are about to get', (
    tester,
  ) async {
    await pumpDialog(tester);

    // Not "Advanced" and nothing else: the state is readable without opening
    // it, which is the whole point of the affordance.
    expect(find.text('Tuning'), findsOneWidget);
    expect(find.text(MountOptions.defaults.summary), findsOneWidget);
    // Nothing to reset while it matches the defaults.
    expect(find.text('Reset to defaults'), findsNothing);
    // Collapsed by default — the common case never expands it.
    expect(find.byType(MountOptionsEditor), findsNothing);
  });

  testWidgets('it seeds from the SAVED defaults, not the shipped ones', (
    tester,
  ) async {
    final saved = MountOptions.defaults.copyWith(cacheMaxSize: '25Gi');
    await pumpDialog(tester, savedDefaults: saved);

    expect(find.text(saved.summary), findsOneWidget);
    // Seeded, therefore not a deviation — no count, no reset.
    expect(find.textContaining('changed)'), findsNothing);
    expect(find.text('Reset to defaults'), findsNothing);
  });

  testWidgets('editing marks a deviation and never touches the defaults', (
    tester,
  ) async {
    final container = await pumpDialog(tester);

    await tester.tap(find.text('Tuning'));
    await tester.pumpAndSettle();
    expect(find.byType(MountOptionsEditor), findsOneWidget);

    // Scoped to the editor on purpose: the dialog's own form has Remote and
    // Drive dropdowns before it, so a bare .at(1) would grab the wrong one.
    final cacheSize = find
        .descendant(
          of: find.byType(MountOptionsEditor),
          matching: find.byType(DropdownButtonFormField<String>),
        )
        .at(1);
    await tester.ensureVisible(cacheSize);
    await tester.pumpAndSettle();
    await tester.tap(cacheSize);
    await tester.pumpAndSettle();
    await tester.tap(find.text('25Gi').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('(1 changed)'), findsOneWidget);
    final reset = find.text('Reset to defaults');
    expect(reset, findsOneWidget);
    // The promise that makes two places safe: this mount changed, the defaults
    // did not.
    expect(container.read(mountDefaultsProvider), MountOptions.defaults);

    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    // Back to the defaults, and the deviation marker is gone. Asserted on the
    // exact summary rather than "contains changed" - the editor's own help text
    // says "whether a file changed", which a loose matcher would catch.
    expect(find.textContaining('(1 changed)'), findsNothing);
    expect(find.text(MountOptions.defaults.summary), findsOneWidget);
  });

  group('MountOptionsEditor', () {
    testWidgets('reports one field at a time, leaving the rest alone', (
      tester,
    ) async {
      MountOptions? got;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MountOptionsEditor(
                value: MountOptions.defaults,
                onChanged: (v) => got = v,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5Gi').last);
      await tester.pumpAndSettle();

      expect(got, isNotNull);
      expect(got!.cacheMaxSize, '5Gi');
      expect(got!.changedFrom(MountOptions.defaults), 1);
    });

    testWidgets('the cache size is disabled when nothing is cached', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MountOptionsEditor(
                value: MountOptions.defaults.copyWith(cacheMode: 'off'),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // A size cap on a mode that keeps no file cache would be a lie.
      final size = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).at(1),
      );
      expect(size.onChanged, isNull);
    });
  });

  group('MountDefaults', () {
    test('persists and reloads, and reset forgets the override', () async {
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      final tuned = MountOptions.defaults.copyWith(
        cacheMode: 'writes',
        networkMode: true,
      );
      await c1.read(mountDefaultsProvider.notifier).set(tuned);

      // A fresh container reads it back off disk.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(mountDefaultsProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c2.read(mountDefaultsProvider), tuned);

      await c2.read(mountDefaultsProvider.notifier).reset();
      expect(c2.read(mountDefaultsProvider), MountOptions.defaults);

      final prefs = await SharedPreferences.getInstance();
      // Removed, not overwritten: a later change to the SHIPPED defaults must
      // reach a user who has reset.
      expect(prefs.getString('mount_options_defaults'), isNull);
    });
  });
}
