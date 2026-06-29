import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../state/jobs_controller.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// Bottom dock listing active and finished transfers. The shell gives this its
/// height; we just fill the space with a header + scrollable job rows.
class JobsPanel extends ConsumerWidget {
  const JobsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AircloneTheme.of(context);
    final jobs = ref.watch(jobsControllerProvider);

    final running = jobs.where((j) => j.isRunning).length;
    final finished = jobs.length - running;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(running: running, finished: finished),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: jobs.isEmpty
                ? _EmptyState(colors: colors)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: Space.x1),
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: colors.border),
                    itemBuilder: (_, i) => _JobRow(job: jobs[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Title, counts, and the "Clear finished" action.
class _Header extends ConsumerWidget {
  const _Header({required this.running, required this.finished});

  final int running;
  final int finished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AircloneTheme.of(context);
    final hasFinished = finished > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.x4,
        Space.x3,
        Space.x3,
        Space.x3,
      ),
      child: Row(
        children: [
          Text(
            'Transfers',
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: Space.x3),
          Text(
            '$running active · $finished done',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const Spacer(),
          TextButton(
            onPressed: hasFinished
                ? () =>
                      ref.read(jobsControllerProvider.notifier).clearFinished()
                : null,
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
              disabledForegroundColor: colors.textFaint,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x3,
                vertical: Space.x1,
              ),
            ),
            child: const Text('Clear finished'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});

  final AircloneColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No transfers yet',
        style: TextStyle(color: colors.textFaint, fontSize: 12),
      ),
    );
  }
}

/// A single transfer line: type, source→dest, progress, sizes, speed, status.
class _JobRow extends ConsumerWidget {
  const _JobRow({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AircloneTheme.of(context);
    final failed = job.status == JobStatus.failed;
    final barColor = failed ? colors.error : colors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x4,
        vertical: Space.x3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _TypeLabel(type: job.type, colors: colors),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${job.source}  →  ${job.dest}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['Consolas', 'Menlo'],
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    Text(
                      _sizes(job),
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: Space.x2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.full),
                  child: LinearProgressIndicator(
                    value: job.isRunning && job.total <= 0
                        ? null
                        : job.progress,
                    minHeight: 4,
                    backgroundColor: colors.surfaceSunken,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
                if (failed && job.error != null) ...[
                  const SizedBox(height: Space.x1),
                  Text(
                    job.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.error, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.x4),
          SizedBox(
            width: 84,
            child: Text(
              job.isRunning ? _speed(job) : '',
              textAlign: TextAlign.right,
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          ),
          const SizedBox(width: Space.x3),
          _StatusChip(status: job.status, colors: colors),
          const SizedBox(width: Space.x1),
          SizedBox(
            width: 32,
            child: job.isRunning
                ? IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    color: colors.textMuted,
                    tooltip: 'Stop',
                    onPressed: () =>
                        ref.read(jobsControllerProvider.notifier).stop(job.id),
                  )
                : IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: colors.textFaint,
                    tooltip: 'Dismiss',
                    onPressed: () => ref
                        .read(jobsControllerProvider.notifier)
                        .remove(job.id),
                  ),
          ),
        ],
      ),
    );
  }

  static String _sizes(Job job) {
    final done = humanSize(job.bytes);
    if (job.total <= 0) return done;
    return '$done / ${humanSize(job.total)}';
  }

  static String _speed(Job job) {
    if (job.speedBps <= 0) return '';
    return '${humanSize(job.speedBps.round())}/s';
  }
}

/// Pill showing the transfer kind.
class _TypeLabel extends StatelessWidget {
  const _TypeLabel({required this.type, required this.colors});

  final JobType type;
  final AircloneColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x2,
        vertical: Space.x1,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        _label(type),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  static String _label(JobType type) => switch (type) {
    JobType.copy => 'Copy',
    JobType.move => 'Move',
    JobType.sync => 'Sync',
    JobType.delete => 'Delete',
    JobType.upload => 'Upload',
    JobType.download => 'Download',
  };
}

/// Colored status chip reflecting the [JobStatus].
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.colors});

  final JobStatus status;
  final AircloneColors colors;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      JobStatus.running => ('Running', colors.info, colors.surfaceSunken),
      JobStatus.success => ('Done', colors.success, colors.successBg),
      JobStatus.failed => ('Failed', colors.error, colors.errorBg),
      JobStatus.canceled => (
        'Canceled',
        colors.textMuted,
        colors.surfaceSunken,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x2,
        vertical: Space.x1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}
