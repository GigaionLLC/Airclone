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
