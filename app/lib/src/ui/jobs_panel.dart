import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../state/jobs_controller.dart';
import '../state/transfer_service.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// Recognizes the class of rclone bisync failure that means its two saved
/// listings (the "baseline") are missing or unusable, so the only recovery is a
/// fresh `--resync`. rclone phrases this several ways across versions, e.g.
/// "cannot find prior Path1 listing", "cannot find prior Path1 or Path2
/// listings", "Bisync aborted. Must run --resync to recover", or "Try running
/// bisync again with --resync". We deliberately match tolerantly — lowercased
/// `contains` on two stable signals, not any single exact sentence — so wording
/// drift between rclone releases still lands the hint:
///   • the `--resync` flag itself (unambiguous: a plain "sync" error has no such
///     double-dashed token), or
///   • a "prior … listing" word pair (both words survive even when rclone
///     splices "Path1"/"Path2" between them, which a literal "prior listing"
///     substring match would miss).
/// Kept a pure top-level function so it is unit-testable in isolation.
bool looksLikeBisyncNeedsResync(String error) {
  final e = error.toLowerCase();
  return e.contains('--resync') ||
      (e.contains('prior') && e.contains('listing'));
}

/// Bottom dock listing active and finished transfers. The shell gives this its
/// height; we just fill the space with a header + scrollable job rows.
class JobsPanel extends ConsumerWidget {
  const JobsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AircloneTheme.of(context);
    final jobs = ref.watch(jobsControllerProvider);

    final running = jobs.where((j) => j.isRunning).length;
    final queued = jobs.where((j) => j.isQueued).length;
    final finished = jobs.where((j) => j.isFinished).length;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(running: running, queued: queued, finished: finished),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: jobs.isEmpty
                ? _EmptyState(colors: colors)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: Space.x1),
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: colors.border),
                    // Keyed by job id: rows carry expansion state, and a
                    // ListView reusing an element by INDEX would otherwise move
                    // one job's "show every file" onto a different job when the
                    // list reorders or a finished job is cleared.
                    itemBuilder: (_, i) =>
                        _JobRow(key: ValueKey(jobs[i].id), job: jobs[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Title, counts, and the "Clear finished" action.
class _Header extends ConsumerWidget {
  const _Header({
    required this.running,
    required this.queued,
    required this.finished,
  });

  final int running;
  final int queued;
  final int finished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AircloneTheme.of(context);
    final hasFinished = finished > 0;
    final paused = ref.watch(queuePausedProvider);
    final counts = [
      '$running active',
      if (queued > 0) '$queued queued${paused ? ' (paused)' : ''}',
      '$finished done',
    ].join(' · ');

    // Vertically compact ON PURPOSE: this header plus the dock's tab strip is
    // what [kMinJobsDockHeight] has to accommodate, and Material's default
    // 40-48px button targets would eat the whole dock at its minimum.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.x4,
        Space.x2,
        Space.x3,
        Space.x2,
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
          Text(counts, style: TextStyle(color: colors.textMuted, fontSize: 12)),
          const Spacer(),
          IconButton(
            tooltip: paused
                ? 'Resume queue'
                : 'Pause queue (queued transfers wait; running ones finish)',
            onPressed: () => ref.read(queuePausedProvider.notifier).toggle(),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
            color: paused ? colors.warning : colors.textMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 28),
          ),
          TextButton(
            onPressed: hasFinished
                ? () =>
                      ref.read(jobsControllerProvider.notifier).clearFinished()
                : null,
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
              disabledForegroundColor: colors.textFaint,
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
class _JobRow extends ConsumerStatefulWidget {
  const _JobRow({super.key, required this.job});

  final Job job;

  @override
  ConsumerState<_JobRow> createState() => _JobRowState();
}

class _JobRowState extends ConsumerState<_JobRow> {
  /// How many in-flight files a collapsed row shows before the "+N more"
  /// expander. Three keeps the default dock readable with several jobs in it.
  static const int _collapsedFiles = 3;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
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
                // Per-file breakdown for a running multi-file job. Collapsed
                // to [_collapsedFiles] with a TAPPABLE expander — the old
                // "+N more" was plain text, so a job moving 16 files at once
                // showed three of them and no way to see the rest.
                if (job.isRunning && job.transferring.isNotEmpty) ...[
                  for (final t
                      in _expanded
                          ? job.transferring
                          : job.transferring.take(_collapsedFiles))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textFaint,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.x2),
                          Text(
                            '${t.percentage}%',
                            style: TextStyle(
                              color: colors.textFaint,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (job.transferring.length > _collapsedFiles)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3, bottom: 1),
                          child: Text(
                            _expanded
                                ? 'Show fewer files'
                                : '+${job.transferring.length - _collapsedFiles}'
                                      ' more — show all',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
                if (failed && job.error != null) ...[
                  const SizedBox(height: Space.x1),
                  Text(
                    job.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.error, fontSize: 11),
                  ),
                  // The raw (truncated) bisync "lost baseline" error is a dead
                  // end on its own — it names no fix. When we recognize it, add
                  // a styled line pointing at the one-click recovery that ships
                  // in Saved tasks (the "Re-establish baseline…" action).
                  if (looksLikeBisyncNeedsResync(job.error!)) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Two-way sync needs its baseline re-established — open '
                      'Saved tasks and use "Re-establish baseline…".',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.warning, fontSize: 11),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.x4),
          SizedBox(
            width: 84,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  job.isRunning ? _speed(job) : '',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
                if (job.isRunning &&
                    job.etaLabel.isNotEmpty &&
                    job.etaLabel != '—')
                  Text(
                    '${job.etaLabel} left',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: colors.textFaint, fontSize: 10),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.x3),
          _StatusChip(status: job.status, colors: colors),
          const SizedBox(width: Space.x1),
          if (job.isActive)
            SizedBox(
              width: 32,
              child: IconButton(
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                color: colors.textMuted,
                tooltip: job.isQueued ? 'Cancel' : 'Stop',
                onPressed: () =>
                    ref.read(jobsControllerProvider.notifier).stop(job.id),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (job.canRetry)
                  IconButton(
                    icon: const Icon(Icons.replay, size: 16),
                    color: colors.textMuted,
                    tooltip: 'Retry',
                    onPressed: () =>
                        ref.read(transferServiceProvider).retry(job.id),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: colors.textFaint,
                  tooltip: 'Dismiss',
                  onPressed: () =>
                      ref.read(jobsControllerProvider.notifier).remove(job.id),
                ),
              ],
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
    JobType.command => 'Command',
    JobType.archive => 'Archive',
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
      JobStatus.queued => ('Queued', colors.textMuted, colors.surfaceSunken),
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
