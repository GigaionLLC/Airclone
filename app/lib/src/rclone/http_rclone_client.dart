import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import '../state/diagnostics.dart';
import 'rclone_client.dart';
import 'windows_child_job.dart';

/// Whether a line the `rcd` child wrote is worth RETAINING on a release build.
///
/// Every line is drained regardless — see [HttpRcloneClient._drainChildOutput],
/// where draining is a deadlock fix, not a logging feature. This only decides
/// what is kept: rclone's own severity prefix, because at high user verbosity
/// (-vv / --dump) it echoes request headers carrying the rc credentials, and a
/// bug report must never carry those. Kept a pure top-level function so it is
/// unit-testable in isolation.
bool isEngineFailureLine(String line) =>
    line.contains('ERROR') || line.contains('CRITICAL');

/// Desktop [RcloneClient]: spawns `rclone rcd` bound to loopback with per-session
/// credentials, and drives it over HTTP. See `wiki/core/08-core-architecture.md` §3.
class HttpRcloneClient implements RcloneClient {
  HttpRcloneClient({
    required this.rclonePath,
    this.configPath,
    this.configPassword,
    this.extraArgs = const <String>[],
    this.extraEnv = const <String, String>{},
  });

  /// Path to the rclone binary (from [RcloneEngine]).
  final String rclonePath;

  /// Optional explicit `--config` path; null uses rclone's default.
  final String? configPath;

  /// Config-encryption password, passed via `RCLONE_CONFIG_PASS` (never persisted,
  /// never on the command line). Null for unencrypted configs.
  final String? configPassword;

  /// User-supplied global flags appended to the `rcd` command line (advanced).
  /// Already tokenized argv-style. The rc binding/auth flags above always win.
  final List<String> extraArgs;

  /// Additional environment for the `rcd` child (e.g. Android's TMPDIR /
  /// RCLONE_LOCAL_NO_SET_MODTIME). RCLONE_CONFIG_PASS always wins over this.
  final Map<String, String> extraEnv;

  Process? _process;
  int? _port;
  String? _authHeader;
  String? _version;
  bool _quitting = false;
  final _client = http.Client();

  /// Fires if the rcd child exits without [quit] being called (crash, OOM
  /// kill). The owner surfaces it and offers a restart.
  void Function()? onDied;

  Uri _uri(String method) => Uri.parse('http://127.0.0.1:$_port/$method');

  /// Marker recording the PID of the `rcd` child WE last spawned, so a fresh
  /// launch can reap a leftover from a force-killed prior run. Only ever holds
  /// our own single recorded PID — never a broad process-name match.
  File get _markerFile => File('${Directory.systemTemp.path}/airclone_rcd.pid');

  /// Best-effort kill of the `rcd` child from a previous run that was orphaned
  /// by a hard exit. Targets only the single PID we recorded in the marker, so
  /// it cannot touch the user's other rclone processes. Skipped on Android:
  /// systemTemp resolves to /data/local/tmp (not app-writable), and Android
  /// kills the app's process group anyway.
  Future<void> _reapPreviousRcd() async {
    if (Platform.isAndroid) return;
    final marker = _markerFile;
    try {
      if (!await marker.exists()) return;
      final pid = int.tryParse((await marker.readAsString()).trim());
      if (pid != null) {
        try {
          Process.killPid(pid, ProcessSignal.sigkill);
        } catch (_) {
          /* stale or already gone; ignore */
        }
      }
      try {
        await marker.delete();
      } catch (_) {
        /* ignore */
      }
    } catch (_) {
      /* ignore unreadable/missing marker */
    }
  }

  @override
  ObjectRef objectRef(String fs, String remote) {
    // rcd `--rc-serve` exposes objects at /[<fs>]/<remote-path> with Basic auth.
    final encoded = remote.split('/').map(Uri.encodeComponent).join('/');
    final headers = <String, String>{};
    final auth = _authHeader;
    if (auth != null) headers['Authorization'] = auth;
    return ObjectRef('http://127.0.0.1:$_port/[$fs]/$encoded', headers);
  }

  @override
  Future<void> start() async {
    if (_process != null) return;

    // Reap any rcd child orphaned by a prior hard exit before spawning a new one.
    await _reapPreviousRcd();

    final port = await _freeLoopbackPort();
    final user = 'airclone';
    final pass = _randomToken();
    _port = port;
    _authHeader = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

    final args = <String>[
      'rcd',
      // Advanced: user-supplied global flags go FIRST — rclone (pflag) lets the
      // last occurrence of a repeated flag win, so ours below always take
      // precedence. That keeps the rc listener loopback-bound with per-session
      // creds no matter what a user pastes into the engine-flags setting.
      ...extraArgs,
      '--rc-addr',
      '127.0.0.1:$port',
      '--rc-user',
      user,
      '--rc-pass',
      pass,
      '--rc-serve',
      '--rc-job-expire-duration',
      '24h',
      if (configPath != null && configPath!.isNotEmpty) ...[
        '--config',
        configPath!,
      ],
    ];

    // RCLONE_CONFIG_PASS unlocks an encrypted config; inherits the parent env.
    final env = <String, String>{
      ...extraEnv,
      if (configPassword != null && configPassword!.isNotEmpty)
        'RCLONE_CONFIG_PASS': configPassword!,
    };
    _process = await Process.start(
      rclonePath,
      args,
      runInShell: false,
      environment: env.isEmpty ? null : env,
    );
    // Windows: bind the child to a kill-on-close job object so that even a hard
    // exit of THIS process (crash, "End task") cannot leave an orphaned rcd
    // running — an orphan keeps a handle open on rclone.exe in the install dir
    // and defeats clean uninstall. See WindowsChildJob. The PID marker below
    // stays as the belt-and-braces reap-on-next-launch path.
    WindowsChildJob.adopt(_process!.pid);
    // Record the new child's PID so a future launch can reap it if we crash.
    if (!Platform.isAndroid) {
      try {
        await _markerFile.writeAsString('${_process!.pid}');
      } catch (_) {
        /* non-fatal: reaping is best-effort */
      }
    }
    // Detect the child dying out from under us (crash/OOM); quit() exits are
    // expected and stay silent.
    _quitting = false;
    final watched = _process!;
    unawaited(
      watched.exitCode.then((_) {
        if (!_quitting && identical(_process, watched)) {
          _process = null;
          _port = null;
          _authHeader = null;
          onDied?.call();
        }
      }),
    );
    _loggedLines = 0;
    _lastLoggedLine = null;
    _drainChildOutput(watched);

    await _awaitReady();
  }

  /// Reads the `rcd` child's stdout AND stderr to end, always, on every build.
  ///
  /// This is not logging politeness, it is a deadlock fix. Dart creates a
  /// child's stdout/stderr as pipes with a **1 KiB** buffer on Windows, and a
  /// pipe nobody reads blocks its WRITER once that fills. rclone logs through
  /// Go's `log` package, which holds one global mutex across the write, so a
  /// single blocked line stalls every other goroutine that logs next —
  /// including the ones serving an OS mount. That is the shape of the freeze
  /// reported from the field: a burst of transfers, then Explorer wedged on the
  /// mounted drive, recovering only when Airclone is killed (which closes the
  /// read end, unblocks the write, and takes `rcd` down with it).
  ///
  /// Draining is free and removes the whole class of hang. What we do with the
  /// drained lines stays conservative — see [_onEngineLine].
  void _drainChildOutput(Process proc) {
    for (final stream in <Stream<List<int>>>[proc.stdout, proc.stderr]) {
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          // A decode/read error must never stop the drain — the moment this
          // subscription ends, the pipe starts filling again.
          .listen(_onEngineLine, onError: (Object _) {}, cancelOnError: false);
    }
  }

  /// At most this many engine lines per session reach the diagnostics ring. A
  /// remote failing every request would otherwise fill it with one repeated
  /// line and push out the context that makes a bug report readable.
  static const int _maxLoggedLines = 100;
  int _loggedLines = 0;
  String? _lastLoggedLine;

  /// Debug builds print every line. Release builds keep only rclone's own
  /// ERROR/CRITICAL lines, de-duplicated and capped, because at high user
  /// verbosity (-vv / --dump) rclone echoes request headers carrying the rc
  /// credentials — those must never be retained. The ring redacts at ingest as
  /// a second line of defence.
  void _onEngineLine(String line) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[rclone] $line');
      return;
    }
    if (_loggedLines >= _maxLoggedLines) return;
    if (!isEngineFailureLine(line)) return;
    if (line == _lastLoggedLine) return;
    _lastLoggedLine = line;
    _loggedLines++;
    logDiagnostic(DiagLevel.error, 'engine', line);
  }

  Future<void> _awaitReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) break;
      try {
        final res = await rpc('core/version');
        _version = res['version'] as String?;
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
    throw RcloneException('start', 'rclone rcd did not become ready in time');
  }

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (_port == null) {
      throw RcloneException(method, 'engine not started');
    }
    http.Response res;
    try {
      res = await _client
          .post(
            _uri(method),
            headers: {
              'Authorization': _authHeader!,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(params ?? const {}),
          )
          .timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      _noteTransportFailure(method, e);
      throw RcloneException(method, 'transport error: $e');
    }

    final body = res.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;

    if (res.statusCode ~/ 100 != 2) {
      final msg = (body['error'] ?? res.reasonPhrase ?? 'unknown error')
          .toString();
      throw RcloneException(method, msg, statusCode: res.statusCode);
    }
    return body;
  }

  DateTime? _lastTransportReport;

  /// Leaves evidence when the engine stops answering, at most once a minute.
  ///
  /// A wedged `rcd` answers nothing, so every poller in the app times out in
  /// turn and logging each would bury a report in identical lines. One entry a
  /// minute is enough to separate "Airclone is slow" from "the engine stopped
  /// answering" — which is exactly the question an OS-mount freeze raises, and
  /// the one a user cannot answer from the outside. Silent during [quit], where
  /// a refused connection is the expected outcome, not a symptom.
  void _noteTransportFailure(String method, Object error) {
    if (_quitting) return;
    final now = DateTime.now();
    final last = _lastTransportReport;
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastTransportReport = now;
    logDiagnostic(
      DiagLevel.warning,
      'engine',
      'no answer from the engine for $method',
      detail: '$error',
    );
  }

  /// Runs an arbitrary rclone subcommand via `core/command` with returnType
  /// STREAM and returns a LIVE stream of output lines (the console's Phase-3
  /// path). Desktop/HTTP only — librclone can't stream (`core/command` needs the
  /// live response writer), so this lives on the concrete client, not the seam.
  ///
  /// It is a plain synchronous streamed request — NEVER `_async` (that returns a
  /// jobid but the response writer dies) — and has NO rpc timeout, so a long
  /// command streams for as long as it runs. Cancelling the returned stream's
  /// subscription closes the HTTP request, which cancels rclone's command context
  /// and kills the spawned child — that is the console's Stop.
  Future<Stream<String>> commandStream(
    String command,
    List<String> args,
  ) async {
    if (_port == null) {
      throw RcloneException('core/command', 'engine not started');
    }
    final req = http.Request('POST', _uri('core/command'))
      ..headers['Authorization'] = _authHeader!
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'command': command,
        'arg': args,
        'returnType': 'STREAM',
      });
    final resp = await _client.send(req);
    if (resp.statusCode ~/ 100 != 2) {
      throw RcloneException(
        'core/command',
        'HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    // The body is an unframed byte pipe (chunked, no per-line flush); split it
    // into lines ourselves. Latin-1-safe UTF-8 decode tolerates a chunk that
    // splits a multibyte sequence.
    return resp.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
  }

  @override
  Future<void> quit() async {
    final proc = _process;
    if (proc == null) return;
    _quitting = true;
    try {
      await rpc('core/quit').timeout(const Duration(seconds: 3));
    } catch (_) {
      /* fall through to kill */
    }
    proc.kill();
    await proc.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    _process = null;
    _port = null;
    _authHeader = null;
    _version = null;
    // Clean shutdown: drop the reap marker so no future launch targets this PID.
    try {
      await _markerFile.delete();
    } catch (_) {
      /* already gone; ignore */
    }
  }

  @override
  Future<void> restart() async {
    await quit();
    await start();
  }

  @override
  Future<EngineStatus> status() async {
    if (_process == null) return EngineStatus.stopped;
    try {
      final res = await rpc('core/version');
      return EngineStatus(
        EngineState.running,
        version: res['version'] as String?,
      );
    } catch (e) {
      return EngineStatus(EngineState.error, version: _version, message: '$e');
    }
  }

  static Future<int> _freeLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static String _randomToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
