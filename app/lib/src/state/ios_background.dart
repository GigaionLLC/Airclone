import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/job.dart';
import 'android_work_registration.dart';
import 'host_platform.dart';
import 'jobs_controller.dart';
import 'poll_cadence.dart';
import 'scheduling_policy.dart';
import 'tasks_controller.dart';

/// Keeping work going on iOS, which suspends an app shortly after you leave it
/// (#52). Three pieces, all answered by AppDelegate.swift:
///
///  * While a transfer is queued or running, the app holds an iOS background
///    task, so leaving Airclone gives it the extra time iOS allows (about 30
///    seconds) to finish rather than stopping mid-file.
///  * Optionally, the screen stays on while a transfer runs, so a long sync is
///    not cut off when the phone locks itself ([iosKeepScreenOnProvider]).
///  * Scheduled tasks are submitted to BGTaskScheduler. iOS runs them when it
///    chooses, usually while charging on Wi-Fi, through the same headless
///    entrypoint Android's WorkManager wake uses (android_work_entrypoint.dart).
const _channel = MethodChannel('airclone/native');

const _keepScreenOnKey = 'ios_keep_screen_on';

/// "Keep the screen on during transfers". On by default: without it a sync
/// stops when the phone locks itself, which is the complaint this answers.
class IosKeepScreenOn extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(_keepScreenOnKey);
      if (v != null) state = v;
    } catch (_) {}
  }

  Future<void> set(bool v) async {
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_keepScreenOnKey, v);
    } catch (_) {
      // best-effort
    }
  }
}

final iosKeepScreenOnProvider = NotifierProvider<IosKeepScreenOn, bool>(
  IosKeepScreenOn.new,
);

/// Tells iOS whether a transfer is active, and whether to keep the screen on.
/// Force-read once at launch (HomeScreen), like Android's foreground service.
final iosTransferKeepAliveProvider = Provider<void>((ref) {
  if (!HostPlatform.isIOS) return;
  bool? sentActive;
  bool? sentScreen;
  Future<void> apply() async {
    final active = ref
        .read(jobsControllerProvider)
        .any(
          (j) => j.status == JobStatus.running || j.status == JobStatus.queued,
        );
    final screen = active && ref.read(iosKeepScreenOnProvider);
    if (active == sentActive && screen == sentScreen) return;
    sentActive = active;
    sentScreen = screen;
    try {
      await _channel.invokeMethod<void>('transferActive', {
        'active': active,
        'keepScreenOn': screen,
      });
    } catch (_) {}
  }

  ref.listen(jobsControllerProvider, (_, _) => unawaited(apply()));
  ref.listen(iosKeepScreenOnProvider, (_, _) => unawaited(apply()));
});

/// Keeps the BGTaskScheduler request in step with the saved tasks: submitted
/// while anything scheduled wants to run with the app closed, cancelled when
/// nothing does. Re-applied at every launch, which is also what re-arms it.
final iosBackgroundReconcilerProvider = Provider<void>((ref) {
  if (!HostPlatform.isIOS) return;
  bool? applied;
  Future<void> reconcile() async {
    final desired = androidWorkDesired(
      tasks: [
        for (final t in ref.read(tasksProvider))
          (schedule: t.schedule, runWhileClosed: t.runWhileClosed),
      ],
      optInOffered: canRunWhileClosed,
    );
    if (desired == applied) return;
    try {
      await _channel.invokeMethod<void>(
        desired ? 'scheduleBackgroundRun' : 'cancelBackgroundRun',
        {'minutes': ref.read(pollCadenceProvider)},
      );
      applied = desired;
    } catch (_) {}
  }

  unawaited(() async {
    await ref.read(tasksProvider.notifier).ready;
    await reconcile();
  }());
  ref.listen(tasksProvider, (_, _) => unawaited(reconcile()));
});
