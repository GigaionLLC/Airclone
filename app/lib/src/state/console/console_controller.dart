import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rclone/models/job.dart';
import '../../rclone/rclone_client.dart';
import '../engine_controller.dart';
import '../jobs_controller.dart';
import 'console_command.dart';
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

  @override
  ConsoleState build(String arg) => const ConsoleState();

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

    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      _append('Engine not ready.', ConsoleLineKind.system);
      return;
    }

    final jobs = ref.read(jobsControllerProvider.notifier);
    final job = jobs.add(
      type: JobType.command,
      source: cmd.preview(),
      dest: '',
      status: JobStatus.running,
    );
    _append('› ${cmd.preview()}', ConsoleLineKind.input);
    state = state.copyWith(running: true, draft: '');

    try {
      final res = await client.rpc('core/command', cmd.toRcParams());
      final out = (res['result'] as String?) ?? '';
      for (final line in const LineSplitter().convert(out)) {
        _append(line, ConsoleLineKind.output);
      }
      if (res['error'] == true) {
        _append('✗ command exited non-zero', ConsoleLineKind.error);
        jobs.markDone(job.id, JobStatus.failed, error: 'non-zero exit');
      } else {
        jobs.markDone(job.id, JobStatus.success);
      }
    } on RcloneException catch (e) {
      _append(e.message, ConsoleLineKind.error);
      jobs.markDone(job.id, JobStatus.failed, error: e.message);
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
      jobs.markDone(job.id, JobStatus.failed, error: '$e');
    } finally {
      state = state.copyWith(running: false);
    }
  }
}

final consoleControllerProvider =
    NotifierProvider.family<ConsoleController, ConsoleState, String>(
      ConsoleController.new,
    );
