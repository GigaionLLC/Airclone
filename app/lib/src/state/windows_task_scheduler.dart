import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// `ExecutionTimeLimit=PT6H`, and `MultipleInstancesPolicy=IgnoreNew` (a slow
/// run isn't stacked on by the next slot).
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
  return '<?xml version="1.0" encoding="UTF-16"?>\n'
      '<Task version="1.2" xmlns="$_taskXmlns">\n'
      '  <RegistrationInfo>\n'
      '    <Author>Airclone</Author>\n'
      '    <Description>Airclone scheduled transfer ($idEsc). Runs in the '
      'background while Airclone is closed.</Description>\n'
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
      '    <ExecutionTimeLimit>PT6H</ExecutionTimeLimit>\n'
      '  </Settings>\n'
      '  <Actions Context="Author">\n'
      '    <Exec>\n'
      '      <Command>$exe</Command>\n'
      '      <Arguments>$args</Arguments>\n'
      '    </Exec>\n'
      '  </Actions>\n'
      '</Task>\n';
}

/// Registers saved schedules as Windows Scheduled Tasks so they fire with the
/// app CLOSED (the in-app scheduler only ticks while Airclone is open). Each task
/// is named `Airclone\<TransferTask.id>`: the `Airclone\` folder groups them so a
/// future uninstall can enumerate and remove every one.
///
/// Windows-only — every public method silently no-ops on other platforms (and is
/// only invoked behind a `Platform.isWindows` gate in the UI anyway). The
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
    if (!Platform.isWindows || schedule == null) return _ok;
    final xml = buildTaskXml(
      schedule: schedule,
      id: t.id,
      exePath: Platform.resolvedExecutable,
    );
    // schtasks /XML reads a file, not stdin; write the definition next to the
    // system temp dir keyed by task id (so concurrent registers don't collide)
    // as UTF-16 to match the declared encoding, then clean it up.
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
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
    if (!Platform.isWindows) return;
    try {
      await _run('schtasks', ['/Delete', '/TN', taskName(id), '/F']);
    } catch (_) {
      // best-effort — a missing task is a success from the caller's view
    }
  }

  /// Whether a Scheduled Task is currently registered for [id], probed via the
  /// exit code of `schtasks /Query`. False on non-Windows or any error.
  Future<bool> isRegistered(String id) async {
    if (!Platform.isWindows) return false;
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
