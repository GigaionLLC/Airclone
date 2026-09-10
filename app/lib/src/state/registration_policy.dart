import 'scheduling_policy.dart';
import 'task_schedule.dart';

/// How one saved schedule gets itself run while Airclone is closed.
///
/// The choice is not a preference and not a platform switch. It follows from
/// one question: **does this schedule name an exact time?**
///
/// A "daily at 09:00" task should fire at 09:00. An OS scheduler can do that
/// exactly, for free, with no wakeups in between — a shared poller can only
/// approximate it, and being fifteen minutes late is the kind of thing people
/// read as broken. An "every two hours" task, on the other hand, is already
/// polling by its nature; giving it its own OS entry buys nothing and adds a
/// second independent wakeup source to keep in sync.
///
/// So: exact schedules get exact triggers, inexact ones share one poller.
enum RegistrationShape {
  /// Its own OS entry with a calendar trigger, firing at the time it names.
  exactTrigger,

  /// Membership of the single shared job that wakes on a fixed cadence and runs
  /// whatever is due (`--run-due`). No entry of its own.
  sharedPoller,

  /// This platform has no background execution yet, so nothing is registered
  /// and the in-app scheduler is all there is.
  unsupported,
}

/// The shape [schedule] should be registered as on [operatingSystem].
///
/// Takes the OS name rather than reading the platform so every case is testable
/// from any machine — the same seam [schedulingSupportFor] uses.
///
/// A platform with no background execution returns [RegistrationShape.unsupported]
/// for everything, including exact schedules: there is nothing to register
/// *into*. That is decided by [schedulingSupportFor] rather than re-listed here,
/// so a platform gaining background support gains it in one place.
RegistrationShape registrationShapeFor({
  required TaskSchedule schedule,
  required String operatingSystem,
}) {
  if (schedulingSupportFor(operatingSystem) != SchedulingSupport.background) {
    return RegistrationShape.unsupported;
  }
  // Android has exactly ONE periodic worker and no per-task OS triggers, so the
  // exact/shared split does not exist there — everything is served by the one
  // wake. Saying otherwise would promise a 09:00 fire that WorkManager cannot
  // make, on a platform whose floor is fifteen minutes anyway.
  if (operatingSystem == 'android') return RegistrationShape.sharedPoller;
  return switch (schedule.kind) {
    // Names a wall-clock time: the OS can hit it exactly.
    ScheduleKind.daily || ScheduleKind.weekly => RegistrationShape.exactTrigger,
    // Names only a gap between runs, which is what a poller already provides.
    ScheduleKind.interval => RegistrationShape.sharedPoller,
  };
}

/// Default wake cadence for the shared poller.
///
/// Fifteen minutes is 96 wakeups a day and bounds lateness at fifteen minutes
/// for the schedules that reach the poller at all — which, by the rule above,
/// are only the ones that never named an exact time. It also matches Android
/// WorkManager's own hard floor, so the platforms do not disagree about what
/// "roughly every quarter hour" means.
const int kDefaultPollMinutes = 15;

/// The cadences offered, coarsest first at the ends people actually want.
///
/// Bounded rather than free-form: below five minutes the wakeups cost more than
/// the feature is worth on a laptop, and above an hour an interval schedule
/// stops resembling what the user asked for.
const List<int> kPollMinuteChoices = [5, 10, 15, 30, 60];

/// Clamps an arbitrary stored or typed value onto the supported range.
///
/// Not [kPollMinuteChoices] membership — a value that came from an older build
/// or a hand-edited preference should be honoured if it is sane, not silently
/// snapped to the nearest offered choice.
int clampPollMinutes(int minutes) =>
    minutes.clamp(kPollMinuteChoices.first, kPollMinuteChoices.last);

/// What the whole set of saved schedules needs registered, in one answer.
///
/// Returning both halves together is the point: the shared poller must exist
/// exactly when at least one schedule has been routed to it, and reconciling
/// those two facts separately is how one of them ends up orphaned. This is the
/// function that decides, so there is one place to be right.
///
/// [runWhileClosed] holds the ids the user has opted in — background execution
/// is never assumed for a schedule just because it exists.
({Set<String> exactTriggerIds, bool needsPoller}) desiredRegistrations({
  required Iterable<({String id, TaskSchedule? schedule})> tasks,
  required Set<String> runWhileClosed,
  required String operatingSystem,
}) {
  final exact = <String>{};
  var poller = false;
  for (final t in tasks) {
    final s = t.schedule;
    if (s == null || !runWhileClosed.contains(t.id)) continue;
    switch (registrationShapeFor(
      schedule: s,
      operatingSystem: operatingSystem,
    )) {
      case RegistrationShape.exactTrigger:
        exact.add(t.id);
      case RegistrationShape.sharedPoller:
        poller = true;
      case RegistrationShape.unsupported:
        break;
    }
  }
  return (exactTriggerIds: exact, needsPoller: poller);
}

/// Where a schedule is registered, named the way a user can go and check it.
///
/// A hybrid means there are now three different things that can run a saved
/// task, and when one of them does not fire, "it did not run" is not a
/// diagnosis. This is the sentence that turns it into one: it says which
/// mechanism owns this schedule and, on a platform where that mechanism is
/// inspectable, exactly what to open.
///
/// Deliberately concrete. "Runs in the background" tells a user nothing they can
/// act on; "Task Scheduler → Airclone → Run due tasks" tells them where to look
/// and what they should see there.
String registrationExplanation({
  required TaskSchedule schedule,
  required String operatingSystem,
  required bool runWhileClosed,
  required int pollMinutes,
  required String taskName,
}) {
  final shape = registrationShapeFor(
    schedule: schedule,
    operatingSystem: operatingSystem,
  );
  if (shape == RegistrationShape.unsupported) {
    return 'Runs only while Airclone is open. This device has no background '
        'scheduling yet, so a run missed while it was closed starts once on '
        'next launch.';
  }
  if (!runWhileClosed) {
    return 'Runs only while Airclone is open, because "Also run while Airclone '
        'is closed" is off for this task. A run missed while it was closed '
        'starts once on next launch.';
  }
  // Only Windows exposes its registrations as named, inspectable entries. On
  // Android the wake is WorkManager's and there is nothing for a user to open,
  // so naming a place to look would send them hunting for one that is not there.
  if (operatingSystem == 'android') {
    return 'Android wakes Airclone about every $pollMinutes minutes and runs '
        'this when it is due, so it can start late — and later still if the '
        'phone is asleep, on battery saver, or off Wi-Fi.';
  }
  return switch (shape) {
    RegistrationShape.exactTrigger =>
      'Windows runs this at the exact time you chose, even with Airclone '
          'closed. It appears in Task Scheduler under '
          'Airclone \u2192 $taskName, and it is the only place to look if it '
          'stops firing.',
    RegistrationShape.sharedPoller =>
      'Windows wakes Airclone every $pollMinutes minutes and runs this when it '
          'is due, so it can start up to $pollMinutes minutes late. One shared '
          'job covers every interval schedule: Task Scheduler \u2192 '
          'Airclone \u2192 $kDueRunnerTaskName.',
    // Handled above; listed so a future shape cannot fall through silently.
    RegistrationShape.unsupported => '',
  };
}

/// The OS-level name of the single shared job that runs whatever is due.
///
/// A fixed, known name rather than a generated one: it is the thing an uninstall
/// has to find, the thing a reconcile has to recognise as already ours, and the
/// thing [registrationExplanation] tells a user to go and look at.
///
/// Lives here rather than in the Windows scheduler so the platform-neutral
/// explanation can name it without depending on `dart:io`.
const String kDueRunnerTaskName = 'Run due tasks';

/// What the OS scheduler should be changed to, given what it currently holds.
///
/// Reconciliation rather than "register this one thing", because the hybrid made
/// a per-task answer impossible: turning a daily schedule into an interval one
/// must DELETE its exact entry and create the shared poller, and neither of
/// those is a fact about the task being edited.
///
/// It is also where the migration lives, without being a migration. A user who
/// set up an interval schedule under the old build has a private per-task entry
/// for it; under the hybrid that entry is simply *not desired*, so it appears in
/// [toDelete] like any other stale registration. There is no version check and
/// no one-shot upgrade step to get wrong — the same code that keeps things right
/// every day is the code that cleans that up, the first time it runs.
///
/// [existing] is every entry currently in our folder, by its leaf name: a task
/// id for an exact trigger, or [kDueRunnerTaskName] for the shared job.
///
/// Anything in our folder that is neither wanted nor recognised is deleted. The
/// folder is ours, so an entry we did not put there is residue — most likely
/// ours from an older build under a name we no longer use.
({List<String> toCreate, List<String> toDelete}) planReconcile({
  required ({Set<String> exactTriggerIds, bool needsPoller}) desired,
  required Set<String> existing,
}) {
  final want = {
    ...desired.exactTriggerIds,
    if (desired.needsPoller) kDueRunnerTaskName,
  };
  // Sorted so the plan is deterministic — a test can assert it, and a log of
  // what changed reads the same way twice.
  final toCreate = want.difference(existing).toList()..sort();
  final toDelete = existing.difference(want).toList()..sort();
  return (toCreate: toCreate, toDelete: toDelete);
}

/// The leaf names currently registered in our folder, parsed from
/// `schtasks /Query /FO CSV /NH`.
///
/// Each row is `"\Airclone\<name>","<next run time>","<status>"`. Pure, so the
/// parsing is tested without a Task Scheduler; the caller does the spawning.
///
/// Rows for anything outside [folder] are ignored rather than trusted — the
/// caller may hand us the unfiltered output of a query over every task on the
/// machine, and deleting one of those would be catastrophic.
Set<String> parseRegisteredNames(String csv, {String folder = 'Airclone'}) {
  final prefix = '\\$folder\\';
  final names = <String>{};
  for (final line in csv.split('\n')) {
    final row = line.trim();
    if (row.isEmpty) continue;
    // Only the first CSV field matters, and it is always quoted.
    if (!row.startsWith('"')) continue;
    final end = row.indexOf('"', 1);
    if (end < 1) continue;
    final full = row.substring(1, end);
    if (!full.startsWith(prefix)) continue;
    final leaf = full.substring(prefix.length);
    // A nested folder is not one of ours; we only ever create leaves.
    if (leaf.isEmpty || leaf.contains('\\')) continue;
    names.add(leaf);
  }
  return names;
}
