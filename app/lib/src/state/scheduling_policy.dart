import 'host_platform.dart';

/// What "run on a schedule" actually means on the platform you are standing on.
///
/// This exists because the answer is genuinely different in three directions and
/// the product used to imply one answer everywhere. Scattering `HostPlatform.isWindows`
/// across the UI made every surface responsible for getting that right on its
/// own, and they did not agree — the README promised scheduling unconditionally,
/// the schedule editor gated one checkbox, and a phone offered nothing at all
/// while saying nothing about it.
///
/// One enum, one pure decision function, one honest sentence per case.
enum SchedulingSupport {
  /// No scheduling at all. Mobile today: there is no entry point, and no
  /// background execution behind it if there were.
  none,

  /// The in-app scheduler ticks while Airclone is open and catches up a missed
  /// slot once on next launch. Nothing fires with the app closed.
  whileOpen,

  /// Everything [whileOpen] has, plus an OS-registered background run that
  /// fires with Airclone closed.
  background,
}

/// The decision itself, as a pure function of the OS name so it can be tested
/// without a platform. Takes [HostPlatform.operatingSystem]'s vocabulary:
/// `windows`, `macos`, `linux`, `android`, `ios`, `fuchsia`.
///
/// An OS we have never heard of gets [SchedulingSupport.none] rather than a
/// guess — promising a background run we have not wired is the failure this
/// whole file is here to stop.
SchedulingSupport schedulingSupportFor(String operatingSystem) =>
    switch (operatingSystem) {
      // Windows Task Scheduler + the headless `--run-task` entry point.
      'windows' => SchedulingSupport.background,
      // WorkManager + a headless FlutterEngine (v0.8 Phase F). Proven on an
      // emulator: an OS-timed wake with the app process dead ran a due task to
      // completion. The 15-minute floor is Android's, not ours.
      'android' => SchedulingSupport.background,
      // launchd and systemd-user are planned, not built. Until they are, saying
      // "background" here would be a lie with a data-loss shape: a user would
      // close the app expecting their backup to run.
      'macos' || 'linux' => SchedulingSupport.whileOpen,
      _ => SchedulingSupport.none,
    };

/// The support level of the platform this build is running on.
SchedulingSupport get schedulingSupport =>
    schedulingSupportFor(HostPlatform.operatingSystem);

/// Whether a schedule can be created at all here.
bool get canSchedule => schedulingSupport != SchedulingSupport.none;

/// Whether to offer "Also run while Airclone is closed".
///
/// Replaces the old `_canOsSchedule => HostPlatform.isWindows` in the schedule
/// editor. Same answer today; the difference is that when launchd lands, it
/// lands in one place.
bool get canRunWhileClosed => schedulingSupport == SchedulingSupport.background;

/// One sentence of truth to put under a schedule control, per platform.
///
/// Written for a user, not a changelog: it says what will happen tonight, not
/// which subsystem is missing.
String schedulingSummaryFor(SchedulingSupport s) => switch (s) {
  SchedulingSupport.background =>
    'Scheduled tasks run in the background, even with Airclone closed.',
  SchedulingSupport.whileOpen =>
    'Scheduled tasks run while Airclone is open. A run missed while it was '
        'closed starts once on next launch.',
  SchedulingSupport.none =>
    'Scheduling is not available on this device yet — saved tasks still run '
        'when you start them by hand.',
};

/// [schedulingSummaryFor] for the current platform.
String get schedulingSummary => schedulingSummaryFor(schedulingSupport);
