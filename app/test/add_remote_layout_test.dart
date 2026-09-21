/// Every add-a-cloud screen, laid out at a real phone size.
///
/// Screen capture is impossible from a Claude Code desktop session, so layout
/// is verified by widget test rather than by looking. That is not a lesser
/// check here: the bug it exists to catch is a dialog laid out at a fixed
/// desktop width on a ~330dp phone, which draws its primary button past the
/// screen edge — the failure that made Android config import look broken while
/// the flow underneath it worked perfectly.
library;

import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/state/add_remote_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/providers_provider.dart';
import 'package:airclone/src/ui/add_remote_dialog.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

import 'support/config_flow_fixtures.dart';

/// iPhone-ish, and the narrowest thing this app is expected to render on.
const Size kPhone = Size(375, 812);
const Size kDesktop = Size(1400, 900);

class _QuietClient implements RcloneClient {
  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async => const <String, dynamic>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required Size size,
  required RcloneClient client,
  List<RcloneProvider> providers = const [],
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineControllerProvider.overrideWith(() => FakeEngine(client)),
        providersProvider.overrideWith((ref) async => providers),
        urlOpenerProvider.overrideWithValue((_) async => true),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAddRemoteDialog(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Scrolls until [finder] is on screen.
///
/// A ListView builds only what is visible, so a tile further down the picker
/// simply does not exist yet — which is correct behaviour and would otherwise
/// read as a missing widget.
Future<void> ensureVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    return;
  }
  // The scrollable is the CONTENT list, not whichever Scrollable happens to
  // come first: a TextField carries one of its own, and dragging that moves
  // nothing while looking like a search that came up empty.
  final inList = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  if (inList.evaluate().isEmpty) return;
  await tester.scrollUntilVisible(finder, 80, scrollable: inList.last);
  await tester.pumpAndSettle();
}

/// Taps a tile's Advanced action, which is a label where there is room and an
/// icon where there is not.
Future<void> tapAdvanced(WidgetTester tester) async {
  final icon = find.byTooltip('Advanced');
  if (icon.evaluate().isNotEmpty) {
    await tester.tap(icon.first);
  } else {
    await tester.tap(find.text('Advanced').first);
  }
  await tester.pumpAndSettle();
}

/// Types into the picker search box.
Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pumpAndSettle();
}

/// Fails if anything overflowed. Flutter reports overflow as an exception
/// during paint, which the test binding collects rather than throwing.
void expectNoOverflow(WidgetTester tester) {
  final error = tester.takeException();
  expect(error, isNull, reason: 'a widget overflowed its constraints: $error');
}

void main() {
  const s3 = RcloneProvider(
    name: 's3',
    description: 'Amazon S3 and compatible',
    options: [
      ProviderOption(name: 'provider'),
      ProviderOption(name: 'access_key_id', sensitive: true),
      ProviderOption(name: 'secret_access_key', sensitive: true),
      ProviderOption(name: 'region'),
      ProviderOption(name: 'endpoint'),
      ProviderOption(name: 'chunk_size', advanced: true),
      ProviderOption(name: 'upload_concurrency', advanced: true),
    ],
  );

  for (final (label, size) in <(String, Size)>[
    ('a phone', kPhone),
    ('a desktop window', kDesktop),
  ]) {
    group('on $label', () {
      testWidgets('the picker fits', (tester) async {
        await _pumpDialog(
          tester,
          size: size,
          client: _QuietClient(),
          providers: const [s3],
        );
        expect(find.text('Add a cloud'), findsOneWidget);
        // The curated tiles are what somebody should see first.
        expect(find.text('Google Drive'), findsOneWidget);
        await ensureVisible(tester, find.text('Backblaze B2'));
        expect(find.text('Backblaze B2'), findsOneWidget);
        expectNoOverflow(tester);
      });

      testWidgets('the guided essentials screen fits', (tester) async {
        await _pumpDialog(
          tester,
          size: size,
          client: _QuietClient(),
          providers: const [s3],
        );
        await search(tester, 'amazon');
        await tester.tap(find.text('Amazon S3'));
        await tester.pumpAndSettle();

        // The layout contract, which is what differs between the two sizes:
        // the heading and the action are both on screen, and nothing is drawn
        // past the edge. WHICH fields exist is a separate test below — no
        // phone shows five of them at once, and a list that scrolls is the
        // right answer rather than a failure.
        expect(find.text('Connect S3 storage'), findsOneWidget);
        expect(find.text('Connect'), findsOneWidget);
        expect(find.text('Name'), findsOneWidget);
        expectNoOverflow(tester);
      });

      testWidgets('the advanced form fits', (tester) async {
        await _pumpDialog(
          tester,
          size: size,
          client: _QuietClient(),
          providers: const [s3],
        );
        await search(tester, 'amazon');
        // Every tile carries its own way past the guide.
        await tapAdvanced(tester);
        expect(find.text('Create remote'), findsOneWidget);
        expectNoOverflow(tester);
      });
    });
  }

  testWidgets('the recipe decides which fields the guided screen shows', (
    tester,
  ) async {
    // The dialog is sized per step and the guided step is 540 tall by design,
    // so this checks the fields at the top of the recipe rather than all five
    // at once — the rest are one scroll away, which is the intended shape.
    await _pumpDialog(
      tester,
      size: const Size(900, 1400),
      client: _QuietClient(),
      providers: const [s3],
    );
    await search(tester, 'amazon');
    await tester.tap(find.text('Amazon S3'));
    await tester.pumpAndSettle();

    // Our words, not rclone's option names.
    expect(find.text('Service'), findsOneWidget);
    expect(find.text('Access key ID *'), findsOneWidget);
    expect(find.text('access_key_id'), findsNothing);

    // The key is obscured although rclone flags it `Sensitive` rather than
    // `IsPassword` — trusting that flag would paint a live credential on
    // screen, and a screenshot is a publishing channel.
    final key = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('guided-access_key_id')),
        matching: find.byType(TextField),
      ),
    );
    expect(key.obscureText, isTrue);
    expectNoOverflow(tester);
  });

  testWidgets('the option filter narrows a long list', (tester) async {
    await _pumpDialog(
      tester,
      size: kDesktop,
      client: _QuietClient(),
      providers: const [s3],
    );
    await search(tester, 'amazon');
    await tapAdvanced(tester);

    expect(
      find.byKey(const ValueKey('option-row-access_key_id')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('option-filter')),
      'endpoint',
    );
    await tester.pumpAndSettle();

    // Identified by key: the filter box itself now contains the word
    // "endpoint", so matching on text would match the search box too.
    expect(find.byKey(const ValueKey('option-row-endpoint')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('option-row-access_key_id')),
      findsNothing,
    );
    expectNoOverflow(tester);
  });

  testWidgets('a search alias reaches the right backend', (tester) async {
    await _pumpDialog(
      tester,
      size: kPhone,
      client: _QuietClient(),
      providers: const [s3],
    );
    await search(tester, 'wasabi');
    // Nobody should have to know that Wasabi is spelled "s3" in rclone.
    expect(find.text('Wasabi'), findsOneWidget);
    expect(find.text('Google Drive'), findsNothing);
    expectNoOverflow(tester);
  });

  group('the Google sign-in screens', () {
    testWidgets('the shared client_id choice fits on a phone', (tester) async {
      final client = TranscriptClient(ConfigFlow('drive_declines_shared_id'));
      tester.view.physicalSize = kPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineControllerProvider.overrideWith(() => FakeEngine(client)),
            providersProvider.overrideWith(
              (ref) async => [oauthProvider('drive')],
            ),
            urlOpenerProvider.overrideWithValue((_) async => true),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showAddRemoteDialog(ctx),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Drive'));
      await tester.pumpAndSettle();

      // The one primary button, with the alternatives a tap away.
      expect(find.byKey(const ValueKey('sign-in-primary')), findsOneWidget);
      expect(find.text('Other ways to sign in'), findsOneWidget);
      expectNoOverflow(tester);

      await tester.tap(find.byKey(const ValueKey('sign-in-primary')));
      await tester.pumpAndSettle();

      // rclone asks about the retiring shared client_id before OAuth, so this
      // is where the flow lands — and it says so in plain words.
      expect(find.byKey(const ValueKey('own-client-id')), findsOneWidget);
      expect(find.textContaining('retiring'), findsOneWidget);
      await ensureVisible(
        tester,
        find.byKey(const ValueKey('shared-client-id')),
      );
      expect(find.byKey(const ValueKey('shared-client-id')), findsOneWidget);
      expectNoOverflow(tester);

      await tester.tap(find.byKey(const ValueKey('own-client-id')));
      await tester.pumpAndSettle();

      // Both halves of the credential are obscured, although rclone flags
      // neither as a password.
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('own-client_id')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.obscureText, isTrue);
      expectNoOverflow(tester);
    });
  });
}
