import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rclone/http_rclone_client.dart';
import '../../rclone/models/job.dart';
import '../../rclone/rclone_client.dart';
import '../engine_controller.dart';
import '../jobs_controller.dart';
import '../settings_controller.dart';
import 'console_command.dart';
import 'console_rc_translate.dart';
import 'console_redaction.dart';
import 'rclone_commands.dart';

/// The channel a console output line came from — drives its styling.
enum ConsoleLineKind {
  /// The echoed `› rclone …` command the user ran.
  input,

  /// Normal command output (stdout/stderr, combined in the buffered MVP).
  output,

  /// A terminal/error line (rclone error, blocked command, non-zero exit).
  error,

  /// Airclone's own narration (engine not ready, done, cancelled…).
  system,
}

@immutable
class ConsoleLine {
  const ConsoleLine(this.text, this.kind);
  final String text;
  final ConsoleLineKind kind;
}

/// State of one console tab: the draft input, the output scrollback (ring
/// buffered), and whether a command is in flight.
@immutable
class ConsoleState {
  const ConsoleState({
    this.draft = '',
    this.log = const [],
    this.running = false,
    this.activeJobId,
    this.history = const [],
  });

  final String draft;
  final List<ConsoleLine> log;
  final bool running;

  /// The local job id of a Path-B (RC-method) async command in flight, so the
  /// pane can bind a live progress row to it. Null for streaming / instant / idle.
  final int? activeJobId;

  /// Session command history (oldest → newest) for terminal-style ↑/↓ recall.
  /// Holds the raw command lines the user submitted; in-memory only.
  final List<String> history;

  ConsoleState copyWith({
    String? draft,
    List<ConsoleLine>? log,
    bool? running,
    int? activeJobId,
    bool clearActiveJob = false,
    List<String>? history,
  }) => ConsoleState(
    draft: draft ?? this.draft,
    log: log ?? this.log,
    running: running ?? this.running,
    activeJobId: clearActiveJob ? null : (activeJobId ?? this.activeJobId),
    history: history ?? this.history,
  );
}

/// Drives one console tab. Keyed by a stable console id so each tab keeps its
/// own scrollback across tab switches.
///
/// MVP (Phase 1): a typed command is parsed to argv ([ConsoleCommand]), gated by
/// the safety tier, and dispatched as a `core/command` COMBINED_OUTPUT call — a
/// single buffered RPC that returns the whole output when the command finishes.
/// It is registered as a [JobType.command] job so it appears in the transfer
/// queue. Live streaming + Stop + the RC-method (mobile) path come in later
/// phases. Blocked verbs are refused; destructive verbs are gated by the UI
/// (confirm) before [run] is called.
class ConsoleController extends FamilyNotifier<ConsoleState, String> {
  /// Largest number of output lines kept (a `-vv` command is unbounded).
  static const int _logCap = 2000;

  /// Largest number of past commands kept for ↑/↓ recall.
  static const int _historyCap = 100;

  /// The live output subscription of a streaming (desktop) command — cancelling
  /// it is the Stop. Null when nothing is streaming.
  StreamSubscription<String>? _sub;

  /// The local id of the job currently running (for Stop → mark canceled).
  int? _jobId;

  /// Set when Stop is pressed during the brief `commandStream` setup window
  /// (before `_sub` exists) so the stream is cancelled the instant it attaches.
  bool _stopRequested = false;

  /// The local id of a Path-B (RC-method) async command being tracked by the jobs
  /// poller (in-process engine). Null on the streaming path / instant ops / idle.
  int? _activeJobId;

  /// Guards the terminal finalizer so it renders the summary exactly once.
  bool _finalizing = false;

  @override
  ConsoleState build(String arg) {
    ref.onDispose(() => _sub?.cancel());
    // Path B has no live stream — the shared jobs poller drives the async job, so
    // watch for it settling to render the terminal summary in the console.
    ref.listen(jobsControllerProvider, (_, _) => _onJobs());
    return const ConsoleState();
  }

  void setDraft(String value) => state = state.copyWith(draft: value);

  void clear() => state = state.copyWith(log: const []);

  void _append(String text, ConsoleLineKind kind) {
    final next = [...state.log, ConsoleLine(text, kind)];
    state = state.copyWith(
      log: next.length > _logCap ? next.sublist(next.length - _logCap) : next,
    );
  }

  /// Parse + run the current draft. Safe/destructive verbs run; blocked verbs
  /// (and unknown verbs) are refused here as a backstop even though the UI gates
  /// them too. No-op while a command is already running or the draft is empty.
  Future<void> run() async {
    if (state.running) return;
    final cmd = ConsoleCommand.parse(state.draft.trim());
    if (cmd.isEmpty) return;

    // Record the raw line in the session history for ↑/↓ recall — BEFORE the
    // blocked/refused checks below, so a command you need to fix and rerun is
    // still recallable. Skip a consecutive duplicate (bash `ignoredups`).
    final entry = state.draft.trim();
    if (state.history.isEmpty || state.history.last != entry) {
      final next = [...state.history, entry];
      state = state.copyWith(
        history: next.length > _historyCap
            ? next.sublist(next.length - _historyCap)
            : next,
      );
    }

    if (cmd.tier == CommandTier.blocked) {
      // Says WHY and, where one exists, where to do it in the app instead — a
      // refusal that names no alternative reads as a broken feature (see
      // blockedMessage).
      _append(blockedMessage(cmd.verb, cmd.flags), ConsoleLineKind.error);
      return;
    }
    // Refuse credential-dumping verbosity (-vv / --dump …) rather than trying to
    // scrub freeform dump output — block over scrub.
    if (hasCredentialDump(cmd)) {
      _append(
        'Refused: -vv / --dump can echo credentials to the log. Remove it, or '
        'use a lower verbosity.',
        ConsoleLineKind.error,
      );
      return;
    }

    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      _append('Engine not ready.', ConsoleLineKind.system);
      return;
    }
    // Two dispatch paths over the ONE seam. The desktop/Android binary engine
    // (HttpRcloneClient) runs core/command STREAM for full CLI text output. The
    // in-process/FFI engine can't (librclone rejects core/command, and there is no
    // binary to re-exec), so it translates the SAME parsed argv into a curated,
    // fail-closed RC-method call — Path B, the substrate TransferService proves.
    if (client is HttpRcloneClient) {
      // The spawned rcd runs with a `--config` override, but core/command re-execs
      // a FRESH rclone that does NOT inherit that flag — so pass it explicitly, or
      // console commands would read the DEFAULT config. RCLONE_CONFIG_PASS is
      // already inherited via env.
      final configPath = ref
          .read(settingsControllerProvider)
          .configPathOverride;
      final args = (configPath != null && configPath.isNotEmpty)
          ? [...cmd.args, '--config', configPath]
          : cmd.args;
      final safe = redactedPreview(cmd);
      final jobs = ref.read(jobsControllerProvider.notifier);
      final job = jobs.add(
        type: JobType.command,
        source: safe,
        dest: '',
        status: JobStatus.running,
      );
      // A jobs-panel Stop on this row routes to our stream cancel.
      jobs.registerCancel(job.id, stop);
      _append('› $safe', ConsoleLineKind.input);
      _jobId = job.id;
      _stopRequested = false;
      state = state.copyWith(running: true, draft: '');
      await _runStreaming(client, cmd.verb, args, job.id, jobs);
    } else {
      await _runRcMethod(client, cmd);
    }
  }

  /// Path B — dispatch a translated RC-method call on the in-process/FFI engine.
  /// The translator is fail-closed: an unknown verb/flag or an unsplittable remote
  /// refuses here with an honest message and NOTHING is dispatched.
  Future<void> _runRcMethod(RcloneClient client, ConsoleCommand cmd) async {
    final t = translateToRc(cmd);
    if (t is RcRefusal) {
      _append(t.reason, ConsoleLineKind.error);
      return;
    }
    final rc = t as RcDispatch;
    final safe = redactedPreview(cmd);
    _append('› $safe', ConsoleLineKind.input);
    if (rc.notes.isNotEmpty) {
      _append(
        'note: ${rc.notes.join(', ')} shown for reference (no effect via the '
        'in-process engine).',
        ConsoleLineKind.system,
      );
    }
    final jobs = ref.read(jobsControllerProvider.notifier);

    if (rc.kind == RcKind.instant) {
      // One blocking RPC; render the result and mark the job terminal ourselves.
      final job = jobs.add(
        type: JobType.command,
        source: safe,
        dest: '',
        status: JobStatus.running,
      );
      state = state.copyWith(running: true, draft: '');
      try {
        final res = await client.rpc(rc.method, rc.params);
        for (final line in formatRcResult(cmd.verb, res)) {
          _append(redactOutputLine(line), ConsoleLineKind.output);
        }
        jobs.markDone(job.id, JobStatus.success);
      } on RcloneException catch (e) {
        // rclone fs-creation errors echo the fs, which may embed an inline
        // connection-string secret — scrub before it enters the scrollback/history.
        final msg = redactOutputLine(e.message);
        _append(msg, ConsoleLineKind.error);
        jobs.markDone(job.id, JobStatus.failed, error: msg);
      } catch (e) {
        final msg = redactOutputLine('$e');
        _append(msg, ConsoleLineKind.error);
        jobs.markDone(job.id, JobStatus.failed, error: msg);
      }
      state = state.copyWith(running: false);
      return;
    }

    // Async: dispatch _async + _group and hand off to the shared 1s poller. The
    // _onJobs listener renders the terminal summary; Stop routes to job/stop.
    final job = jobs.add(
      type: JobType.command,
      source: safe,
      dest: '',
      status: JobStatus.running,
    );
    _activeJobId = job.id;
    _stopRequested = false;
    _finalizing = false;
    // Route a jobs-panel Stop (and our own) through one cancel path — WITHOUT it, a
    // Stop during the pre-jobid dispatch window would mark the row canceled but
    // never issue job/stop, leaving a destructive purge/sync running.
    jobs.registerCancel(job.id, () => _cancelRcJob(job.id));
    state = state.copyWith(running: true, draft: '', activeJobId: job.id);

    // copyto/moveto: a directory source can't use operations/copyfile — probe the
    // source and fall back to sync/copy|move over the whole fs (TransferService's
    // exact logic), else keep the file method.
    var method = rc.method;
    var params = <String, dynamic>{...rc.params};
    if (rc.needsSourceProbe) {
      var isDir = false;
      try {
        final stat = await client.rpc('operations/stat', {
          'fs': params['srcFs'],
          'remote': params['srcRemote'],
        });
        final item = stat['item'];
        if (item is Map && item['IsDir'] == true) isDir = true;
      } catch (_) {
        isDir = true; // stat failed → the directory-safe path
      }
      if (isDir) {
        method = method == 'operations/copyfile' ? 'sync/copy' : 'sync/move';
        params = {
          'srcFs': params['_srcFsWhole'],
          'dstFs': params['_dstFsWhole'],
          if (params['_config'] != null) '_config': params['_config'],
          if (params['_filter'] != null) '_filter': params['_filter'],
        };
      }
    }
    // Strip our internal whole-fs hints before dispatch.
    params.remove('_srcFsWhole');
    params.remove('_dstFsWhole');
    params['_async'] = true;
    params['_group'] = 'airclone/${job.id}';
    jobs.update(job.id, rcMethod: method, rcParams: params); // retry parity

    try {
      final res = await client.rpc(method, params);
      final jobid = res['jobid'];
      if (jobid is num) {
        jobs.update(job.id, jobid: jobid.toInt());
        // Stop pressed before the jobid landed — now cancel the real rclone job.
        if (_stopRequested) await _cancelRcJob(job.id);
      } else {
        jobs.markDone(
          job.id,
          JobStatus.failed,
          error: 'rclone did not return a job id',
        );
      }
    } catch (e) {
      jobs.markDone(job.id, JobStatus.failed, error: redactOutputLine('$e'));
    }
    // The poller now owns progress + terminal; _onJobs finalizes the console line.
  }

  /// Cancels the tracked Path-B async job. Sets [_stopRequested] (so a Stop during
  /// the pre-jobid window is honored once the jobid lands), and — once a jobid
  /// exists — issues `job/stop` and marks the row canceled. The single convergence
  /// point for BOTH the console Stop button and the jobs-panel Stop hook, so there
  /// is no stop()↔jobs.stop recursion.
  Future<void> _cancelRcJob(int id) async {
    _stopRequested = true;
    Job? job;
    for (final j in ref.read(jobsControllerProvider)) {
      if (j.id == id) {
        job = j;
        break;
      }
    }
    final jobid = job?.jobid;
    // pre-jobid: the dispatcher cancels once it lands
    if (jobid == null) return;
    final client = ref.read(engineControllerProvider).client;
    try {
      await client?.rpc('job/stop', {'jobid': jobid});
    } catch (_) {
      // best-effort — the job may have already finished
    }
    ref.read(jobsControllerProvider.notifier).markDone(id, JobStatus.canceled);
  }

  /// Fired on every jobs-list change: when the tracked Path-B async job settles,
  /// render its terminal summary in the console exactly once, then clear tracking.
  Future<void> _onJobs() async {
    final id = _activeJobId;
    if (id == null || _finalizing) return;
    Job? job;
    for (final j in ref.read(jobsControllerProvider)) {
      if (j.id == id) {
        job = j;
        break;
      }
    }
    if (job == null || !job.isFinished) return;
    _finalizing = true;
    final settled = job;
    // For a read verb (size/hashsum/check) the result lives in job/status.output.
    final client = ref.read(engineControllerProvider).client;
    final jobid = settled.jobid;
    if (client != null && jobid != null) {
      try {
        final s = await client.rpc('job/status', {'jobid': jobid});
        final output = s['output'];
        if (output is Map<String, dynamic>) {
          for (final line in formatRcResult('', output)) {
            _append(redactOutputLine(line), ConsoleLineKind.output);
          }
        }
      } catch (_) {
        // Job reaped/expired — the summary line below still reports the outcome.
      }
    }
    _append(
      switch (settled.status) {
        JobStatus.success => '✓ done',
        JobStatus.canceled => '■ stopped',
        // The poller stores rclone's raw error (which can echo an inline
        // connection-string fs) — scrub it before it enters the scrollback.
        _ => '✗ ${redactOutputLine(settled.error ?? 'failed')}',
      },
      settled.status == JobStatus.success
          ? ConsoleLineKind.system
          : ConsoleLineKind.error,
    );
    _activeJobId = null;
    _finalizing = false;
    state = state.copyWith(running: false, clearActiveJob: true);
  }

  Future<void> _runStreaming(
    HttpRcloneClient client,
    String verb,
    List<String> args,
    int jobId,
    JobsController jobs,
  ) async {
    final Stream<String> stream;
    try {
      stream = await client.commandStream(verb, args);
    } on RcloneException catch (e) {
      _append(e.message, ConsoleLineKind.error);
      jobs.markDone(jobId, JobStatus.failed, error: e.message);
      _finish();
      return;
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
      jobs.markDone(jobId, JobStatus.failed, error: '$e');
      _finish();
      return;
    }
    // Stop was pressed during the setup window (before _sub existed) — cancel
    // the stream the instant it attaches.
    if (_stopRequested) {
      final s = stream.listen(null);
      await s.cancel();
      jobs.markDone(jobId, JobStatus.canceled);
      _append('■ stopped', ConsoleLineKind.system);
      _finish();
      return;
    }
    // core/command STREAM carries no exit code — HTTP 200 is already flushed and
    // rclone writes any error into the body, then ends the stream normally. So we
    // heuristically flag a failure from error-shaped lines and style them.
    var sawError = false;
    _sub = stream.listen(
      (line) {
        final isErr = _looksLikeError(line);
        if (isErr) sawError = true;
        _append(
          redactOutputLine(line),
          isErr ? ConsoleLineKind.error : ConsoleLineKind.output,
        );
      },
      onError: (Object e) {
        _append('$e', ConsoleLineKind.error);
        jobs.markDone(jobId, JobStatus.failed, error: '$e');
        _finish();
      },
      onDone: () {
        jobs.markDone(
          jobId,
          sawError ? JobStatus.failed : JobStatus.success,
          error: sawError ? 'command reported an error' : null,
        );
        _finish();
      },
      cancelOnError: true,
    );
  }

  static bool _looksLikeError(String line) {
    final l = line.toLowerCase();
    return line.contains('ERROR') ||
        l.contains('failed to') ||
        l.startsWith('error:') ||
        l.contains('fatal error');
  }

  void _finish() {
    _sub = null;
    _jobId = null;
    _stopRequested = false;
    state = state.copyWith(running: false);
  }

  /// Stop a running command. Streaming (binary engine): cancelling the
  /// subscription closes the HTTP request, so rclone cancels the command context
  /// and kills the child. Path B (in-process async): there is no stream — cancel
  /// via `job/stop` (the `_onJobs` listener then settles the console line). Also
  /// invoked by the jobs panel via the registered cancel hook (streaming only).
  Future<void> stop() async {
    if (!state.running) return;

    // Path B: an RC-method async command is tracked by its job id, not a stream.
    // The same convergence point the jobs-panel hook uses (no recursion, and the
    // pre-jobid window is honored via _stopRequested).
    final activeId = _activeJobId;
    if (activeId != null) {
      await _cancelRcJob(activeId);
      return;
    }

    // Streaming path.
    final sub = _sub;
    if (sub == null) {
      // Stop hit during the commandStream setup window — cancel once it attaches,
      // OR an instant RC-method op is in flight (uncancelable) → harmless no-op.
      _stopRequested = true;
      return;
    }
    _sub = null;
    await sub.cancel(); // silent — does not fire onDone
    final jid = _jobId;
    _jobId = null;
    if (jid != null) {
      ref
          .read(jobsControllerProvider.notifier)
          .markDone(jid, JobStatus.canceled);
    }
    _append('■ stopped', ConsoleLineKind.system);
    state = state.copyWith(running: false);
  }

  /// Renders an rclone RC result map into console output lines, routing by the
  /// result SHAPE (so it also handles a read verb's `job/status.output`). Every
  /// line is redacted by the caller before it enters the buffer.
  static List<String> formatRcResult(String verb, Map<String, dynamic> json) {
    final list = json['list'];
    if (list is List) {
      return [
        for (final e in list)
          if (e is Map) _listLine(e.cast<String, dynamic>()),
      ];
    }
    if (json.containsKey('total') || json.containsKey('free')) {
      String q(String k) => json[k] == null ? '?' : _humanBytes(json[k]);
      return [
        'Total: ${q('total')}   Used: ${q('used')}   Free: ${q('free')}',
        if (json['trashed'] != null) 'Trashed: ${q('trashed')}',
      ];
    }
    if (json.containsKey('count') && json.containsKey('bytes')) {
      return ['${json['count']} objects, ${_humanBytes(json['bytes'])}'];
    }
    if (json['version'] is String) return ['rclone ${json['version']}'];
    final remotes = json['remotes'];
    if (remotes is List) return [for (final r in remotes) '$r'];
    if (json['url'] is String) return ['${json['url']}'];
    final hashes = json['hashsum'];
    if (hashes is Map) {
      return [for (final e in hashes.entries) '${e.value}  ${e.key}'];
    }
    if (json.isEmpty) return const ['done'];
    return const JsonEncoder.withIndent('  ').convert(json).split('\n');
  }

  static String _listLine(Map<String, dynamic> e) {
    final name = (e['Path'] ?? e['Name'] ?? '').toString();
    final size = e['IsDir'] == true ? '<DIR>' : _humanBytes(e['Size']);
    return '${size.padLeft(10)}  $name';
  }

  static String _humanBytes(Object? v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    if (n < 0) return '-';
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
    var x = n;
    var u = 0;
    while (x >= 1024 && u < units.length - 1) {
      x /= 1024;
      u++;
    }
    return u == 0 ? '${x.toInt()} B' : '${x.toStringAsFixed(1)} ${units[u]}';
  }
}

final consoleControllerProvider =
    NotifierProvider.family<ConsoleController, ConsoleState, String>(
      ConsoleController.new,
    );
