import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/android_work_channel.dart';
import '../state/android_work_registration.dart';
import '../state/android_work_settings.dart';
import '../state/engine_controller.dart';
import '../state/jobs_controller.dart';
import '../state/local_locations.dart';
import '../state/photo_backup.dart';
import '../state/poll_cadence.dart';
import '../state/scheduler_controller.dart';
import '../state/scheduling_policy.dart';
import '../state/task_kind.dart';
import '../state/task_schedule.dart';
import '../state/tasks_controller.dart';
import '../state/transfer_service.dart';
import 'destination_picker.dart';
import 'dialog_body.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// Settings → Automation, Android only: **Back up your photos** and
/// **Background on this phone**.
///
/// Two things in one section because they are one story on a phone: the
/// photo backup is the reason background execution exists here, and the
/// Wi-Fi / charging constraints are what make it safe to leave on. Reads
/// "Back up your photos" against the existing "Back up your remotes" (config)
/// and the Phase E "Back up your files" — three different things, and the
/// words are what keep them apart.
class PhotoBackupSection extends ConsumerWidget {
  const PhotoBackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final c = AircloneTheme.of(context);
    final tasks = ref.watch(tasksProvider);
    final photo = tasks.where((t) => t.kind == TaskKind.photos).firstOrNull;
    final constraints = ref.watch(androidWorkSettingsProvider);
    final plan = planAndroidWork(
      tasks: tasks,
      constraints: constraints,
      pollMinutes: ref.watch(pollCadenceProvider),
      optInOffered: canRunWhileClosed,
    );
    // Re-times "last ran" / "next" on every scheduler tick.
    ref.watch(schedulerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(
          'Back up your photos',
          help:
              'Copies your camera roll (and any folders you add) to a remote, '
              'on a schedule. Copy only — nothing on the phone is ever moved '
              'or deleted.',
        ),
        if (photo == null)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => showPhotoBackupDialog(context),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Set up photo backup…'),
            ),
          )
        else
          _PhotoBackupCard(task: photo),
        const SizedBox(height: Space.x4),
        _Label('Background on this phone', help: androidWorkExplanation(plan)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Only on Wi-Fi'),
          subtitle: const Text('Never on mobile data.'),
          value: constraints.unmetered,
          onChanged: (v) =>
              ref.read(androidWorkSettingsProvider.notifier).setUnmetered(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Only while charging'),
          value: constraints.charging,
          onChanged: (v) =>
              ref.read(androidWorkSettingsProvider.notifier).setCharging(v),
        ),
        const SizedBox(height: Space.x2),
        _WorkStatusLine(color: c.textFaint),
        if (plan.desired)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _runInBackground(context, ref),
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('Run due tasks in background now'),
            ),
          ),
      ],
    );
  }

  Future<void> _runInBackground(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(androidWorkProvider).runOnce();
    ref.invalidate(androidWorkStatusProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Queued. Android runs it in the background in a moment; the '
                    'outcome lands in the task’s history and in the line above.'
              : 'Could not queue a background run.',
        ),
      ),
    );
  }
}

/// "in 12m" / "in 3h" for a future time, "5m ago" for a past one — the
/// shared [relativeTime] only knows the past, and a future time fed to it
/// reads as "now".
String _when(DateTime t) {
  final now = DateTime.now();
  if (t.isAfter(now)) {
    final d = t.difference(now);
    if (d.inMinutes < 1) return 'any moment';
    if (d.inHours < 1) return 'in ${d.inMinutes}m';
    if (d.inDays < 1) return 'in ${d.inHours}h';
    return 'in ${d.inDays}d';
  }
  final r = relativeTime(t);
  // relativeTime says "now" inside a minute; "now ago" is not a phrase.
  return r == 'now' ? 'just now' : '$r ago';
}

class _Label extends StatelessWidget {
  const _Label(this.label, {this.help});
  final String label;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (help != null) ...[
            const SizedBox(height: 2),
            Text(help!, style: TextStyle(color: c.textFaint, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

/// What WorkManager holds right now, and what the last background wake did.
class _WorkStatusLine extends ConsumerWidget {
  const _WorkStatusLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(androidWorkStatusProvider);
    final text = status.when(
      loading: () => 'Checking Android’s schedule…',
      error: (e, _) => 'Could not read Android’s schedule: $e',
      data: (s) {
        final parts = <String>[
          if (s.error != null)
            'Could not read Android’s schedule: ${s.error}'
          else if (s.enqueued)
            'Registered with Android'
                '${s.nextRunAt != null ? ' · next wake ${_when(s.nextRunAt!)}' : ''}'
          else
            'Not registered with Android',
          if (s.lastRunAt != null)
            'Last background wake ${_when(s.lastRunAt!)}: '
                '${switch (s.lastExitCode) {
                  0 => 'ok',
                  1 => 'a task failed',
                  2 => 'could not start',
                  _ => 'unknown',
                }}'
                '${s.lastDetail != null && s.lastDetail!.isNotEmpty ? ' — ${s.lastDetail}' : ''}',
        ];
        return parts.join('\n');
      },
    );
    return Text(text, style: TextStyle(color: color, fontSize: 11));
  }
}

class _PhotoBackupCard extends ConsumerWidget {
  const _PhotoBackupCard({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final spec = photoBackupSpecOf(task) ?? PhotoBackupSpec.defaults;
    final last = task.history.isNotEmpty ? task.history.first : null;
    final s = task.schedule;
    final now = DateTime.now();
    final next = s == null
        ? null
        : nextRun(s, from: now, lastRun: task.lastRun);
    final faint = TextStyle(color: c.textFaint, fontSize: 11);
    final body = TextStyle(color: c.text, fontSize: 12);

    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: body,
          children: [
            TextSpan(text: '$k  ', style: faint),
            TextSpan(text: v),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('To', task.dstFs),
          row(
            'From',
            spec.folders.isEmpty
                ? 'no folders — edit to add one'
                : spec.folders.join(', '),
          ),
          row('Videos', spec.includeVideos ? 'included' : 'skipped'),
          row('Runs', s?.describe() ?? 'by hand only'),
          if (next != null && s != null)
            row(
              'Next',
              isDue(s, now: now, lastRun: task.lastRun)
                  ? 'due now'
                  : _when(next),
            ),
          row(
            'Last run',
            last == null
                ? 'never'
                : '${_when(last.at)} · '
                      '${last.ok ? 'ok' : 'failed'}'
                      '${last.error != null ? ' — ${last.error}' : ''}',
          ),
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x2,
            children: [
              OutlinedButton(
                onPressed: () => showPhotoBackupDialog(context, existing: task),
                child: const Text('Edit…'),
              ),
              OutlinedButton(
                onPressed: () => _runNow(context, ref),
                child: const Text('Run now'),
              ),
              TextButton(
                onPressed: () => _remove(context, ref),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dispatches the backup from inside the app, supervised to a history record
  /// exactly as the tasks panel's own Run does. The run outlives this widget
  /// on purpose (the container, not the ref, is captured).
  Future<void> _runNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    if (container.read(engineControllerProvider).client == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The engine is not ready yet.')),
      );
      return;
    }
    final notifier = container.read(tasksProvider.notifier);
    final live = container
        .read(tasksProvider)
        .where((t) => t.id == task.id)
        .firstOrNull;
    if (live == null) return;
    // Stamp lastRun dispatch-adjacent so the next tick does not fire a second,
    // scheduled run right behind this manual one.
    if (live.schedule != null) {
      notifier.update(live.copyWith(lastRun: DateTime.now()));
    }
    final jobId = await container
        .read(transferServiceProvider)
        .transferAdvancedRaw(
          srcFs: live.srcFs,
          dstFs: live.dstFs,
          srcLabel: live.srcLabel,
          dstLabel: live.dstLabel,
          options: backupOptions(live.options),
        );
    messenger.showSnackBar(
      const SnackBar(content: Text('Photo backup started — see Transfers.')),
    );
    unawaited(
      recordRunOutcome(
        readClient: () => container.read(engineControllerProvider).client,
        tasks: notifier,
        readJobs: () => container.read(jobsControllerProvider),
        taskId: live.id,
        jobId: jobId,
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop backing up photos?'),
        content: const Text(
          'The schedule is removed. Nothing already copied to the remote is '
          'touched, and nothing on the phone is either.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(tasksProvider.notifier).remove(task.id);
  }
}

/// The three-answer flow: where, which folders, how often. Opens, asks, and
/// closes — it is not the advanced transfer dialog and must not become it.
Future<void> showPhotoBackupDialog(
  BuildContext context, {
  TransferTask? existing,
}) => showDialog<void>(
  context: context,
  builder: (_) => _PhotoBackupDialog(existing: existing),
);

class _PhotoBackupDialog extends ConsumerStatefulWidget {
  const _PhotoBackupDialog({this.existing});
  final TransferTask? existing;

  @override
  ConsumerState<_PhotoBackupDialog> createState() => _PhotoBackupDialogState();
}

class _PhotoBackupDialogState extends ConsumerState<_PhotoBackupDialog> {
  late PhotoBackupSpec _spec;
  String? _dstFs;
  late int _intervalMinutes;
  String _deviceName = 'Android';
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _spec =
        (e == null ? null : photoBackupSpecOf(e)) ?? PhotoBackupSpec.defaults;
    _dstFs = e?.dstFs;
    final s = e?.schedule;
    _intervalMinutes = s?.kind == ScheduleKind.interval
        ? s!.intervalMinutes
        : kPhotoBackupDefaultSchedule.intervalMinutes;
    unawaited(
      photoBackupDeviceName().then((n) {
        if (mounted) setState(() => _deviceName = n);
      }),
    );
  }

  Future<void> _pickDestination() async {
    final picked = await showDestinationPicker(
      context,
      title: 'Where to keep the photos',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dstFs = photoBackupDestination(
        remoteFs: picked.remote.fs,
        path: picked.path,
        deviceName: _deviceName,
      );
      _error = null;
    });
  }

  Future<void> _addFolder() async {
    final picked = await showDestinationPicker(
      context,
      title: 'Add a folder to back up',
    );
    if (picked == null || !mounted) return;
    final rel = picked.remote.isLocal
        ? relativePhotoFolder(
            '${picked.remote.fs}${picked.path}',
            androidStorageRoot,
          )
        : null;
    setState(() {
      if (rel == null) {
        _error =
            'Only folders on this phone’s internal storage can be backed '
            'up here.';
      } else if (_spec.folders.contains(rel)) {
        _error = '$rel is already in the list.';
      } else {
        _spec = _spec.copyWith(folders: [..._spec.folders, rel]);
        _error = null;
      }
    });
  }

  void _save() {
    final dst = _dstFs;
    if (dst == null) {
      setState(() => _error = 'Choose where to keep the photos first.');
      return;
    }
    if (_spec.folders.isEmpty) {
      setState(() => _error = 'Add at least one folder.');
      return;
    }
    final e = widget.existing;
    final task = buildPhotoBackupTask(
      id: e?.id,
      storageRoot: androidStorageRoot,
      spec: _spec,
      dstFs: dst,
      schedule: TaskSchedule(
        kind: ScheduleKind.interval,
        intervalMinutes: _intervalMinutes,
      ),
      lastRun: e?.lastRun,
      history: e?.history ?? const [],
    );
    final tasks = ref.read(tasksProvider.notifier);
    if (e == null) {
      tasks.add(task);
    } else {
      tasks.update(task);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final faint = TextStyle(color: c.textFaint, fontSize: 11);
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Back up your photos' : 'Edit photo backup',
      ),
      content: DialogBody(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Where', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: Space.x1),
              Text(
                _dstFs ?? 'Not chosen yet — a cloud remote is the point.',
                style: _dstFs == null ? faint : null,
              ),
              const SizedBox(height: Space.x1),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _pickDestination,
                  child: Text(_dstFs == null ? 'Choose…' : 'Change…'),
                ),
              ),
              Text(
                'Photos land in Airclone/Photos/${deviceFolderName(_deviceName)} '
                'there, mirroring the folders below.',
                style: faint,
              ),
              const SizedBox(height: Space.x4),
              Text('What', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: Space.x1),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x1,
                children: [
                  for (final f in _spec.folders)
                    InputChip(
                      label: Text(f == kCameraRollFolder ? 'Camera roll' : f),
                      onDeleted: () => setState(
                        () => _spec = _spec.copyWith(
                          folders: [
                            for (final x in _spec.folders)
                              if (x != f) x,
                          ],
                        ),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Add folder'),
                    onPressed: _addFolder,
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Include videos'),
                subtitle: const Text(
                  'They are most of the bytes, and most of the first run.',
                ),
                value: _spec.includeVideos,
                onChanged: (v) =>
                    setState(() => _spec = _spec.copyWith(includeVideos: v)),
              ),
              const SizedBox(height: Space.x2),
              Text('How often', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: Space.x1),
              DropdownButton<int>(
                value: kPhotoBackupIntervalChoices.contains(_intervalMinutes)
                    ? _intervalMinutes
                    : kPhotoBackupDefaultSchedule.intervalMinutes,
                isDense: true,
                // Fill the column rather than size to content: a non-expanded
                // dropdown in a phone-width dialog overflows its own row by a
                // few pixels (caught by photo_backup_dialog_test at 375dp).
                isExpanded: true,
                items: [
                  for (final m in kPhotoBackupIntervalChoices)
                    DropdownMenuItem(
                      value: m,
                      child: Text(
                        TaskSchedule(
                          kind: ScheduleKind.interval,
                          intervalMinutes: m,
                        ).describe(),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _intervalMinutes = v);
                },
              ),
              Text(
                'Runs in the background on Wi-Fi by default — see "Background '
                'on this phone" in Settings to change that.',
                style: faint,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.x2),
                Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.existing == null ? 'Start backing up' : 'Save'),
        ),
      ],
    );
  }
}
