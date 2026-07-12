import 'package:airclone/src/rclone/http_rclone_client.dart';
import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/console/console_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/remotes_provider.dart';
import 'package:airclone/src/state/settings_controller.dart';
import 'package:airclone/src/ui/console_pane.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Regression guard for the console focus bug: typing opened the suggestion
/// popover as a conditional, unkeyed sibling directly above the input, so
/// Flutter re-matched the Column children by position and repurposed the input's
/// element as the popover — tearing down the TextField and dropping its focus,
/// which then emptied the (hasFocus-gated) suggestions and removed the popover: a
/// thrash that read as "I typed and suddenly couldn't type." Stable keys pin each
/// child's identity so the input keeps its element (and focus) across the change.
class _FakeSettings extends SettingsController {
  @override
  SettingsState build() => const SettingsState();
}

class _FakeHttp extends HttpRcloneClient {
  _FakeHttp() : super(rclonePath: 'rclone');
  @override
  Future<Stream<String>> commandStream(
    String command,
    List<String> args,
  ) async => const Stream.empty();
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._c);
  final _FakeHttp _c;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _c);
}

/// The console controller listens to jobsControllerProvider on build, whose real
/// build() starts a 1s poll Timer that pumpAndSettle would never drain. This fake
/// yields the same empty list without the timer.
class _FakeJobs extends JobsController {
  @override
  List<Job> build() => const [];
}

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        engineControllerProvider.overrideWith(() => _FakeEngine(_FakeHttp())),
        settingsControllerProvider.overrideWith(() => _FakeSettings()),
        jobsControllerProvider.overrideWith(() => _FakeJobs()),
        remotesProvider.overrideWith((ref) async => const <Remote>[]),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ConsolePane(consoleId: 'test')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'opening the suggestion popover keeps the input element + focus',
    (tester) async {
      await pump(tester);

      // No text yet → no popover; the field is autofocused.
      expect(find.byType(TextField), findsOneWidget);
      final before = tester.element(find.byType(TextField));

      await tester.enterText(find.byType(TextField), 'ls');
      await tester.pumpAndSettle();

      // The popover opened (a real suggestion for "ls")…
      expect(find.text('lsjson'), findsOneWidget);
      // …and the input is the SAME element — NOT reparented by the popover — so
      // its focus survived. (Before the keys fix this was a different element.)
      final after = tester.element(find.byType(TextField));
      expect(
        after,
        same(before),
        reason: 'input element must not be reparented',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
        reason: 'input must keep focus when the popover opens',
      );
    },
  );

  testWidgets(
    'closing the popover (clearing text) also keeps the input element',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'ls');
      await tester.pumpAndSettle();
      final withPopover = tester.element(find.byType(TextField));

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.text('lsjson'), findsNothing);
      expect(tester.element(find.byType(TextField)), same(withPopover));
    },
  );

  testWidgets(
    'Up/Down recall command history on an empty prompt (terminal-style)',
    (tester) async {
      final container = await pump(tester);
      // Populate history via the controller (run() records each command). Settle
      // between runs so the first command's stream drains (running → false) —
      // otherwise the second run() early-returns and never reaches history.
      final ctrl = container.read(consoleControllerProvider('test').notifier);
      for (final cmd in ['about gdrive:', 'size s3:b']) {
        ctrl.setDraft(cmd);
        await ctrl.run();
        await tester.pumpAndSettle();
      }

      String text() =>
          tester.widget<TextField>(find.byType(TextField)).controller!.text;

      // The empty prompt shows no popover, so the arrows drive history.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(text(), '');
      expect(
        find.text('size s3:b'),
        findsNothing,
        reason: 'no popover on empty',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(text(), 'size s3:b', reason: 'newest first');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(text(), 'about gdrive:', reason: 'older');

      // Bottoming out doesn't wrap.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(text(), 'about gdrive:');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(text(), 'size s3:b', reason: 'back toward newer');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(text(), '', reason: 'past the newest restores the (empty) draft');
    },
  );
}
