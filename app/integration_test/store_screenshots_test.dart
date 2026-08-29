import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:airclone/main.dart' as app;

/// Drives the real app on a simulator and captures App Store screenshots.
///
/// Why this rather than tapping the Simulator window with `cliclick`, the way
/// the Mac rig drives the desktop app: on a simulator the target moves. Device
/// bezels, window zoom and title-bar height all shift where a device point lands
/// on screen, and none of them are reported anywhere convenient. Driving from
/// inside the app finds widgets by what they SAY, which does not move.
///
/// It is deliberately TOLERANT. A screenshot run that fails because one tap
/// missed is worth much less than one that captures whatever it reached and says
/// what it could not find - the pictures are the deliverable, and a partial set
/// is still a set. Every navigation step is best-effort; only the captures are
/// mandatory.
///
/// The demo content (a "Demo Cloud" alias remote and real CC0 photographs) is
/// seeded into the app container by `ios-screenshots.yml` before this runs.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App Store screenshots', (tester) async {
    app.main(const <String>[]);

    // NOT pumpAndSettle: the engine starts asynchronously and the app shows a
    // progress indicator while it does, which never settles. Pump real time
    // instead and let the frames arrive.
    Future<void> settle([int seconds = 3]) async {
      for (var i = 0; i < seconds * 2; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    await settle(12); // engine start + first listing

    // What does the APP see? The rig seeds photographs into the container and
    // the browser still renders "Empty folder" - which is a completed listing
    // with zero entries, not a load in progress. Every theory about why has been
    // wrong so far, so ask the process that actually has the sandbox view rather
    // than inferring from outside it.
    try {
      final docs = await getApplicationDocumentsDirectory();
      final support = await getApplicationSupportDirectory();
      final conf = File('${support.path}/rclone.conf');
      debugPrint('PROBE docs=${docs.path}');
      debugPrint('PROBE docsExists=${docs.existsSync()}');
      if (docs.existsSync()) {
        final names = docs
            .listSync()
            .map((e) => e.path.split('/').last)
            .toList();
        debugPrint('PROBE docsEntries=$names');
      }
      debugPrint('PROBE confExists=${conf.existsSync()}');
      if (conf.existsSync()) {
        final lines = conf.readAsLinesSync();
        debugPrint('PROBE conf=${lines.join(" | ")}');
      }
    } catch (e) {
      debugPrint('PROBE failed: $e');
    }

    // Required once on iOS before the surface can be read back.
    await binding.convertFlutterSurfaceToImage();

    Future<void> shot(String name) async {
      await settle(2);
      await binding.takeScreenshot(name);
    }

    /// Tap the first widget matching [finder], if there is one. Returns whether
    /// it found anything, so the caller can report an honest gap.
    Future<bool> tapIfPresent(Finder finder, {int settleSeconds = 3}) async {
      final found = finder.evaluate().isNotEmpty;
      if (found) {
        await tester.tap(finder.first, warnIfMissed: false);
        await settle(settleSeconds);
      }
      return found;
    }

    final missed = <String>[];

    await shot('01-home');

    // Into the seeded remote. Both shells show it by name.
    if (await tapIfPresent(find.text('Demo Cloud'), settleSeconds: 4)) {
      await shot('02-remote');

      // ...and into the photographs, which is the shot worth having.
      if (await tapIfPresent(find.text('Photos'), settleSeconds: 5)) {
        await shot('03-photos');

        // Gallery view renders real thumbnails rather than a list of names.
        final gallery = find.byTooltip('Gallery');
        if (await tapIfPresent(gallery, settleSeconds: 6)) {
          await shot('04-gallery');
        } else if (await tapIfPresent(find.text('Gallery'), settleSeconds: 6)) {
          await shot('04-gallery');
        } else {
          missed.add('gallery view toggle');
        }
      } else {
        missed.add('Photos folder');
      }
    } else {
      missed.add('Demo Cloud remote');
    }

    // Back out to the sidebar first. On the phone shell the browser replaces it,
    // so "On My Device" is simply not on screen after opening a remote - which is
    // why iPad captured this shot and iPhone reported it missing. iPad keeps the
    // sidebar visible, so the back tap is a harmless no-op there.
    for (var i = 0; i < 3; i++) {
      if (find.text('On My Device').evaluate().isNotEmpty) break;
      if (!await tapIfPresent(
        find.byIcon(Icons.arrow_back),
        settleSeconds: 2,
      )) {
        break;
      }
    }

    // The local side: the app's own Documents folder, which is the whole of
    // "local" on iOS and worth showing because it is what Files exposes.
    if (await tapIfPresent(find.text('On My Device'), settleSeconds: 4)) {
      await shot('05-on-my-device');
    } else {
      missed.add('On My Device location');
    }

    if (missed.isNotEmpty) {
      // Printed, not thrown. A partial set of real screenshots beats a failed
      // run with none, and the log says exactly what was not reached.
      debugPrint('SCREENSHOT GAPS: ${missed.join(', ')}');
    }
  });
}
