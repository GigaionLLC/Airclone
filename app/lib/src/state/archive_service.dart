import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/rclone_engine.dart';
import 'archive_command.dart';
import 'cache_crypto.dart';
import 'jobs_controller.dart';
import 'settings_controller.dart';

/// A user-actionable archive failure (binary missing, list failed).
class ArchiveError implements Exception {
  const ArchiveError(this.message);
  final String message;
  @override
  String toString() => 'ArchiveError: $message';
}

/// Runs `rclone archive create/extract/list` as a real subprocess (rclone exposes
/// no RC method for archives; verified against v1.74 `rc/list`). create/extract are
/// tracked as [JobType.archive] jobs — live percentage from `--stats`, and Stop
/// kills the child via the jobs cancel hook. Reads the SAME config the engine runs
/// against (`--config` override + `RCLONE_CONFIG_PASS`), so cross-remote src/dst
/// work. Desktop + Android (needs the binary); the browser wires it desktop-first.
class ArchiveService {
  ArchiveService(this._ref);
  final Ref _ref;

  Future<String?> _rclone() => RcloneEngine.findExisting(
    overridePath: _ref.read(settingsControllerProvider).rclonePathOverride,
  );

  /// The `--config` override the engine spawns with (empty on the desktop default,
  /// where the fresh rclone finds its own config exactly as the engine does).
  List<String> _configArgs() {
    final override = _ref.read(settingsControllerProvider).configPathOverride;
    return (override != null && override.isNotEmpty)
        ? <String>['--config', override]
        : const <String>[];
  }

  /// The config-encryption password, passed via the environment only (never argv).
  Map<String, String>? _env() {
    final pass = _ref.read(cachePassphraseProvider);
    return (pass != null && pass.isNotEmpty)
        ? <String, String>{'RCLONE_CONFIG_PASS': pass}
        : null;
  }

  /// Dispatches a create/extract [cmd] as a tracked subprocess job and returns the
  /// local job id. Never throws — a failure lands on the job. Stop (jobs panel)
  /// kills the child through the registered cancel hook.
  Future<int> runJob(ArchiveCommand cmd) async {
    final jobs = _ref.read(jobsControllerProvider.notifier);
    final job = jobs.add(
      type: JobType.archive,
      source: cmd.sourceLabel,
      dest: cmd.destLabel,
      status: JobStatus.running,
    );
    final rclone = await _rclone();
    if (rclone == null) {
      jobs.markDone(
        job.id,
        JobStatus.failed,
        error: 'The rclone engine binary was not found.',
      );
      return job.id;
    }
    // --stats-one-line gives a periodic single line we scrape a percentage from.
    final args = <String>[
      ...cmd.args,
      '--stats',
      '2s',
      '--stats-one-line',
      ..._configArgs(),
    ];
    final Process proc;
    try {
      proc = await Process.start(
        rclone,
        args,
        runInShell: false,
        environment: _env(),
      );
    } catch (e) {
      jobs.markDone(job.id, JobStatus.failed, error: '$e');
      return job.id;
    }
    var terminal = false;
    // Stop routes here (kill the child); markDone guards against a later exit flip.
    jobs.registerCancel(job.id, () async {
      terminal = true;
      proc.kill();
      jobs.markDone(job.id, JobStatus.canceled);
    });

    final errTail = <String>[];
    // ONLY the real `--stats-one-line` summary ("Transferred: X / Y, NN%, …") is a
    // progress line — scrape the percent from THAT shape, never from an arbitrary
    // "NN%" (a filename legitimately contains one). Every other line goes to
    // errTail, so an error that embeds a percent-containing path is never swallowed.
    final statsRe = RegExp(r'Transferred:.*?,\s*(\d{1,3})%');
    final stderrDone = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.trim().isEmpty) return;
          final m = statsRe.firstMatch(line);
          if (m != null) {
            if (!terminal) {
              final pct = int.parse(m.group(1)!).clamp(0, 100);
              jobs.update(job.id, total: 100, bytes: pct);
            }
          } else {
            errTail.add(line);
            if (errTail.length > 30) errTail.removeAt(0);
          }
        });
    unawaited(proc.stdout.drain<void>());
    unawaited(() async {
      final code = await proc.exitCode;
      // Wait for stderr to fully drain so a failure reports rclone's ACTUAL final
      // line, not a stale earlier one (exitCode can complete before the tail does).
      try {
        await stderrDone;
      } catch (_) {}
      if (terminal) return; // Stop already marked it canceled.
      if (code == 0) {
        jobs.markDone(job.id, JobStatus.success);
      } else {
        jobs.markDone(
          job.id,
          JobStatus.failed,
          error: errTail.isNotEmpty
              ? errTail.last
              : 'rclone exited with code $code',
        );
      }
    }());
    return job.id;
  }

  /// Largest number of `archive list` lines kept in memory / rendered — a
  /// pathological archive (millions of entries) would otherwise buffer hundreds of
  /// MB and freeze the text layout. Beyond this we stop accumulating and note it.
  static const int _listCap = 5000;

  /// One-shot `archive list` — returns the archive's contents listing (capped).
  /// Uses [Process.start] (not [Process.run]) so a timeout can actually KILL the
  /// child rather than orphan it holding the config + connections. Throws
  /// [ArchiveError] on a missing binary, timeout, or non-zero exit.
  Future<String> listContents(ArchiveCommand cmd) async {
    final rclone = await _rclone();
    if (rclone == null) {
      throw const ArchiveError('The rclone engine binary was not found.');
    }
    final args = <String>[...cmd.args, ..._configArgs()];
    final Process proc;
    try {
      proc = await Process.start(
        rclone,
        args,
        runInShell: false,
        environment: _env(),
      );
    } catch (e) {
      throw ArchiveError('$e');
    }
    final lines = <String>[];
    var truncated = false;
    final err = StringBuffer();
    final outDone = proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((l) {
          if (lines.length < _listCap) {
            lines.add(l);
          } else {
            truncated = true;
          }
        });
    final errDone = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(err.write);
    final int code;
    try {
      code = await proc.exitCode.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      proc.kill();
      throw const ArchiveError('Listing the archive timed out.');
    }
    await outDone.catchError((_) {});
    await errDone.catchError((_) {});
    if (code != 0) {
      final e = err.toString().trim();
      throw ArchiveError(
        e.isEmpty ? 'rclone exited with code $code' : e.split('\n').last,
      );
    }
    final out = lines.join('\n');
    return truncated ? '$out\n… (truncated at $_listCap entries)' : out;
  }
}

final archiveServiceProvider = Provider<ArchiveService>(
  (ref) => ArchiveService(ref),
);
