import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'host_platform.dart';
import 'registration_policy.dart';
import 'task_schedule.dart';
import 'tasks_controller.dart';

/// Spawns a process, so [WindowsTaskScheduler]'s `schtasks` calls are injectable
/// in a test without actually shelling out. Mirrors `OsIntegration`'s seam.
typedef ProcessRunner =
    Future<ProcessResult> Function(String exe, List<String> args);

/// Outcome of [WindowsTaskScheduler.register]. On failure [ok] is false and
/// [error] carries a short `schtasks` message the schedule editor surfaces inline
/// under the checkbox (never thrown — the dialog must not crash on a bad exit).
typedef RegisterResult = ({bool ok, String? error});

const RegisterResult _ok = (ok: true, error: null);

/// Task Scheduler's v1.2 task schema namespace. A definition handed to
/// `schtasks /Create /XML` in any other namespace is rejected by the parser.
const _taskXmlns = 'http://schemas.microsoft.com/windows/2004/02/mit/task';

/// A fixed, safely-in-the-past start-boundary DATE. Calendar triggers use only
/// the boundary's TIME-of-day for each daily/weekly fire, and an interval
/// TimeTrigger just needs a boundary already elapsed so `StartWhenAvailable`
/// runs it right away — so the date is arbitrary as long as it isn't in the
/// future. A constant (rather than `DateTime.now()`) keeps [buildTaskXml] pure
/// and its output deterministic for the unit tests.
const _boundaryDate = '2024-01-01';

/// Maps a Dart `DateTime.weekday` (Mon=1 … Sun=7 — the convention
/// [TaskSchedule.weekdays] stores) to its Task Scheduler `DaysOfWeek` child
/// element name.
const _dayOfWeekElements = <int, String>{
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

String _two(int n) => n.toString().padLeft(2, '0');

/// A `YYYY-MM-DDThh:mm:00` start boundary at [hour]:[minute] on [_boundaryDate].
String _boundary(int hour, int minute) =>
    '${_boundaryDate}T${_two(hour)}:${_two(minute)}:00';

/// Escapes the five XML metacharacters. `&` MUST be replaced first, otherwise a
/// subsequently-inserted `&lt;`/`&amp;` would itself be double-escaped. Applied
/// to the executable path (which can hold `&`, spaces, etc.) so a path like
/// `C:\Air & Clone\airclone.exe` produces valid XML.
String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// The single `<Trigger>` element for [s]. Child-element order follows Task
/// Scheduler's own exported-task shape (its parser is order-sensitive):
/// - interval → a [TimeTrigger] that repeats every `intervalMinutes` minutes
///   indefinitely. `<Repetition>` precedes `<StartBoundary>`/`<Enabled>` as in a
///   real export; omitting `<Duration>` is the schema's way of saying "repeat
///   forever"; the boundary sits in the past so the first fire is immediate.
/// - daily → a `CalendarTrigger`/`ScheduleByDay` at the boundary's time-of-day.
/// - weekly → a `CalendarTrigger`/`ScheduleByWeek` at that time on the selected
///   `DaysOfWeek` (weekdays sorted for a stable, readable definition).
String _triggerXml(TaskSchedule s) {
  switch (s.kind) {
    case ScheduleKind.interval:
      return '<TimeTrigger>'
          '<Repetition>'
          '<Interval>PT${s.intervalMinutes}M</Interval>'
          '<StopAtDurationEnd>false</StopAtDurationEnd>'
          '</Repetition>'
          '<StartBoundary>${_boundaryDate}T00:00:00</StartBoundary>'
          '<Enabled>true</Enabled>'
          '</TimeTrigger>';
    case ScheduleKind.daily:
      return '<CalendarTrigger>'
          '<StartBoundary>${_boundary(s.hour, s.minute)}</StartBoundary>'
          '<Enabled>true</Enabled>'
          '<ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>'
          '</CalendarTrigger>';
    case ScheduleKind.weekly:
      final days = (s.weekdays.toList()..sort())
          .map((d) => _dayOfWeekElements[d])
          .whereType<String>()
          .map((name) => '<$name/>')
          .join();
      return '<CalendarTrigger>'
          '<StartBoundary>${_boundary(s.hour, s.minute)}</StartBoundary>'
          '<Enabled>true</Enabled>'
          '<ScheduleByWeek>'
          '<DaysOfWeek>$days</DaysOfWeek>'
          '<WeeksInterval>1</WeeksInterval>'
          '</ScheduleByWeek>'
          '</CalendarTrigger>';
  }
}

/// Builds the Task Scheduler XML definition for a task: [schedule] mapped to a
/// trigger, an `Exec` action of [exePath] `--run-task <id>` (the headless CLI
/// contract), and the settings that make an *unattended* run trustworthy —
/// `StartWhenAvailable` (catch up a run missed while the PC was off/asleep),
/// `DisallowStartIfOnBatteries=false` (laptops on battery still run),
/// `ExecutionTimeLimit=PT72H`, and `MultipleInstancesPolicy=IgnoreNew` (a slow
/// run isn't stacked on by the next slot).
///
/// PT72H is only the outer backstop. The real guard against a hung run is the
/// no-progress watchdog in `recordRunOutcome`, which stops a run that has
/// moved nothing for `kStallWindow`; a long run that keeps moving is allowed
/// to finish, which a fixed six-hour limit used to cut off mid-transfer. The
/// value matches `kMaxSuperviseDuration` and the headless default timeout.
///
/// The Description carries a definition fingerprint (see
/// [definitionFingerprint]), so [WindowsTaskScheduler.reconcile] can tell an
/// entry written by an older build from a current one.
///
/// Pure + side-effect free (no clock read, no I/O) so `windows_task_scheduler_test`
/// can assert the schedule→XML mapping directly. [register] handles turning the
/// returned string into the UTF-16 file `schtasks` consumes.
String buildTaskXml({
  required TaskSchedule schedule,
  required String id,
  required String exePath,
}) {
  final exe = _xmlEscape(exePath);
  final args = _xmlEscape('--run-task $id');
  // Escape the id in the Description too (not just <Arguments>): today's ids are
  // [0-9a-z-] so it's inert, but a future id source with & < > would otherwise
  // yield well-formed <Arguments> yet malformed <Description> — a latent trap.
  final idEsc = _xmlEscape(id);
  return _stampDefinition(
    '<?xml version="1.0" encoding="UTF-16"?>\n'
    '<Task version="1.2" xmlns="$_taskXmlns">\n'
    '  <RegistrationInfo>\n'
    '    <Author>Airclone</Author>\n'
    '    <Description>Airclone scheduled transfer ($idEsc). Runs in the '
    'background while Airclone is closed.$_defToken</Description>\n'
    '  </RegistrationInfo>\n'
    '  <Triggers>\n'
    '    ${_triggerXml(schedule)}\n'
    '  </Triggers>\n'
    '  <Principals>\n'
    '    <Principal id="Author">\n'
    '      <LogonType>InteractiveToken</LogonType>\n'
    '      <RunLevel>LeastPrivilege</RunLevel>\n'
    '    </Principal>\n'
    '  </Principals>\n'
    // Element order follows Task Scheduler's schema sequence (its parser is
    // order-sensitive): batteries settings precede StartWhenAvailable, and
    // Enabled precedes ExecutionTimeLimit.
    '  <Settings>\n'
    '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n'
    '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\n'
    '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\n'
    '    <StartWhenAvailable>true</StartWhenAvailable>\n'
    '    <Enabled>true</Enabled>\n'
    '    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>\n'
    '  </Settings>\n'
    '  <Actions Context="Author">\n'
    '    <Exec>\n'
    '      <Command>$exe</Command>\n'
    '      <Arguments>$args</Arguments>\n'
    '    </Exec>\n'
    '  </Actions>\n'
    '</Task>\n',
  );
}

/// Builds the definition for the shared `--run-due` job: one `TimeTrigger`
/// repeating every [intervalMinutes], running the headless entry point that
/// selects and runs whatever is due.
///
/// The counterpart to [buildTaskXml], which builds an EXACT trigger for one
/// task. Which of the two a schedule gets is `registrationShapeFor`'s decision,
/// not this file's — see `state/registration_policy.dart`.
///
/// Settings are deliberately identical to the per-task ones, because the
/// reasons are identical: catch up a run missed while the machine was off, do
/// not skip because a laptop is on battery, and never stack a slow run under
/// the next tick. The one difference is the description, which has to explain a
/// job the user never created by name.
///
/// Pure and side-effect free, for the same reason as [buildTaskXml].
String buildDueRunnerXml({
  required int intervalMinutes,
  required String exePath,
}) {
  final exe = _xmlEscape(exePath);
  final minutes = clampPollMinutes(intervalMinutes);
  return _stampDefinition(
    '<?xml version="1.0" encoding="UTF-16"?>\n'
    '<Task version="1.2" xmlns="$_taskXmlns">\n'
    '  <RegistrationInfo>\n'
    '    <Author>Airclone</Author>\n'
    '    <Description>Airclone background scheduler. Wakes every $minutes '
    'minutes and runs any saved task whose schedule is due, while Airclone '
    'is closed.$_defToken</Description>\n'
    '  </RegistrationInfo>\n'
    '  <Triggers>\n'
    '    <TimeTrigger>'
    '<Repetition>'
    '<Interval>PT${minutes}M</Interval>'
    '<StopAtDurationEnd>false</StopAtDurationEnd>'
    '</Repetition>'
    '<StartBoundary>${_boundaryDate}T00:00:00</StartBoundary>'
    '<Enabled>true</Enabled>'
    '</TimeTrigger>\n'
    '  </Triggers>\n'
    '  <Principals>\n'
    '    <Principal id="Author">\n'
    '      <LogonType>InteractiveToken</LogonType>\n'
    '      <RunLevel>LeastPrivilege</RunLevel>\n'
    '    </Principal>\n'
    '  </Principals>\n'
    '  <Settings>\n'
    '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n'
    '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\n'
    '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\n'
    '    <StartWhenAvailable>true</StartWhenAvailable>\n'
    '    <Enabled>true</Enabled>\n'
    '    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>\n'
    '  </Settings>\n'
    '  <Actions Context="Author">\n'
    '    <Exec>\n'
    '      <Command>$exe</Command>\n'
    '      <Arguments>--run-due</Arguments>\n'
    '    </Exec>\n'
    '  </Actions>\n'
    '</Task>\n',
  );
}

/// Where a definition's fingerprint goes, inside its Description. Replaced by
/// [_stampDefinition] before anything is written.
const _defPlaceholder = '%AIRCLONE_DEF%';
const _defToken = ' [airclone-def:$_defPlaceholder]';
final _defPattern = RegExp(r'airclone-def:([0-9a-f]{16})');

/// Stamps [xml] with a fingerprint of itself: the first 16 hex digits of the
/// SHA-256 of the definition as built, placeholder and all. Any change to what
/// a build writes (a new time limit, a moved executable, an edited trigger)
/// changes the fingerprint, with no version number to remember to bump.
String _stampDefinition(String xml) {
  final digest = sha256.convert(utf8.encode(xml)).toString().substring(0, 16);
  return xml.replaceFirst(_defPlaceholder, digest);
}

/// The fingerprint stamped into a task definition, or null when there is none
/// (an entry written before fingerprints existed, or not by Airclone at all).
///
/// Reads both a definition this file built and the XML `schtasks /Query /XML`
/// prints back, which may arrive with stray NULs from the UTF-16 round trip.
String? definitionFingerprint(String xml) =>
    _defPattern.firstMatch(xml.replaceAll('\u0000', ''))?.group(1);

/// Registers saved schedules as Windows Scheduled Tasks so they fire with the
/// app CLOSED (the in-app scheduler only ticks while Airclone is open). Each task
/// is named `Airclone\<TransferTask.id>`: the `Airclone\` folder groups them so a
/// future uninstall can enumerate and remove every one.
///
/// Windows-only — every public method silently no-ops on other platforms (and is
/// only invoked behind a `HostPlatform.isWindows` gate in the UI anyway). The
/// [ProcessRunner] seam exists for testability; production shells out to the
/// in-box `schtasks.exe`.
class WindowsTaskScheduler {
  WindowsTaskScheduler({ProcessRunner? runner})
    : _run = runner ?? ((e, a) => Process.run(e, a, runInShell: false));

  final ProcessRunner _run;

  /// The Task Scheduler name for [id] under the grouping folder. The backslash
  /// makes `Airclone` a folder that holds every Airclone task.
  static String taskName(String id) => 'Airclone\\$id';

  /// (Re-)registers [t]'s schedule as a Windows Scheduled Task via
  /// `schtasks /Create /XML … /F` (the `/F` overwrites an existing definition, so
  /// this doubles as an update on an edited schedule). Returns `(ok: false, …)`
  /// with the `schtasks` message on a non-zero exit or a thrown error — never
  /// throws. A no-op success on non-Windows or when [t] has no schedule.
  Future<RegisterResult> register(TransferTask t) async {
    final schedule = t.schedule;
    if (!HostPlatform.isWindows || schedule == null) return _ok;
    final xml = buildTaskXml(
      schedule: schedule,
      id: t.id,
      exePath: Platform.resolvedExecutable,
    );
    // schtasks /XML reads a file, not stdin; write the definition next to the
    // system temp dir keyed by task id (so concurrent registers don't collide)
    // as UTF-16 to match the declared encoding, then clean it up.
    final file = File(
      '${Directory.systemTemp.path}${HostPlatform.pathSeparator}'
      'airclone-task-${t.id}.xml',
    );
    try {
      await file.writeAsBytes(_utf16leBytes(xml), flush: true);
      final res = await _run('schtasks', [
        '/Create',
        '/TN',
        taskName(t.id),
        '/XML',
        file.path,
        '/F',
      ]);
      if (res.exitCode != 0) return (ok: false, error: _schtasksError(res));
      return _ok;
    } catch (e) {
      return (ok: false, error: e.toString());
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // best-effort cleanup
      }
    }
  }

  /// Removes the Scheduled Task for [id] via `schtasks /Delete … /F`. Tolerates a
  /// not-found task (best-effort: a task that was never OS-scheduled, or already
  /// removed, is not an error). Never throws.
  Future<void> unregister(String id) async {
    if (!HostPlatform.isWindows) return;
    try {
      await _run('schtasks', ['/Delete', '/TN', taskName(id), '/F']);
    } catch (_) {
      // best-effort — a missing task is a success from the caller's view
    }
  }

  /// Every entry currently in our Task Scheduler folder, by leaf name.
  ///
  /// `schtasks /Query` over the whole machine, filtered by
  /// [parseRegisteredNames] — there is no "list one folder" form, and asking
  /// for a folder that does not exist is an error rather than an empty list.
  /// An empty set on any failure, so a reconcile that cannot see what is there
  /// creates what it needs and deletes nothing.
  Future<Set<String>> listRegistered() async {
    if (!HostPlatform.isWindows) return const {};
    try {
      final res = await _run('schtasks', ['/Query', '/FO', 'CSV', '/NH']);
      if (res.exitCode != 0) return const {};
      return parseRegisteredNames('${res.stdout}');
    } catch (_) {
      return const {};
    }
  }

  /// Makes Task Scheduler match [tasks], and returns what it changed.
  ///
  /// Reconciliation rather than register/unregister, because under the hybrid a
  /// single edit is not a single operation: turning a daily schedule into an
  /// interval one must delete that task's exact entry AND create the shared
  /// poller, and neither is a fact about the task being edited.
  ///
  /// [refresh] names entries whose DEFINITION must be rewritten even though they
  /// are already registered — the task whose schedule was just edited, or every
  /// entry when the poll cadence changed. Left empty, an entry that already
  /// exists is not touched at all. That restraint is deliberate: `schtasks
  /// /Create /F` replaces a task, which resets its trigger state, and a
  /// repeating trigger whose start boundary is in the past then fires straight
  /// away. Rewriting everything on every launch would turn opening the app into
  /// a background run.
  ///
  /// The one exception is an entry whose stored definition no longer matches
  /// what this build writes, detected by the fingerprint in its Description
  /// ([definitionFingerprint]). That entry is rewritten once, so an update
  /// that changes the definition (as the PT6H → PT72H change did) reaches
  /// tasks registered by an older build. A rewritten interval entry fires
  /// once straight away, for the reason above; the shared job then runs only
  /// what is due, and the run gate keeps it from starting anything already
  /// running.
  ///
  /// Deletes run before creates, so a shape change never leaves both forms
  /// registered at once.
  ///
  /// Never throws. A failure is returned with the `schtasks` message, the same
  /// contract [register] has, because the schedule editor surfaces it inline.
  Future<({bool ok, String? error, List<String> created, List<String> deleted})>
  reconcile({
    required List<TransferTask> tasks,
    required int pollMinutes,
    Set<String> refresh = const {},
  }) async {
    if (!HostPlatform.isWindows) {
      return (
        ok: true,
        error: null,
        created: const <String>[],
        deleted: const <String>[],
      );
    }
    final desired = desiredRegistrations(
      tasks: [for (final t in tasks) (id: t.id, schedule: t.schedule)],
      runWhileClosed: {
        for (final t in tasks)
          if (t.runWhileClosed) t.id,
      },
      operatingSystem: HostPlatform.operatingSystem,
    );
    final existing = await listRegistered();
    final plan = planReconcile(desired: desired, existing: existing);

    final deleted = <String>[];
    for (final name in plan.toDelete) {
      await unregister(name);
      deleted.add(name);
    }

    // Everything missing, plus anything the caller says has changed underneath
    // a name that already exists.
    final write = <String>{
      ...plan.toCreate,
      ...refresh.where(
        (n) =>
            desired.exactTriggerIds.contains(n) ||
            (desired.needsPoller && n == kDueRunnerTaskName),
      ),
    }.toList()..sort();

    // An entry that exists under the right name can still hold a definition
    // an older build wrote (the six-hour time limit, a moved executable).
    // Compare fingerprints and rewrite only the ones that differ, so the
    // restraint above still holds for an entry that is already current. A
    // definition that cannot be read is left alone rather than guessed at.
    final wanted = [
      ...desired.exactTriggerIds,
      if (desired.needsPoller) kDueRunnerTaskName,
    ];
    for (final name in wanted) {
      if (!existing.contains(name) || write.contains(name)) continue;
      final want = _definitionFor(name, tasks, pollMinutes);
      if (want == null) continue;
      final have = await registeredDefinition(name);
      if (have == null) continue;
      if (definitionFingerprint(have) != definitionFingerprint(want)) {
        write.add(name);
      }
    }
    write.sort();

    final created = <String>[];
    for (final name in write) {
      // A wanted id with no task behind it cannot happen — the desired set is
      // derived from these same tasks — but skipping beats writing a
      // definition for something that does not exist.
      final xml = _definitionFor(name, tasks, pollMinutes);
      if (xml == null) continue;
      final res = await _writeDefinition(name, xml);
      if (!res.ok) {
        return (
          ok: false,
          error: res.error,
          created: created,
          deleted: deleted,
        );
      }
      created.add(name);
    }
    return (ok: true, error: null, created: created, deleted: deleted);
  }

  /// The definition this build wants under [name], or null when no task
  /// behind it has a schedule.
  String? _definitionFor(
    String name,
    List<TransferTask> tasks,
    int pollMinutes,
  ) {
    if (name == kDueRunnerTaskName) {
      return buildDueRunnerXml(
        intervalMinutes: pollMinutes,
        exePath: Platform.resolvedExecutable,
      );
    }
    for (final t in tasks) {
      final schedule = t.schedule;
      if (t.id == name && schedule != null) {
        return buildTaskXml(
          schedule: schedule,
          id: t.id,
          exePath: Platform.resolvedExecutable,
        );
      }
    }
    return null;
  }

  /// The XML Task Scheduler holds for [name], via `schtasks /Query /TN … /XML`.
  /// Null on non-Windows, a non-zero exit, or any error.
  Future<String?> registeredDefinition(String name) async {
    if (!HostPlatform.isWindows) return null;
    try {
      final res = await _run('schtasks', [
        '/Query',
        '/TN',
        taskName(name),
        '/XML',
      ]);
      if (res.exitCode != 0) return null;
      return '${res.stdout}';
    } catch (_) {
      return null;
    }
  }

  /// Writes one task definition under [name] via `schtasks /Create /XML … /F`.
  ///
  /// Shared by [register] and [reconcile]. `/F` replaces an existing definition,
  /// so this is create-or-update. The XML goes to a UTF-16 file because
  /// `schtasks /XML` reads a file rather than stdin and the declared encoding
  /// has to match.
  Future<RegisterResult> _writeDefinition(String name, String xml) async {
    // Keyed by a filesystem-safe form of the name so two concurrent writes
    // cannot collide on one temp file. The shared job's name has spaces in it.
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(
      '${Directory.systemTemp.path}${HostPlatform.pathSeparator}'
      'airclone-task-$safe.xml',
    );
    try {
      await file.writeAsBytes(_utf16leBytes(xml), flush: true);
      final res = await _run('schtasks', [
        '/Create',
        '/TN',
        taskName(name),
        '/XML',
        file.path,
        '/F',
      ]);
      if (res.exitCode != 0) return (ok: false, error: _schtasksError(res));
      return _ok;
    } catch (e) {
      return (ok: false, error: e.toString());
    } finally {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {
        // A leftover temp file is not worth failing a registration over.
      }
    }
  }

  /// Whether a Scheduled Task is currently registered for [id], probed via the
  /// exit code of `schtasks /Query`. False on non-Windows or any error.
  Future<bool> isRegistered(String id) async {
    if (!HostPlatform.isWindows) return false;
    try {
      final res = await _run('schtasks', ['/Query', '/TN', taskName(id)]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// The most useful line out of a failed `schtasks` invocation for the inline
  /// error: its stderr (where it writes `ERROR: …`), falling back to stdout, then
  /// the bare exit code.
  String _schtasksError(ProcessResult res) {
    final err = (res.stderr is String ? res.stderr as String : '').trim();
    final out = (res.stdout is String ? res.stdout as String : '').trim();
    final msg = err.isNotEmpty ? err : out;
    return msg.isNotEmpty ? msg : 'schtasks exited ${res.exitCode}';
  }

  /// Encodes [s] as UTF-16LE with a byte-order mark — the encoding declared in
  /// [buildTaskXml]'s prolog and the form `schtasks /XML` reads most reliably.
  /// `String.codeUnits` are already UTF-16 code units, emitted little-endian.
  static List<int> _utf16leBytes(String s) {
    final bytes = <int>[0xFF, 0xFE]; // UTF-16LE BOM
    for (final unit in s.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return bytes;
  }
}

final windowsTaskSchedulerProvider = Provider<WindowsTaskScheduler>(
  (_) => WindowsTaskScheduler(),
);
