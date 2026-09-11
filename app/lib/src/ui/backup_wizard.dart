import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/backup_task.dart';
import '../state/device_name.dart';
import '../state/poll_cadence.dart';
import '../state/scheduler_registration.dart';
import '../state/scheduling_policy.dart';
import '../state/task_schedule.dart';
import '../state/tasks_controller.dart';
import '../state/windows_task_scheduler.dart';
import 'destination_picker.dart';
import 'dialog_body.dart';
import 'from_to_picker.dart';
import 'theme/tokens.dart';

/// "Back up a folder" — three answers, then done.
///
/// Deliberately **not** the advanced transfer dialog, and deliberately not a
/// door to it. What makes this a backup rather than a transfer with softer words
/// is that the destructive options are not reachable from here at all: mode,
/// dry-run and the version-keeping toggle are decided by [buildBackupTask] and
/// enforced again when the task runs.
///
/// Not advanced-gated. "Back up a folder" is a concept an ordinary user has;
/// "a saved transfer task with a TransferOptions payload" is not, and that split
/// is the whole reason this screen exists separately.
Future<bool> showBackupWizard(BuildContext context) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => const _BackupWizard(),
  );
  return created ?? false;
}

class _BackupWizard extends ConsumerStatefulWidget {
  const _BackupWizard();

  @override
  ConsumerState<_BackupWizard> createState() => _BackupWizardState();
}

class _BackupWizardState extends ConsumerState<_BackupWizard> {
  FolderRef? _source;
  FolderRef? _dest;

  /// How often. Daily is the default because a backup people forget about is
  /// the point of the feature, and "every N hours" is a transfer habit rather
  /// than a backup one.
  ScheduleKind _kind = ScheduleKind.daily;
  int _hour = 2;
  int _minute = 0;
  int _intervalMinutes = 360;

  /// Only offered where it can actually be honoured.
  bool _runWhileClosed = canRunWhileClosed;

  bool _busy = false;

  /// This device's per-device path segment, resolved once.
  ///
  /// Asked of the platform rather than taken from `Platform.localHostname`,
  /// which on Android is the constant `localhost` — so every Android phone
  /// would back up into the same folder, which is the merge the segment exists
  /// to prevent. [backupDeviceName] is the one answer camera-roll backup uses
  /// too, deliberately.
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    backupDeviceName().then((n) {
      if (mounted) setState(() => _deviceName = n);
    });
  }

  /// Where this backup will write, shown before anything is created.
  ///
  /// A user should be able to see the folder their files are about to land in
  /// rather than discover it afterwards by browsing.
  String? get _destinationPreview {
    final s = _source;
    final d = _dest;
    final device = _deviceName;
    if (s == null || d == null || device == null) return null;
    final path = backupDestinationPath(
      destPath: d.path,
      deviceName: device,
      sourceRemoteName: s.remote.name,
      sourcePath: s.path,
    );
    return '${d.remote.name}:$path';
  }

  bool get _ready =>
      _source != null && _dest != null && _deviceName != null && !_busy;

  TaskSchedule get _schedule => TaskSchedule(
    kind: _kind,
    intervalMinutes: _intervalMinutes,
    hour: _hour,
    minute: _minute,
    // Weekly is not offered here: a backup that runs once a week is a backup
    // that is six days stale when you need it, and the raw task editor is
    // still there for someone who genuinely wants it.
    weekdays: const [],
  );

  Future<void> _pick({required bool source}) async {
    final picked = await showDestinationPicker(
      context,
      title: source ? 'Which folder to back up' : 'Where to keep the backup',
    );
    if (picked == null || !mounted) return;
    setState(() => source ? _source = picked : _dest = picked);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (t == null || !mounted) return;
    setState(() {
      _hour = t.hour;
      _minute = t.minute;
    });
  }

  Future<void> _create() async {
    final s = _source!;
    final d = _dest!;
    setState(() => _busy = true);

    final destPath = backupDestinationPath(
      destPath: d.path,
      deviceName: _deviceName!,
      sourceRemoteName: s.remote.name,
      sourcePath: s.path,
    );
    final leaf = backupFolderLeaf(remoteName: s.remote.name, path: s.path);
    final task = buildBackupTask(
      id: TransferTask.newId(),
      name: 'Back up $leaf',
      srcFs: '${s.remote.fs}${s.path}',
      srcLabel: folderRefLabel(s),
      dstFs: '${d.remote.fs}$destPath',
      dstLabel: '${d.remote.name}:$destPath',
      schedule: _schedule,
      runWhileClosed: canRunWhileClosed && _runWhileClosed,
    );

    final notifier = ref.read(tasksProvider.notifier);
    notifier.add(task);
    await reconcileRegistrations(
      notifier: notifier,
      readTasks: () => ref.read(tasksProvider),
      os: ref.read(windowsTaskSchedulerProvider),
      pollMinutes: ref.read(pollCadenceProvider),
      refresh: {task.id},
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final preview = _destinationPreview;
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: const Text('Back up a folder'),
      content: DialogBody(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _step(c, 1, 'What to back up'),
              _picked(c, _source, () => _pick(source: true)),
              const SizedBox(height: Space.x4),
              _step(c, 2, 'Where to keep it'),
              _picked(c, _dest, () => _pick(source: false)),
              if (preview != null) ...[
                const SizedBox(height: Space.x2),
                Text(
                  'Files will go to $preview',
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                ),
              ],
              const SizedBox(height: Space.x4),
              _step(c, 3, 'How often'),
              const SizedBox(height: Space.x2),
              Wrap(
                spacing: Space.x2,
                children: [
                  for (final k in [ScheduleKind.daily, ScheduleKind.interval])
                    ChoiceChip(
                      label: Text(k == ScheduleKind.daily ? 'Daily' : 'Hourly'),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: Space.x3),
              if (_kind == ScheduleKind.daily)
                Row(
                  children: [
                    Text('At', style: TextStyle(color: c.textMuted)),
                    const SizedBox(width: Space.x3),
                    OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(
                        '${_hour.toString().padLeft(2, '0')}:'
                        '${_minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Text('Every', style: TextStyle(color: c.textMuted)),
                    const SizedBox(width: Space.x3),
                    DropdownButton<int>(
                      value: _intervalMinutes,
                      dropdownColor: c.surfaceRaised,
                      items: const [
                        DropdownMenuItem(value: 60, child: Text('hour')),
                        DropdownMenuItem(value: 360, child: Text('6 hours')),
                        DropdownMenuItem(value: 720, child: Text('12 hours')),
                      ],
                      onChanged: (v) =>
                          setState(() => _intervalMinutes = v ?? 360),
                    ),
                  ],
                ),
              if (canRunWhileClosed) ...[
                const SizedBox(height: Space.x2),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Also run while Airclone is closed'),
                  value: _runWhileClosed,
                  onChanged: (v) =>
                      setState(() => _runWhileClosed = v ?? false),
                ),
              ],
              const SizedBox(height: Space.x2),
              Text(
                // The promise, stated once, in the words the constraints buy.
                'Backups only ever copy — they never delete anything at the '
                'destination. A file that gets overwritten is kept as an older '
                'version you can restore. $schedulingSummary',
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _ready ? _create : null,
          child: const Text('Start backing up'),
        ),
      ],
    );
  }

  Widget _step(AircloneColors c, int n, String label) => Row(
    children: [
      CircleAvatar(
        radius: 9,
        backgroundColor: c.primary.withValues(alpha: 0.15),
        child: Text(
          '$n',
          style: TextStyle(
            color: c.primary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: Space.x2),
      Text(
        label,
        style: TextStyle(
          color: c.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _picked(AircloneColors c, FolderRef? value, VoidCallback onPick) =>
      Padding(
        padding: const EdgeInsets.only(left: 26, top: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? 'Not chosen yet' : folderRefLabel(value),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value == null ? c.textFaint : c.text,
                  fontSize: 12,
                  fontStyle: value == null
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
            TextButton(
              onPressed: onPick,
              child: Text(value == null ? 'Choose…' : 'Change'),
            ),
          ],
        ),
      );
}
