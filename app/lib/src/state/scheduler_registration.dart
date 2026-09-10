import 'scheduling_policy.dart';
import 'tasks_controller.dart';
import 'windows_task_scheduler.dart';

/// Carries forward a background opt-in that used to live in Task Scheduler.
///
/// `runWhileClosed` is new. It used to be inferred by asking Task Scheduler
/// whether `Airclone\<id>` existed, which worked because every scheduled task
/// had its own entry — and stops working under the hybrid, where an interval
/// schedule is served by one shared job and has no entry of its own to ask
/// about.
///
/// So the intent moved onto the model, and every task saved before that moment
/// says `false` while a perfectly good registration sits in Task Scheduler. A
/// reconcile run against those tasks would read "nobody wants background runs"
/// and delete the lot.
///
/// This is what stops that: any task whose id is currently registered is marked
/// as opted in, once, before anything is reconciled. Returns null when nothing
/// needed changing, so the common case does not rewrite the store.
///
/// It only ever turns the flag ON. Turning it off is a thing the user does, and
/// inferring "they must not want this" from an absent registration would undo a
/// choice rather than recover one.
List<TransferTask>? seedRunWhileClosed(
  List<TransferTask> tasks,
  Set<String> registered,
) {
  var changed = false;
  final out = [
    for (final t in tasks)
      if (!t.runWhileClosed && registered.contains(t.id))
        (() {
          changed = true;
          return t.copyWith(runWhileClosed: true);
        })()
      else
        t,
  ];
  return changed ? out : null;
}

/// Makes the OS scheduler match the saved tasks, seeding the opt-in first.
///
/// Called at launch and after any edit that changes what should be registered.
/// Everything it does is a no-op on a platform without background execution, so
/// callers do not need their own platform check.
///
/// [refresh] names entries whose definition must be rewritten even though they
/// already exist — the task just edited, or every entry when the cadence
/// changed. See [WindowsTaskScheduler.reconcile] for why that is not the
/// default.
///
/// Never throws: a scheduler that cannot reconcile should leave things as they
/// are, not take down the app.
/// Takes its dependencies rather than a `Ref`, because both a widget and a
/// provider need to call it and `WidgetRef` and `Ref` are unrelated types. It
/// also makes the whole thing drivable from a test with no container.
Future<void> reconcileRegistrations({
  required TasksController notifier,
  required List<TransferTask> Function() readTasks,
  required WindowsTaskScheduler os,
  required int pollMinutes,
  Set<String> refresh = const {},
  bool seed = false,
}) async {
  if (!canRunWhileClosed) return;
  try {
    // The whole set has to be real before acting on it. An empty list reads as
    // "nothing is scheduled" and would unregister everything.
    await notifier.ready;

    if (seed) {
      final seeded = seedRunWhileClosed(readTasks(), await os.listRegistered());
      if (seeded != null) await notifier.replaceAll(seeded);
    }
    await os.reconcile(
      tasks: readTasks(),
      pollMinutes: pollMinutes,
      refresh: refresh,
    );
  } catch (_) {
    // Best effort. The in-app scheduler still runs everything while the app is
    // open, so a failed reconcile degrades background execution rather than
    // breaking scheduling outright.
  }
}
