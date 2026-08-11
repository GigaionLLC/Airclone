import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../state/browser_controller.dart';
import '../state/cache_crypto.dart';
import '../state/config_password_vault.dart';
import '../state/engine_controller.dart';
import '../state/jobs_controller.dart';
import '../state/scheduler_controller.dart';
import '../state/task_schedule.dart';
import '../state/tasks_controller.dart';
import '../state/transfer_options.dart';
import '../state/transfer_service.dart';
import '../state/windows_task_scheduler.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';
import 'transfer_options_dialog.dart';

/// Opens the saved-tasks dialog (list · run · delete · new).
Future<void> showTasksDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _TasksDialog());

class _TasksDialog extends ConsumerWidget {
  const _TasksDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final tasks = ref.watch(tasksProvider);
    // Re-read each tick; also carries the "a run was due while the engine was
    // locked" flag surfaced in the footer below.
    final sched = ref.watch(schedulerProvider);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: DialogBody(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x5,
                Space.x4,
                Space.x2,
                Space.x3,
              ),
              child: Row(
                children: [
                  Icon(Icons.checklist_rounded, size: 20, color: c.primary),
                  const SizedBox(width: Space.x2),
                  Text(
                    'Saved tasks',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _newTask(context, ref),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New task'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    color: c.textMuted,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Expanded(
              child: tasks.isEmpty
                  ? _empty(c)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: Space.x1),
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: c.border),
                      itemBuilder: (_, i) => _TaskRow(task: tasks[i]),
                    ),
            ),
            if (tasks.any((t) => t.schedule != null)) ...[
              Divider(height: 1, color: c.border),
              if (sched.skippedWhileUnavailable != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.x5,
                    Space.x2,
                    Space.x5,
                    0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 13,
                        color: c.warning,
                      ),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: Text(
                          'A scheduled task was due while the engine was '
                          'locked — unlock to let it run.',
                          style: TextStyle(color: c.warning, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.x5,
                  vertical: Space.x2,
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 13, color: c.textFaint),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Text(
                        'Scheduled tasks run only while Airclone is open. A run '
                        'missed while it was closed starts once on next launch.',
                        style: TextStyle(color: c.textFaint, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty(AircloneColors c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rounded, size: 40, color: c.textFaint),
          const SizedBox(height: Space.x3),
          Text(
            'No saved tasks yet',
            style: TextStyle(
              color: c.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.x1),
          Text(
            'Open a source in the active pane and a destination in the other '
            'pane, then click "New task".',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textFaint, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Future<void> _newTask(BuildContext context, WidgetRef ref) async {
    final active = ref.read(activePaneProvider);
    final src = ref.read(paneProvider(active));
    final dst = ref.read(paneProvider(active == 0 ? 1 : 0));
    final messenger = ScaffoldMessenger.of(context);
    if (src.remote == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Open a source remote in the active pane first.'),
        ),
      );
      return;
    }
    if (dst.remote == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Open a destination remote in the OTHER pane first.'),
        ),
      );
      return;
    }
    final srcLabel = '${src.remote!.name}:${src.path}';
    final dstLabel = '${dst.remote!.name}:${dst.path}';
    final options = await showTransferOptionsDialog(
      context,
      fromLabel: srcLabel,
      toLabel: dstLabel,
    );
    if (options == null || !context.mounted) return;
    final name = await _promptName(context, '$srcLabel → $dstLabel');
    if (name == null) return;
    ref
        .read(tasksProvider.notifier)
        .add(
          TransferTask(
            id: TransferTask.newId(),
            name: name,
            srcFs: '${src.remote!.fs}${src.path}',
            srcLabel: srcLabel,
            dstFs: '${dst.remote!.fs}${dst.path}',
            dstLabel: dstLabel,
            options: options,
          ),
        );
  }

  Future<String?> _promptName(BuildContext context, String dflt) {
    final ctrl = TextEditingController(text: dflt);
    return showDialog<String>(
      context: context,
      builder: (dctx) {
        final c = AircloneTheme.of(dctx);
        String? result() => ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
        return AlertDialog(
          backgroundColor: c.surfaceRaised,
          title: const Text('Save task as'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Task name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
            onSubmitted: (_) => Navigator.of(dctx).pop(result()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(result()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    // Re-time the schedule labels below (due now / next / last ran) whenever the
    // scheduler ticks (~30 s) so they don't go stale while the dialog is open.
    ref.watch(schedulerProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x4,
        vertical: Space.x3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${task.options.mode.name} · '
                  '${task.srcLabel} → ${task.dstLabel}',
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.options.mode == TransferMode.bisync &&
                    !task.options.baselineEstablished) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 12,
                        color: c.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Needs first run — baseline not established',
                        style: TextStyle(
                          color: c.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
                if (task.schedule != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 12, color: c.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${task.schedule!.describe()} · ${_nextLabel(task)}',
                          style: TextStyle(
                            color: c.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                // Last-run outcome (manual or scheduled): a check/error glyph +
                // relative time, with a tooltip of the last few runs. Falls back
                // to the bare "last ran" when a scheduled task has no history yet.
                if (task.history.isNotEmpty)
                  _lastOutcome(c, task.history.first)
                else if (task.schedule != null && task.lastRun != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'last ran ${_lastRanLabel(task.lastRun)}',
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.x3),
          // Bisync escape hatch: once the baseline is established there's no other
          // way to force a fresh --resync, so a task whose listings rclone has
          // lost would fail forever. Only shown for already-baselined bisync tasks.
          if (task.options.mode == TransferMode.bisync &&
              task.options.baselineEstablished)
            IconButton(
              onPressed: () => _run(context, ref, reestablish: true),
              icon: const Icon(Icons.restart_alt, size: 18),
              color: c.textFaint,
              tooltip: 'Re-establish baseline…',
            ),
          IconButton(
            onPressed: () => showScheduleDialog(context, ref, task),
            icon: Icon(
              task.schedule == null ? Icons.alarm_add_outlined : Icons.alarm_on,
              size: 18,
            ),
            color: task.schedule == null ? c.textFaint : c.primary,
            tooltip: task.schedule == null ? 'Schedule…' : 'Edit schedule',
          ),
          FilledButton.icon(
            onPressed: () => _run(context, ref),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Run'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            ),
          ),
          IconButton(
            onPressed: () {
              // Best-effort: drop any OS Scheduled Task registered for this task
              // so a deleted task can't keep firing in the background while the
              // app is closed (Windows only; a no-op everywhere else).
              unawaited(
                ref.read(windowsTaskSchedulerProvider).unregister(task.id),
              );
              ref.read(tasksProvider.notifier).remove(task.id);
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            color: c.textFaint,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  /// Runs the task. A two-way (bisync) task that hasn't established its baseline
  /// shows a guarded confirm first, then runs `--resync`; on a successful
  /// (non-dry-run) baseline run it flips `baselineEstablished` so later runs are
  /// normal two-way syncs.
  ///
  /// [reestablish] forces that same guarded `--resync` confirm for a task whose
  /// baseline is *already* established — the escape hatch when rclone's listings
  /// are lost/corrupt and every normal run would otherwise fail forever. A
  /// successful non-dry re-resync leaves `baselineEstablished` true.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    bool reestablish = false,
  }) async {
    final svc = ref.read(transferServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    // Grab the container up front so supervising the run to a history record
    // outlives this dialog: a WidgetRef would tear the watcher down when the
    // tasks dialog closes — the same widget-lifecycle trap that can silently
    // drop the bisync baseline flip (phase-3 plan §3).
    final container = ProviderScope.containerOf(context, listen: false);
    final needsBaseline =
        task.options.mode == TransferMode.bisync &&
        !task.options.baselineEstablished;

    // Stamp lastRun on a scheduled task the instant before we actually dispatch
    // (mirrors the scheduler tick + headless runOne) so manually running a slot
    // that is "due now" advances the anchor — otherwise the next tick (<=30s)
    // sees it still due and fires a second, scheduled run right behind this
    // manual one. Read the LIVE task first so the stamp doesn't clobber history
    // added since build. Called dispatch-adjacent (not at the top) so a cancel
    // of the baseline dialog below doesn't advance the anchor for a run that
    // never happened.
    void stampScheduledRun() {
      if (task.schedule == null) return;
      final notifier = ref.read(tasksProvider.notifier);
      final cur =
          ref.read(tasksProvider).where((t) => t.id == task.id).firstOrNull ??
          task;
      notifier.update(cur.copyWith(lastRun: DateTime.now()));
    }

    final int jobId;
    if (!needsBaseline && !reestablish) {
      stampScheduledRun();
      jobId = await svc.transferAdvancedRaw(
        srcFs: task.srcFs,
        dstFs: task.dstFs,
        srcLabel: task.srcLabel,
        dstLabel: task.dstLabel,
        options: task.options,
      );
      messenger.showSnackBar(SnackBar(content: Text('Started "${task.name}"')));
    } else {
      final choice = await showBaselineDialog(context, task);
      if (choice == null || !context.mounted) return;
      stampScheduledRun();
      jobId = await svc.transferAdvancedRaw(
        srcFs: task.srcFs,
        dstFs: task.dstFs,
        srcLabel: task.srcLabel,
        dstLabel: task.dstLabel,
        options: task.options.copyWith(
          resyncMode: choice.resyncMode,
          dryRun: choice.dryRun,
        ),
        forceResync: true,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            choice.dryRun
                ? 'Dry-run baseline for "${task.name}" started'
                : 'Establishing baseline for "${task.name}"…',
          ),
        ),
      );
      // A dry-run proves nothing on disk, so it must NOT mark the baseline done.
      if (!choice.dryRun) _flipBaselineOnSuccess(ref, jobId);
    }

    // Supervise the dispatched job to a terminal state and append the outcome to
    // this task's per-run history — the same path the scheduler uses.
    unawaited(
      recordRunOutcome(
        readClient: () => container.read(engineControllerProvider).client,
        tasks: container.read(tasksProvider.notifier),
        readJobs: () => container.read(jobsControllerProvider),
        taskId: task.id,
        jobId: jobId,
      ),
    );
  }

  /// Watches [jobId] to a terminal state; on success, records that this task's
  /// two-way baseline is now established (so subsequent runs don't re-resync).
  void _flipBaselineOnSuccess(WidgetRef ref, int jobId) {
    late final ProviderSubscription<List<Job>> sub;
    sub = ref.listenManual(jobsControllerProvider, (_, jobs) {
      Job? job;
      for (final j in jobs) {
        if (j.id == jobId) {
          job = j;
          break;
        }
      }
      if (job == null) return;
      if (job.status == JobStatus.success) {
        // Read the CURRENT task before flipping — the build-time `task` snapshot
        // carries a stale history, and recordRunOutcome (which supervises the
        // SAME job on its own poller) may have prepended this run's success
        // record first. A full-replace from the snapshot would clobber that
        // record (lost update); read-modify-write on the live task preserves it.
        final notifier = ref.read(tasksProvider.notifier);
        final cur =
            ref.read(tasksProvider).where((t) => t.id == task.id).firstOrNull ??
            task;
        notifier.update(
          cur.copyWith(
            options: cur.options.copyWith(baselineEstablished: true),
          ),
        );
        sub.close();
      } else if (job.status == JobStatus.failed ||
          job.status == JobStatus.canceled) {
        sub.close();
      }
    });
  }

  /// The last-run outcome line: a status glyph + relative time (red "· failed"
  /// on a failure), wrapped in a tooltip listing the most recent runs.
  Widget _lastOutcome(AircloneColors c, TaskRunRecord last) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Tooltip(
      message: _historyTooltip(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            last.ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 12,
            color: last.ok ? c.success : c.error,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'last ran ${_lastRanLabel(last.at)}${last.ok ? '' : ' · failed'}',
              style: TextStyle(
                color: last.ok ? c.textFaint : c.error,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );

  /// A compact multi-line summary of the last few runs for the outcome tooltip
  /// (✓/✗ · when · how long · error text on failures).
  String _historyTooltip() => [
    for (final r in task.history.take(5))
      [
        r.ok ? '✓' : '✗',
        _lastRanLabel(r.at),
        if (r.duration > Duration.zero) _fmtRunDuration(r.duration),
        if (r.error != null) r.error!,
      ].join(' · '),
  ].join('\n');
}

/// The one-time two-way baseline confirm. Shows which concrete location is
/// Path1 vs Path2 (and that Path1/active wins by default), a resync-mode
/// choice, and a Dry-run-first option. Returns null on cancel.
Future<({String resyncMode, bool dryRun})?> showBaselineDialog(
  BuildContext context,
  TransferTask task,
) {
  var mode = task.options.resyncMode;
  return showDialog<({String resyncMode, bool dryRun})>(
    context: context,
    builder: (dctx) {
      final c = AircloneTheme.of(dctx);
      return StatefulBuilder(
        builder: (dctx, setState) => AlertDialog(
          backgroundColor: c.surfaceRaised,
          title: const Text('Establish two-way baseline'),
          content: DialogBody(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The first two-way sync matches both sides. The winning side '
                  'overwrites differing files on the other; deletions are not '
                  'propagated on this run. This cannot be undone.',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                const SizedBox(height: Space.x3),
                _pathRow(c, 'Path1', task.srcLabel),
                _pathRow(c, 'Path2', task.dstLabel),
                const SizedBox(height: Space.x3),
                Text(
                  'On conflict, this side wins:',
                  style: TextStyle(color: c.text, fontSize: 12),
                ),
                const SizedBox(height: Space.x1),
                DropdownButton<String>(
                  value: mode,
                  isExpanded: true,
                  dropdownColor: c.surfaceRaised,
                  items: const [
                    DropdownMenuItem(
                      value: 'path1',
                      child: Text('Path1 wins (the "From" side)'),
                    ),
                    DropdownMenuItem(
                      value: 'path2',
                      child: Text('Path2 wins (the other side)'),
                    ),
                    DropdownMenuItem(value: 'newer', child: Text('Newer wins')),
                    DropdownMenuItem(value: 'older', child: Text('Older wins')),
                  ],
                  onChanged: (v) => setState(() => mode = v ?? mode),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(dctx).pop((resyncMode: mode, dryRun: true)),
              child: const Text('Dry run first'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dctx).pop((resyncMode: mode, dryRun: false)),
              child: const Text('Establish baseline'),
            ),
          ],
        ),
      );
    },
  );
}

Widget _pathRow(AircloneColors c, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 2),
  child: Row(
    children: [
      SizedBox(
        width: 48,
        child: Text(
          label,
          style: TextStyle(
            color: c.textFaint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
      ),
    ],
  ),
);

/// "due now" or "next today 18:00" for a scheduled task's status line.
String _nextLabel(TransferTask task) {
  final s = task.schedule!;
  final now = DateTime.now();
  if (isDue(s, now: now, lastRun: task.lastRun)) return 'due now';
  return 'next ${_fmtNext(nextRun(s, from: now, lastRun: task.lastRun))}';
}

/// "just now" / "5 min ago" / "2 h ago" / "3 d ago" / "never" for a task's
/// persisted [lastRun] on the schedule status line.
String _lastRanLabel(DateTime? lastRun) {
  if (lastRun == null) return 'never';
  final d = DateTime.now().difference(lastRun);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// "1.2s" / "3m 05s" / "1h 04m" for a run's wall-clock [Duration] in the
/// history tooltip.
String _fmtRunDuration(Duration d) {
  if (d.inSeconds < 60) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  if (d.inMinutes < 60) {
    return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  }
  return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
}

String _fmtNext(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'today $hh:$mm';
  if (diff == 1) return 'tomorrow $hh:$mm';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[(dt.weekday - 1) % 7]} $hh:$mm';
}

/// Opens the per-task schedule editor.
Future<void> showScheduleDialog(
  BuildContext context,
  WidgetRef ref,
  TransferTask task,
) => showDialog(
  context: context,
  builder: (_) => _ScheduleDialog(task: task),
);

const _intervalPresets = <(int, String)>[
  (15, '15 minutes'),
  (30, '30 minutes'),
  (60, 'hour'),
  (120, '2 hours'),
  (360, '6 hours'),
  (720, '12 hours'),
  (1440, '24 hours'),
];

class _ScheduleDialog extends ConsumerStatefulWidget {
  const _ScheduleDialog({required this.task});
  final TransferTask task;

  @override
  ConsumerState<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends ConsumerState<_ScheduleDialog> {
  late bool _on;
  late ScheduleKind _kind;
  late int _interval;
  late int _hour;
  late int _minute;
  late Set<int> _weekdays;

  /// Windows-only: also register this schedule as an OS Scheduled Task so it runs
  /// while Airclone is closed. Task Scheduler itself is the source of truth (we
  /// persist nothing on the model), so the box is seeded from an [isRegistered]
  /// probe on open.
  bool _runWhileClosed = false;

  /// True once the user has toggled the checkbox themselves. The async
  /// [isRegistered] probe (a real `schtasks /Query` process spawn, 100ms–1s+)
  /// must NOT overwrite a fresh user tick with its result, so it only seeds
  /// [_runWhileClosed] while this is false.
  bool _userTouchedClosed = false;

  /// True while the open-time [isRegistered] probe is still in flight. Save is
  /// disabled until it resolves so a fast Save can't take the unregister branch
  /// on the stale `false` default and silently delete a task the user meant to
  /// keep (the probe hadn't yet learned the true registration state).
  bool _probing = false;

  /// A short `schtasks` failure surfaced under the checkbox (never crashes the
  /// dialog); null while healthy.
  String? _osError;

  /// Set when "run while closed" is ticked on an ENCRYPTED config whose password
  /// isn't available for an unattended unlock (empty vault): a background run
  /// would fail exit-2 every fire with no history trace, so we block Save and
  /// point the user at "Remember config password". Null when not blocked.
  String? _bgPasswordError;

  /// True while a register/unregister is in flight — disables Save so a slow
  /// `schtasks` can't be double-submitted.
  bool _osBusy = false;

  /// Whether OS-level background scheduling is offered here. Windows is the only
  /// platform wired to the headless `--run-task` CLI so far.
  bool get _canOsSchedule => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    final s = widget.task.schedule;
    _on = s != null;
    _kind = s?.kind ?? ScheduleKind.interval;
    _interval = s?.intervalMinutes ?? 360;
    _hour = s?.hour ?? 9;
    _minute = s?.minute ?? 0;
    _weekdays = {...?s?.weekdays};
    if (_weekdays.isEmpty) _weekdays = {DateTime.now().weekday};
    if (_canOsSchedule) {
      _probing = true;
      unawaited(_probeRegistered());
    }
  }

  /// Reflects an already-registered Scheduled Task into the checkbox so re-opening
  /// the editor shows the true current state. Only seeds the box when the user
  /// hasn't already toggled it (so a slow probe can't clobber a fresh tick), and
  /// always clears [_probing] so Save re-enables.
  Future<void> _probeRegistered() async {
    final reg = await ref
        .read(windowsTaskSchedulerProvider)
        .isRegistered(widget.task.id);
    if (!mounted) return;
    setState(() {
      _probing = false;
      if (!_userTouchedClosed) _runWhileClosed = reg;
    });
  }

  /// Whether enabling "run while closed" right now would produce a background
  /// task that can never unlock the config unattended: the config is encrypted
  /// but the OS vault holds no password. In a running GUI a non-null cache
  /// passphrase is set ONLY by a successful encrypted unlock
  /// ([EngineController._startWith]), so it doubles as the "config is encrypted"
  /// signal here without a fresh rclone probe; combined with an empty vault it
  /// means every scheduled fire would exit 2 with no history entry.
  Future<bool> _backgroundUnlockBlocked() async {
    final encrypted = ref.read(cachePassphraseProvider) != null;
    if (!encrypted) return false;
    final stored = await ref.read(configPasswordVaultProvider).read();
    return stored == null || stored.isEmpty;
  }

  /// Re-checks the encrypted-config/empty-vault gate and surfaces (or clears)
  /// the inline block. Returns whether a background run is blocked. Kept off the
  /// toggle's synchronous path since the vault read is async.
  Future<bool> _refreshBgPasswordGate() async {
    final blocked = await _backgroundUnlockBlocked();
    if (!mounted) return blocked;
    setState(() {
      _bgPasswordError = (_runWhileClosed && blocked)
          ? 'This config is encrypted and no password is stored, so a '
                'background run could never unlock it. Enable "Remember config '
                'password" in Settings first.'
          : null;
    });
    return blocked;
  }

  Future<void> _save() async {
    final notifier = ref.read(tasksProvider.notifier);
    final TransferTask updated;
    if (!_on) {
      updated = widget.task.copyWith(schedule: null);
    } else {
      updated = widget.task.copyWith(
        schedule: TaskSchedule(
          kind: _kind,
          intervalMinutes: _interval,
          hour: _hour,
          minute: _minute,
          weekdays: _kind == ScheduleKind.weekly
              ? (_weekdays.toList()..sort())
              : const [],
        ),
        // Reset the clock so a slot already past today doesn't fire instantly.
        lastRun: DateTime.now(),
      );
    }
    // Reconcile the OS Scheduled Task BEFORE persisting the model, so a schtasks
    // failure (or a blocked encrypted config) can't leave the in-app schedule
    // committed while the OS registration diverges — and a Cancel afterwards
    // then wouldn't have an already-saved schedule to run behind a stale/absent
    // OS task. An enabled schedule with the box ticked (re-)registers (/Create
    // /F overwrites, so this also picks up an edited schedule); anything else
    // (schedule off, or box unticked) unregisters. Failures surface inline and
    // keep the dialog open rather than silently losing the choice.
    if (_canOsSchedule) {
      final os = ref.read(windowsTaskSchedulerProvider);
      if (_on && _runWhileClosed) {
        // Refuse to register a background task for an encrypted config with no
        // stored password: every fire would exit 2 unattended with no history
        // entry. Block Save and point the user at "Remember config password".
        if (await _refreshBgPasswordGate()) return;
        setState(() {
          _osBusy = true;
          _osError = null;
        });
        final res = await os.register(updated);
        if (!res.ok) {
          if (mounted) {
            setState(() {
              _osBusy = false;
              _osError = res.error;
            });
          }
          return;
        }
      } else {
        await os.unregister(widget.task.id);
      }
    }

    // OS side reconciled cleanly — now commit the model change and close.
    notifier.update(updated);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked != null) {
      setState(() {
        _hour = picked.hour;
        _minute = picked.minute;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final intervals = {
      for (final (m, _) in _intervalPresets) m,
      _interval,
    }.toList()..sort();
    final time =
        '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: Text('Schedule "${widget.task.name}"'),
      content: DialogBody(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Run automatically on a schedule'),
              value: _on,
              onChanged: (v) => setState(() => _on = v),
            ),
            if (_on) ...[
              const SizedBox(height: Space.x2),
              Wrap(
                spacing: Space.x2,
                children: [
                  for (final k in ScheduleKind.values)
                    ChoiceChip(
                      label: Text(switch (k) {
                        ScheduleKind.interval => 'Interval',
                        ScheduleKind.daily => 'Daily',
                        ScheduleKind.weekly => 'Weekly',
                      }),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: Space.x3),
              if (_kind == ScheduleKind.interval)
                Row(
                  children: [
                    Text('Every', style: TextStyle(color: c.textMuted)),
                    const SizedBox(width: Space.x3),
                    DropdownButton<int>(
                      value: _interval,
                      dropdownColor: c.surfaceRaised,
                      borderRadius: BorderRadius.circular(Radii.md),
                      items: [
                        for (final m in intervals)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              _intervalPresets
                                      .where((p) => p.$1 == m)
                                      .map((p) => p.$2)
                                      .firstOrNull ??
                                  '$m minutes',
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _interval = v ?? _interval),
                    ),
                  ],
                )
              else ...[
                if (_kind == ScheduleKind.weekly) ...[
                  Text('On days', style: TextStyle(color: c.textMuted)),
                  const SizedBox(height: Space.x2),
                  Wrap(
                    spacing: Space.x1,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(
                            const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d - 1],
                          ),
                          selected: _weekdays.contains(d),
                          onSelected: (sel) => setState(() {
                            sel ? _weekdays.add(d) : _weekdays.remove(d);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.x3),
                ],
                Row(
                  children: [
                    Text('At', style: TextStyle(color: c.textMuted)),
                    const SizedBox(width: Space.x3),
                    OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(time),
                    ),
                  ],
                ),
              ],
              // Windows only: opt into an OS Scheduled Task so the run fires even
              // with Airclone closed. Only meaningful when a schedule is set, so
              // it lives inside the `_on` block.
              if (_canOsSchedule) ...[
                const SizedBox(height: Space.x2),
                Divider(height: 1, color: c.border),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Also run while Airclone is closed'),
                  subtitle: Text(
                    'Registers a Windows Scheduled Task that runs this task in '
                    'the background; missed runs start as soon as the PC is '
                    'available.',
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                  value: _runWhileClosed,
                  onChanged: (v) {
                    setState(() {
                      _userTouchedClosed = true;
                      _runWhileClosed = v ?? false;
                      if (!_runWhileClosed) _bgPasswordError = null;
                    });
                    // Ticking ON: verify an encrypted config actually has a
                    // stored password for the unattended unlock (async vault
                    // read), and surface an inline block if not.
                    if (_runWhileClosed) unawaited(_refreshBgPasswordGate());
                  },
                ),
                if (_bgPasswordError != null)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.x1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: c.warning,
                        ),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: Text(
                            _bgPasswordError!,
                            style: TextStyle(color: c.warning, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_osError != null)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.x1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, size: 13, color: c.error),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: Text(
                            'Could not register the background task: $_osError',
                            style: TextStyle(color: c.error, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
            const SizedBox(height: Space.x3),
            // Base-case caveat — suppressed once an OS Scheduled Task is opted in
            // above, where the closed-app behaviour no longer applies.
            if (!(_canOsSchedule && _on && _runWhileClosed))
              Text(
                'Runs only while Airclone is open — there is no background '
                'service. A missed run starts once on next launch.',
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Disabled while the registration probe is still resolving (so a fast
          // Save can't unregister on the stale default), while a schtasks call
          // is in flight, or with a weekly schedule and no weekday chosen.
          onPressed:
              (_osBusy ||
                  _probing ||
                  (_on && _kind == ScheduleKind.weekly && _weekdays.isEmpty))
              ? null
              : () => _save(),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
