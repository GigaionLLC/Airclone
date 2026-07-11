import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rclone/http_rclone_client.dart';
import '../../rclone/models/job.dart';
import '../../rclone/rclone_client.dart';
import '../engine_controller.dart';
import '../jobs_controller.dart';
import 'console_command.dart';
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
  });

  final String draft;
  final List<ConsoleLine> log;
  final bool running;

  ConsoleState copyWith({
    String? draft,
    List<ConsoleLine>? log,
    bool? running,
  }) => ConsoleState(
    draft: draft ?? this.draft,
    log: log ?? this.log,
    running: running ?? this.running,
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

  /// The live output subscription of a streaming (desktop) command — cancelling
  /// it is the Stop. Null when nothing is streaming.
  StreamSubscription<String>? _sub;

  /// The local id of the job currently running (for Stop → mark canceled).
  int? _jobId;

  @override
  ConsoleState build(String arg) {
    ref.onDispose(() => _sub?.cancel());
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

    if (cmd.tier == CommandTier.blocked) {
      _append(
        'Blocked: "${cmd.verb}" is not permitted in the console '
        '(it leaks secrets, mutates config, or runs a server).',
        ConsoleLineKind.error,
      );
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

    // A redacted, display-safe rendering used everywhere the command is shown.
    final safe = redactedPreview(cmd);
    final jobs = ref.read(jobsControllerProvider.notifier);
    final job = jobs.add(
      type: JobType.command,
      source: safe,
      dest: '',
      status: JobStatus.running,
    );
    _append('› $safe', ConsoleLineKind.input);
    _jobId = job.id;
    state = state.copyWith(running: true, draft: '');

    // Desktop/HTTP: a LIVE stream via core/command STREAM (no 30s timeout,
    // Stop-able). The in-process (FFI) engine can't stream core/command, so it
    // takes the buffered fallback (which surfaces a clear error until the Phase-4
    // RC-method console).
    if (client is HttpRcloneClient) {
      await _runStreaming(client, cmd, job.id, jobs);
    } else {
      await _runBuffered(client, cmd, job.id, jobs);
    }
  }

  Future<void> _runStreaming(
    HttpRcloneClient client,
    ConsoleCommand cmd,
    int jobId,
    JobsController jobs,
  ) async {
    try {
      final stream = await client.commandStream(cmd.verb, cmd.args);
      _sub = stream.listen(
        (line) => _append(redactOutputLine(line), ConsoleLineKind.output),
        onError: (Object e) {
          _append('$e', ConsoleLineKind.error);
          jobs.markDone(jobId, JobStatus.failed, error: '$e');
          _finish();
        },
        onDone: () {
          jobs.markDone(jobId, JobStatus.success);
          _finish();
        },
        cancelOnError: true,
      );
    } on RcloneException catch (e) {
      _append(e.message, ConsoleLineKind.error);
      jobs.markDone(jobId, JobStatus.failed, error: e.message);
      _finish();
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
      jobs.markDone(jobId, JobStatus.failed, error: '$e');
      _finish();
    }
  }

  Future<void> _runBuffered(
    RcloneClient client,
    ConsoleCommand cmd,
    int jobId,
    JobsController jobs,
  ) async {
    try {
      final res = await client.rpc('core/command', cmd.toRcParams());
      final out = (res['result'] as String?) ?? '';
      for (final line in const LineSplitter().convert(out)) {
        _append(redactOutputLine(line), ConsoleLineKind.output);
      }
      if (res['error'] == true) {
        _append('✗ command exited non-zero', ConsoleLineKind.error);
        jobs.markDone(jobId, JobStatus.failed, error: 'non-zero exit');
      } else {
        jobs.markDone(jobId, JobStatus.success);
      }
    } on RcloneException catch (e) {
      _append(e.message, ConsoleLineKind.error);
      jobs.markDone(jobId, JobStatus.failed, error: e.message);
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
      jobs.markDone(jobId, JobStatus.failed, error: '$e');
    } finally {
      _finish();
    }
  }

  void _finish() {
    _sub = null;
    _jobId = null;
    state = state.copyWith(running: false);
  }

  /// Stop a running (streaming) command: cancelling the subscription closes the
  /// HTTP request, so rclone cancels the command context and kills the spawned
  /// child. Marks the job canceled. No-op if nothing is streaming (the buffered
  /// fallback isn't cancellable).
  Future<void> stop() async {
    final sub = _sub;
    if (sub == null) return;
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
}

final consoleControllerProvider =
    NotifierProvider.family<ConsoleController, ConsoleState, String>(
      ConsoleController.new,
    );
