import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/browser_controller.dart';
import '../state/tasks_controller.dart';
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
              ],
            ),
          ),
          const SizedBox(width: Space.x3),
          FilledButton.icon(
            onPressed: () {
              ref
                  .read(transferServiceProvider)
                  .transferAdvancedRaw(
                    srcFs: task.srcFs,
                    dstFs: task.dstFs,
                    srcLabel: task.srcLabel,
                    dstLabel: task.dstLabel,
                    options: task.options,
                  );
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Started "${task.name}"')));
            },
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
}
