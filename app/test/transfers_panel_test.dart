import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/state/jobs_controller.dart';
import 'package:airclone/src/state/pane_layout.dart';
import 'package:airclone/src/state/stats_controller.dart';
import 'package:airclone/src/ui/jobs_dock.dart';
import 'package:airclone/src/ui/jobs_panel.dart';
import 'package:airclone/src/ui/stats_panel.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// "The transfers list is compacted and hard to see all the on-going transfers
/// … I couldn't resize it."
///
/// Two separate causes, one per group below:
///  * the live per-file strip was pinned in a HARD 100px box, so making the
///    dock taller grew everything EXCEPT the list of files actually moving;
///  * a job moving more files than the row shows ended in a dead "+N more"
///    label with no way to see the rest.
List<TransferItem> _files(int n) => [
  for (var i = 0; i < n; i++)
    TransferItem(name: 'file-$i.bin', percentage: i, speed: 1000, size: 4096),
];

/// The real controllers poll on a 1s timer that `pumpAndSettle` would never
/// drain; these hold a fixed snapshot instead.
class _FakeStats extends StatsController {
  _FakeStats(this._stats);
  final CoreStats _stats;
  @override
  CoreStats build() => _stats;
}

class _FakeJobs extends JobsController {
  _FakeJobs(this._jobs);
  final List<Job> _jobs;
  @override
  List<Job> build() => _jobs;
}

void main() {
  group('live file strip', () {
    Future<double> heightIn(WidgetTester tester, double available) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statsProvider.overrideWith(
              () => _FakeStats(CoreStats(transferring: _files(12))),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: available),
                  child: const StatsPanel(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byType(StatsPanel)).height;
    }

    testWidgets('grows into the height the dock gives it', (tester) async {
      final short = await heightIn(tester, 100);
      final tall = await heightIn(tester, 400);

      // The whole point of the fix: a taller dock shows more in-flight files.
      expect(tall, greaterThan(short));
      expect(short, lessThanOrEqualTo(100));
      expect(tall, lessThanOrEqualTo(400));
    });

    testWidgets('never overflows the height it is given', (tester) async {
      // 40 files in a 120px slot: it must scroll, not paint past its box.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statsProvider.overrideWith(
              () => _FakeStats(CoreStats(transferring: _files(40))),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: const StatsPanel(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(StatsPanel)).height,
        lessThanOrEqualTo(120),
      );
      expect(find.byType(Scrollbar), findsOneWidget);
    });
  });

  group('the dock itself', () {
    /// The real bottom dock, at the heights the shell actually gives it: the
    /// default 240, the floor, and the tallest a drag allows. A RenderFlex that
    /// overflows surfaces as an exception here, which is the whole point — the
    /// tab strip is a hard 30px and everything in it has to fit that.
    Future<void> pumpDock(WidgetTester tester, double height) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statsProvider.overrideWith(
              () => _FakeStats(CoreStats(transferring: _files(9))),
            ),
            jobsControllerProvider.overrideWith(
              () => _FakeJobs([
                Job(
                  id: 1,
                  type: JobType.copy,
                  source: 'drive:photos',
                  dest: 's3:backup',
                  transferring: _files(9),
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: SizedBox.expand()),
                  SizedBox(
                    height: height,
                    child: JobsDock(atMaxHeight: false, onToggleHeight: () {}),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // (height, whether the live strip has room to appear at that height).
    // The floor and the default are the two heights the shell actually hands
    // the dock without a drag, so they are the two that must never overflow.
    for (final (height, strip) in <(double, bool)>[
      (kMinJobsDockHeight, false),
      (kDefaultJobsDockHeight, true),
      (460, true),
    ]) {
      testWidgets('lays out cleanly at ${height.toInt()}px', (tester) async {
        await pumpDock(tester, height);

        expect(tester.takeException(), isNull);
        expect(find.byType(JobsPanel), findsOneWidget);
        // At the dock's minimum there is no room for the strip's header plus a
        // file row, so every pixel goes to the job list rather than to a box
        // whose content cannot fit it.
        expect(find.byType(StatsPanel), strip ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('a taller dock gives the live strip more room', (tester) async {
      await pumpDock(tester, 240);
      final short = tester.getSize(find.byType(StatsPanel)).height;
      await pumpDock(tester, 460);
      final tall = tester.getSize(find.byType(StatsPanel)).height;

      expect(tall, greaterThan(short));
    });

    testWidgets('the chevron offers the height toggle', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            statsProvider.overrideWith(() => _FakeStats(const CoreStats())),
            jobsControllerProvider.overrideWith(() => _FakeJobs(const [])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                height: 240,
                child: JobsDock(
                  atMaxHeight: false,
                  onToggleHeight: () => toggled++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_up));
      expect(toggled, 1);
    });
  });

  group('per-job file list', () {
    Future<void> pumpJobs(WidgetTester tester, List<Job> jobs) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jobsControllerProvider.overrideWith(() => _FakeJobs(jobs)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: SizedBox(height: 600, child: JobsPanel()),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('"+N more" expands to every file and back', (tester) async {
      await pumpJobs(tester, [
        Job(
          id: 1,
          type: JobType.copy,
          source: 'a:',
          dest: 'b:',
          transferring: _files(7),
        ),
      ]);

      // Collapsed: three files, and an expander naming the rest.
      expect(find.text('file-0.bin'), findsOneWidget);
      expect(find.text('file-3.bin'), findsNothing);
      expect(find.text('+4 more — show all'), findsOneWidget);

      await tester.tap(find.text('+4 more — show all'));
      await tester.pump();

      expect(find.text('file-6.bin'), findsOneWidget);
      expect(find.text('Show fewer files'), findsOneWidget);

      await tester.tap(find.text('Show fewer files'));
      await tester.pump();
      expect(find.text('file-6.bin'), findsNothing);
    });

    testWidgets('a job at or under the cap gets no expander', (tester) async {
      await pumpJobs(tester, [
        Job(
          id: 1,
          type: JobType.copy,
          source: 'a:',
          dest: 'b:',
          transferring: _files(3),
        ),
      ]);

      expect(find.text('file-2.bin'), findsOneWidget);
      expect(find.textContaining('show all'), findsNothing);
    });
  });
}
