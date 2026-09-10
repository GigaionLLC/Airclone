import 'package:airclone/src/state/android_work_channel.dart';
import 'package:airclone/src/state/android_work_registration.dart';
import 'package:airclone/src/state/android_work_settings.dart';
import 'package:airclone/src/state/task_schedule.dart';
import 'package:airclone/src/state/tasks_controller.dart';
import 'package:airclone/src/state/transfer_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pure half of Android background execution: whether the one periodic
/// WorkManager request should exist, at what cadence, and what Settings says
/// about it. The platform half (WorkChannel.kt / DueTasksWorker.kt) is
/// verified on an emulator, not here.
void main() {
  TransferTask task({TaskSchedule? schedule, bool runWhileClosed = false}) =>
      TransferTask(
        id: 't',
        name: 't',
        srcFs: 'a:',
        srcLabel: 'a',
        dstFs: 'b:',
        dstLabel: 'b',
        options: const TransferOptions(),
        schedule: schedule,
        runWhileClosed: runWhileClosed,
      );
  const daily = TaskSchedule(kind: ScheduleKind.daily);

  group('androidWorkIntervalFor', () {
    test('never goes below the 15-minute floor Android enforces anyway', () {
      expect(androidWorkIntervalFor(5), 15);
      expect(androidWorkIntervalFor(10), 15);
      expect(androidWorkIntervalFor(15), 15);
    });

    test('passes a sane cadence through unchanged', () {
      expect(androidWorkIntervalFor(30), 30);
      expect(androidWorkIntervalFor(60), 60);
    });
  });

  group('androidWorkDesired', () {
    test('nothing scheduled: no wake', () {
      expect(
        androidWorkDesired(
          tasks: [(schedule: null, runWhileClosed: true)],
          optInOffered: false,
        ),
        isFalse,
      );
      expect(androidWorkDesired(tasks: const [], optInOffered: false), isFalse);
    });

    test('while the opt-in is not offered, every schedule counts', () {
      // The checkbox was never shown, so it cannot be why a backup did not run.
      expect(
        androidWorkDesired(
          tasks: [(schedule: daily, runWhileClosed: false)],
          optInOffered: false,
        ),
        isTrue,
      );
    });

    test('once the opt-in is offered, it is honoured', () {
      expect(
        androidWorkDesired(
          tasks: [(schedule: daily, runWhileClosed: false)],
          optInOffered: true,
        ),
        isFalse,
      );
      expect(
        androidWorkDesired(
          tasks: [
            (schedule: daily, runWhileClosed: false),
            (schedule: daily, runWhileClosed: true),
          ],
          optInOffered: true,
        ),
        isTrue,
      );
    });
  });

  group('planAndroidWork', () {
    test('carries the clamped cadence and the constraints', () {
      final plan = planAndroidWork(
        tasks: [task(schedule: daily)],
        constraints: const AndroidWorkConstraints(
          unmetered: false,
          charging: true,
        ),
        pollMinutes: 5,
        optInOffered: false,
      );
      expect(plan.desired, isTrue);
      expect(plan.intervalMinutes, 15);
      expect(plan.constraints.unmetered, isFalse);
      expect(plan.constraints.charging, isTrue);
    });

    test('two plans from the same inputs are equal, so a no-op is skipped', () {
      AndroidWorkPlan make() => planAndroidWork(
        tasks: [task(schedule: daily)],
        constraints: const AndroidWorkConstraints(),
        pollMinutes: 30,
        optInOffered: false,
      );
      expect(make(), make());
      expect(
        make(),
        isNot(
          planAndroidWork(
            tasks: [task(schedule: daily)],
            constraints: const AndroidWorkConstraints(charging: true),
            pollMinutes: 30,
            optInOffered: false,
          ),
        ),
      );
    });
  });

  group('androidWorkExplanation', () {
    test('says nothing is registered when nothing is scheduled', () {
      final plan = planAndroidWork(
        tasks: const [],
        constraints: const AndroidWorkConstraints(),
        pollMinutes: 15,
        optInOffered: false,
      );
      expect(androidWorkExplanation(plan), contains('Nothing is scheduled'));
    });

    test('names the cadence and every constraint in force', () {
      final plan = planAndroidWork(
        tasks: [task(schedule: daily)],
        constraints: const AndroidWorkConstraints(
          unmetered: true,
          charging: true,
        ),
        pollMinutes: 30,
        optInOffered: false,
      );
      final text = androidWorkExplanation(plan);
      expect(text, contains('every 30 minutes'));
      expect(text, contains('on Wi-Fi'));
      expect(text, contains('while charging'));
      expect(text, contains('even with the app closed'));
    });

    test('omits constraints that are off', () {
      final plan = planAndroidWork(
        tasks: [task(schedule: daily)],
        constraints: const AndroidWorkConstraints(
          unmetered: false,
          charging: false,
        ),
        pollMinutes: 15,
        optInOffered: false,
      );
      final text = androidWorkExplanation(plan);
      expect(text, isNot(contains('Wi-Fi')));
      expect(text, isNot(contains('charging')));
    });
  });

  group('AndroidWorkConstraints', () {
    test('Wi-Fi-only is the default; charging is not', () {
      const c = AndroidWorkConstraints();
      expect(c.unmetered, isTrue);
      expect(c.charging, isFalse);
    });
  });

  group('AndroidWorkStatus.fromMap', () {
    test('reads the platform map, absent keys meaning never', () {
      final s = AndroidWorkStatus.fromMap({
        'enqueued': true,
        'state': 'ENQUEUED',
        'nextRunAt': 1000,
        'lastExitCode': 1,
      });
      expect(s.enqueued, isTrue);
      expect(s.state, 'ENQUEUED');
      expect(s.nextRunAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(s.lastRunAt, isNull);
      expect(s.lastExitCode, 1);
    });
  });
}
