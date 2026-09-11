import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'android_work_channel.dart';
import 'android_work_entrypoint.dart';
import 'android_work_settings.dart';
import 'host_platform.dart';
import 'poll_cadence.dart';
import 'scheduling_policy.dart';
import 'task_schedule.dart';
import 'tasks_controller.dart';

/// Android's floor for periodic work. WorkManager raises anything smaller
/// silently; clamping here means the number the UI shows is the one in force.
const int kAndroidWorkMinIntervalMinutes = 15;

/// The poll cadence Android will actually honour for [pollMinutes].
int androidWorkIntervalFor(int pollMinutes) =>
    pollMinutes < kAndroidWorkMinIntervalMinutes
    ? kAndroidWorkMinIntervalMinutes
    : pollMinutes;

/// Whether the periodic request should exist at all.
///
/// Every scheduled task on Android goes through the one shared poll — there
/// are no exact-time triggers to route a daily task to — so the question is
/// only "is anything scheduled that wants to run while the app is closed?".
///
/// [optInOffered] is whether this build shows "Also run while Airclone is
/// closed" (`canRunWhileClosed`). While it does not, every schedule counts:
/// on a phone "on a schedule" means "in the background", and a checkbox the
/// user was never shown cannot be the reason their backup did not run. Once a
/// build offers the opt-in, it is honoured, the same as on Windows.
bool androidWorkDesired({
  required Iterable<({TaskSchedule? schedule, bool runWhileClosed})> tasks,
  required bool optInOffered,
}) =>
    tasks.any((t) => t.schedule != null && (!optInOffered || t.runWhileClosed));

/// Everything WorkManager needs to be told, decided in one place so the
/// reconciler can compare plans and skip a no-op update.
@immutable
class AndroidWorkPlan {
  const AndroidWorkPlan({
    required this.desired,
    required this.intervalMinutes,
    required this.constraints,
  });

  final bool desired;
  final int intervalMinutes;
  final AndroidWorkConstraints constraints;

  @override
  bool operator ==(Object other) =>
      other is AndroidWorkPlan &&
      other.desired == desired &&
      other.intervalMinutes == intervalMinutes &&
      other.constraints == constraints;

  @override
  int get hashCode => Object.hash(desired, intervalMinutes, constraints);
}

/// The plan for the current saved tasks and settings. Pure.
AndroidWorkPlan planAndroidWork({
  required List<TransferTask> tasks,
  required AndroidWorkConstraints constraints,
  required int pollMinutes,
  required bool optInOffered,
}) => AndroidWorkPlan(
  desired: androidWorkDesired(
    tasks: [
      for (final t in tasks)
        (schedule: t.schedule, runWhileClosed: t.runWhileClosed),
    ],
    optInOffered: optInOffered,
  ),
  intervalMinutes: androidWorkIntervalFor(pollMinutes),
  constraints: constraints,
);

/// One sentence of truth for the Settings section, in the same register as
/// `registrationExplanation`: what will happen, and where the slack is.
String androidWorkExplanation(AndroidWorkPlan plan) {
  if (!plan.desired) {
    return 'Nothing is scheduled, so Android is not asked to wake Airclone.';
  }
  final conditions = <String>[
    if (plan.constraints.unmetered) 'on Wi-Fi',
    if (plan.constraints.charging) 'while charging',
  ];
  final when = conditions.isEmpty ? '' : ' ${conditions.join(' and ')}';
  return 'Android wakes Airclone about every ${plan.intervalMinutes} minutes'
      '$when and runs whatever is due, even with the app closed. A task can '
      'start up to that long after its time, and Android may hold a wake '
      'back to save battery.';
}

/// Keeps WorkManager in step with the saved tasks and the constraint settings.
///
/// Force-read once at launch (HomeScreen) like the other lazy providers. It
/// stores the Dart entrypoint's handle first — a wake before that is stored
/// has nothing to run — waits for the tasks to hydrate (acting on the empty
/// list `build()` returns would cancel a real registration), then applies the
/// plan and re-applies it whenever the inputs change. A plan equal to the last
/// one applied is skipped, so the run-history and `lastRun` writes that every
/// scheduled run makes to `tasksProvider` do not each touch WorkManager.
final androidWorkReconcilerProvider = Provider<void>((ref) {
  if (!HostPlatform.isAndroid) return;
  final work = ref.read(androidWorkProvider);
  var registered = false;
  AndroidWorkPlan? applied;

  Future<void> reconcile() async {
    if (!registered) return;
    final plan = planAndroidWork(
      tasks: ref.read(tasksProvider),
      constraints: ref.read(androidWorkSettingsProvider),
      pollMinutes: ref.read(pollCadenceProvider),
      optInOffered: canRunWhileClosed,
    );
    if (plan == applied) return;
    final ok = plan.desired
        ? await work.enqueuePeriodic(
                intervalMinutes: plan.intervalMinutes,
                unmetered: plan.constraints.unmetered,
                charging: plan.constraints.charging,
              ) !=
              null
        : await work.cancelPeriodic();
    if (ok) applied = plan;
  }

  unawaited(() async {
    registered = await work.registerCallback(androidWorkEntrypoint);
    await ref.read(tasksProvider.notifier).ready;
    await reconcile();
  }());
  ref.listen(tasksProvider, (_, _) => unawaited(reconcile()));
  ref.listen(androidWorkSettingsProvider, (_, _) => unawaited(reconcile()));
  ref.listen(pollCadenceProvider, (_, _) => unawaited(reconcile()));
});
