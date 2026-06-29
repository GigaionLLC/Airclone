import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/models/remote.dart';
import 'engine_controller.dart';
import 'jobs_controller.dart';
import 'transfer_options.dart';

/// Builds async rclone transfers and registers them as [Job]s so the Jobs panel
/// can track progress.
///
/// Every transfer runs with `_async: true` and a unique `_group` of the form
/// `airclone/<jobId>` so the poller in [JobsController] can scope `core/stats`
/// to exactly this transfer. The rclone `{jobid}` from the kick-off response is
/// stored back on the job.
class TransferService {
  TransferService(this._ref);

  final Ref _ref;

  /// Copy or move [srcPath] within [srcRemote] to [dstPath] within [dstRemote].
  ///
  /// Decides file-vs-directory by stat'ing the source: a single file uses
  /// `operations/copyfile`/`operations/movefile`; a directory (or unknown) uses
  /// `sync/copy`/`sync/move` over the full fs strings.
  Future<void> transfer({
    required Remote srcRemote,
    required String srcPath,
    required Remote dstRemote,
    required String dstPath,
    required JobType type,
  }) async {
    final client = _ref.read(engineControllerProvider).client;
    final jobs = _ref.read(jobsControllerProvider.notifier);

    final job = jobs.add(
      type: type,
      source: '${srcRemote.name}:$srcPath',
      dest: '${dstRemote.name}:$dstPath',
      status: JobStatus.queued,
    );

    if (client == null) {
      jobs.markDone(job.id, JobStatus.failed, error: 'Engine not ready');
      return;
    }

    final group = 'airclone/${job.id}';
    final isMove = type == JobType.move;

    // Dispatched by the jobs queue once a transfer slot is free.
    jobs.enqueue(job.id, () async {
      try {
        // Learn whether the source is a directory.
        var isDir = false;
        try {
          final stat = await client.rpc('operations/stat', {
            'fs': srcRemote.fs,
            'remote': srcPath,
          });
          final item = stat['item'];
          if (item is Map && item['IsDir'] == true) isDir = true;
        } catch (_) {
          // If stat fails, fall back to the directory-safe sync path.
          isDir = true;
        }

        final Map<String, dynamic> params;
        final String method;
        if (isDir) {
          method = isMove ? 'sync/move' : 'sync/copy';
          params = {
            'srcFs': '${srcRemote.fs}$srcPath',
            'dstFs': '${dstRemote.fs}$dstPath',
            '_async': true,
            '_group': group,
          };
        } else {
          method = isMove ? 'operations/movefile' : 'operations/copyfile';
          params = {
            'srcFs': srcRemote.fs,
            'srcRemote': srcPath,
            'dstFs': dstRemote.fs,
            'dstRemote': dstPath,
            '_async': true,
            '_group': group,
          };
        }

        final res = await client.rpc(method, params);
        final jobid = res['jobid'];
        if (jobid is num) {
          jobs.update(job.id, jobid: jobid.toInt());
        } else {
          jobs.markDone(
            job.id,
            JobStatus.failed,
            error: 'rclone did not return a job id',
          );
        }
      } catch (e) {
        jobs.markDone(job.id, JobStatus.failed, error: '$e');
      }
    });
  }

  /// Advanced Copy/Move/Sync of [srcPath] → [dstPath] driven by [options]
  /// (skip rules, compare mode, include/exclude/filter, dry-run). Dispatches
  /// `sync/copy|move|sync` with the assembled `_config`/`_filter` and tracks it
  /// as a [Job].
  Future<void> transferAdvanced({
    required Remote srcRemote,
    required String srcPath,
    required Remote dstRemote,
    required String dstPath,
    required TransferOptions options,
  }) => transferAdvancedRaw(
    srcFs: '${srcRemote.fs}$srcPath',
    dstFs: '${dstRemote.fs}$dstPath',
    srcLabel: '${srcRemote.name}:$srcPath',
    dstLabel: '${dstRemote.name}:$dstPath',
    options: options,
  );

  /// Advanced transfer from full `fs<path>` strings (used by saved tasks).
  /// [srcLabel]/[dstLabel] are human-readable for the job row.
  Future<void> transferAdvancedRaw({
    required String srcFs,
    required String dstFs,
    required String srcLabel,
    required String dstLabel,
    required TransferOptions options,
  }) async {
    final client = _ref.read(engineControllerProvider).client;
    final jobs = _ref.read(jobsControllerProvider.notifier);
    final jtype = switch (options.mode) {
      TransferMode.copy => JobType.copy,
      TransferMode.move => JobType.move,
      TransferMode.sync => JobType.sync,
    };
    final job = jobs.add(
      type: jtype,
      source: '$srcLabel${options.dryRun ? ' (dry run)' : ''}',
      dest: dstLabel,
      status: JobStatus.queued,
    );
    if (client == null) {
      jobs.markDone(job.id, JobStatus.failed, error: 'Engine not ready');
      return;
    }
    final call = buildRcCall(options, srcFs, dstFs);
    final params = <String, dynamic>{
      ...call.params,
      '_group': 'airclone/${job.id}',
    };
    jobs.enqueue(job.id, () async {
      try {
        final res = await client.rpc(call.method, params);
        final jobid = res['jobid'];
        if (jobid is num) {
          jobs.update(job.id, jobid: jobid.toInt());
        } else {
          jobs.markDone(
            job.id,
            JobStatus.failed,
            error: 'rclone did not return a job id',
          );
        }
      } catch (e) {
        jobs.markDone(job.id, JobStatus.failed, error: '$e');
      }
    });
  }
}

final transferServiceProvider = Provider<TransferService>(
  (ref) => TransferService(ref),
);
