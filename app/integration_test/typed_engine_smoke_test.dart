import 'dart:io';

import 'package:airclone/main.dart' as app;
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Boots the REAL app with the REAL engine and checks the whole chain the
/// `airclone_rc` split and the typed API run through: engine start → typed rc
/// calls → app state → rendered widgets.
///
/// Everything here is read-only apart from a temp directory this test creates
/// and deletes itself. It never writes to a remote, and it never prints the
/// names of the remotes it finds - the config it reads belongs to whoever is
/// running it.
///
/// Run: `flutter test integration_test/typed_engine_smoke_test.dart -d windows`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the app comes up on the package and lists through the typed API',
    (tester) async {
      // A directory with known contents, so a listing assertion can be exact.
      final dir = await Directory.systemTemp.createTemp('airclone-gui-smoke');
      await File(
        '${dir.path}${Platform.pathSeparator}alpha.txt',
      ).writeAsString('a');
      await File(
        '${dir.path}${Platform.pathSeparator}beta.txt',
      ).writeAsString('bb');
      await Directory('${dir.path}${Platform.pathSeparator}gamma').create();

      app.main(const <String>[]);

      // NOT pumpAndSettle: the engine starts asynchronously behind a progress
      // indicator, which never settles. Pump real time instead.
      Future<void> settle([int seconds = 3]) async {
        for (var i = 0; i < seconds * 2; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
      }

      await settle(4);
      expect(
        find.byType(ProviderScope),
        findsOneWidget,
        reason: 'the app shell did not build',
      );

      // containerOf looks UP the tree, so it needs an element BELOW the scope -
      // handing it the ProviderScope's own element finds nothing.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp).first),
        listen: false,
      );

      // --- the engine, started by the package inside the real app -------------
      RcloneClient? client;
      for (var i = 0; i < 40 && client == null; i++) {
        await settle(1);
        client = container.read(engineControllerProvider).client;
      }
      expect(client, isNotNull, reason: 'the engine never produced a client');

      EngineStatus status = await client!.status();
      for (var i = 0; i < 20 && status.state != EngineState.running; i++) {
        await settle(1);
        status = await client.status();
      }
      expect(status.state, EngineState.running);
      expect(status.version, matches(RegExp(r'^v?\d+\.\d+\.\d+')));
      debugPrint('SMOKE engine: ${status.version}');

      // --- the typed API, against that live engine ---------------------------
      final api = RcApi(client);

      expect(await api.core.version(), matches(RegExp(r'^v?\d+\.\d+\.\d+')));
      expect(await api.core.stats(), isA<Map<String, dynamic>>());
      expect(await api.job.list(), isA<List<int>>());

      // Counted, never named: these are the user's own remotes.
      final remotes = await api.config.listRemotes();
      debugPrint('SMOKE remotes configured: ${remotes.length}');

      // The namespaces added for the typed API, answered by a real rclone.
      final mountTypes = await api.mount.types();
      final serveTypes = await api.serve.types();
      debugPrint(
        'SMOKE mount types: ${mountTypes.length}, '
        'serve types: ${serveTypes.length}',
      );
      expect(await api.mount.listMounts(), isA<List<MountInfo>>());
      expect(await api.serve.list(), isA<List<ServeServer>>());
      expect(await api.vfs.list(), isA<List<String>>());

      // The local backend is a filesystem like any other, so the temp directory
      // above is a complete end-to-end target with no network involved.
      final listed = await api.operations.list(dir.path, '');
      expect(listed.map((f) => f.name).toSet(), {
        'alpha.txt',
        'beta.txt',
        'gamma',
      }, reason: 'typed operations/list against the live engine');
      expect(listed.firstWhere((f) => f.name == 'beta.txt').size, 2);
      expect(listed.firstWhere((f) => f.name == 'gamma').isDir, isTrue);

      final stat = await api.operations.stat(dir.path, 'alpha.txt');
      expect(stat?.size, 1);
      expect(
        await api.operations.fsInfo(dir.path),
        isA<Map<String, dynamic>>(),
      );
      // 2, not 3: operations/size counts OBJECTS, and a directory is not one.
      expect((await api.operations.size(dir.path))['count'], 2);

      // listOrNull answers for a directory that exists, and the distinction it
      // exists for: null when there is no listing in the answer at all.
      expect(await api.operations.listOrNull(dir.path, ''), isNotNull);

      // --- the GUI, rendering what a typed listing produced ------------------
      final remote = Remote(
        name: 'Smoke dir',
        type: 'local',
        fs: dir.path,
        isLocal: true,
      );
      await container.read(browserAProvider.notifier).open(remote);
      await settle(6);

      final state = container.read(browserAProvider);
      expect(state.entries.map((f) => f.name).toSet(), {
        'alpha.txt',
        'beta.txt',
        'gamma',
      }, reason: 'the browser pane state after a real listing');

      // And the widgets actually show them - the point of the whole exercise.
      expect(find.text('alpha.txt'), findsWidgets);
      expect(find.text('beta.txt'), findsWidgets);
      expect(find.text('gamma'), findsWidgets);
      debugPrint('SMOKE the pane rendered ${state.entries.length} entries');

      // Navigating into the subdirectory goes through the same path again.
      await container.read(browserAProvider.notifier).navigateTo('gamma');
      await settle(4);
      expect(container.read(browserAProvider).path, 'gamma');
      expect(container.read(browserAProvider).entries, isEmpty);

      await dir.delete(recursive: true);
    },
  );
}
