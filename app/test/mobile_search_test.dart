import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/remotes_provider.dart';
import 'package:airclone/src/ui/mobile_home.dart';
import 'package:airclone/src/ui/pane_search_box.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:shared_preferences/shared_preferences.dart';

class _Client implements RcloneClient {
  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'operations/list') {
      return {
        'list': [
          {'Name': 'holiday.mp4', 'Path': 'holiday.mp4', 'IsDir': false},
          {'Name': 'work.txt', 'Path': 'work.txt', 'IsDir': false},
        ],
      };
    }
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends EngineController {
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _Client());
}

const _remote = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');

/// The phone (and TV) shell: the header's search icon opens the box in the
/// title's place, and the system Back button steps out of the search before it
/// navigates anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('search icon opens the box; Back clears it step by step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        engineControllerProvider.overrideWith(_FakeEngine.new),
        remotesProvider.overrideWith((ref) => const [_remote]),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MobileHomeScreen(),
        ),
      ),
    );
    final ctrl = container.read(browserAProvider.notifier);
    await ctrl.open(_remote);
    await ctrl.navigateTo('Movies');
    await tester.pumpAndSettle();
    expect(find.byType(PaneSearchBox), findsNothing);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(PaneSearchBox), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'holi');
    await tester.pumpAndSettle();
    expect(find.text('holiday.mp4'), findsOneWidget);
    expect(find.text('work.txt'), findsNothing);
    expect(find.text('Search subfolders for "holi"'), findsOneWidget);

    // Back #1 clears the text, #2 closes the box, #3 finally goes up.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(browserAProvider).filter, isEmpty);
    expect(find.byType(PaneSearchBox), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PaneSearchBox), findsNothing);
    expect(container.read(browserAProvider).path, 'Movies');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(browserAProvider).path, isEmpty);
  });
}
