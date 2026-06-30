import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../state/browser_controller.dart';
import '../state/jobs_controller.dart';
import '../state/task_schedule.dart';
import '../state/tasks_controller.dart';
import '../state/transfer_options.dart';
import '../state/transfer_service.dart';
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
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
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
            id: DateTime.now().microsecondsSinceEpoch.toString(),
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
              ],
            ),
          ),
          const SizedBox(width: Space.x3),
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
            onPressed: () => ref.read(tasksProvider.notifier).remove(task.id),
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
  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(transferServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final needsBaseline =
        task.options.mode == TransferMode.bisync &&
        !task.options.baselineEstablished;

    if (!needsBaseline) {
      svc.transferAdvancedRaw(
        srcFs: task.srcFs,
        dstFs: task.dstFs,
        srcLabel: task.srcLabel,
        dstLabel: task.dstLabel,
        options: task.options,
      );
      messenger.showSnackBar(SnackBar(content: Text('Started "${task.name}"')));
      return;
    }

    final choice = await showBaselineDialog(context, task);
    if (choice == null || !context.mounted) return;
    final jobId = await svc.transferAdvancedRaw(
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
        ref
            .read(tasksProvider.notifier)
            .update(
              task.copyWith(
                options: task.options.copyWith(baselineEstablished: true),
              ),
            );
        sub.close();
      } else if (job.status == JobStatus.failed ||
          job.status == JobStatus.canceled) {
        sub.close();
      }
    });
  }
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
          content: SizedBox(
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
  }

  void _save() {
    final notifier = ref.read(tasksProvider.notifier);
    if (!_on) {
      notifier.update(widget.task.copyWith(schedule: null));
    } else {
      notifier.update(
        widget.task.copyWith(
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
        ),
      );
    }
    Navigator.of(context).pop();
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
      content: SizedBox(
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
            ],
            const SizedBox(height: Space.x3),
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
          onPressed: (_on && _kind == ScheduleKind.weekly && _weekdays.isEmpty)
              ? null
              : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
