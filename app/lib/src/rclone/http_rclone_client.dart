import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'rclone_client.dart';

/// Desktop [RcloneClient]: spawns `rclone rcd` bound to loopback with per-session
/// credentials, and drives it over HTTP. See `wiki/core/08-core-architecture.md` §3.
class HttpRcloneClient implements RcloneClient {
  HttpRcloneClient({
    required this.rclonePath,
    this.configPath,
    this.configPassword,
  });

  /// Path to the rclone binary (from [RcloneEngine]).
  final String rclonePath;

  /// Optional explicit `--config` path; null uses rclone's default.
  final String? configPath;

  /// Config-encryption password, passed via `RCLONE_CONFIG_PASS` (never persisted,
  /// never on the command line). Null for unencrypted configs.
  final String? configPassword;

  Process? _process;
  int? _port;
  String? _authHeader;
  String? _version;
  final _client = http.Client();

  Uri _uri(String method) => Uri.parse('http://127.0.0.1:$_port/$method');

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

    final port = await _freeLoopbackPort();
    final user = 'airclone';
    final pass = _randomToken();
    _port = port;
    _authHeader = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

    final args = <String>[
      'rcd',
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

    _process = await Process.start(
      rclonePath,
      args,
      runInShell: false,
      // RCLONE_CONFIG_PASS unlocks an encrypted config; inherits the parent env.
      environment: configPassword != null && configPassword!.isNotEmpty
          ? {'RCLONE_CONFIG_PASS': configPassword!}
          : null,
    );
    // Surface engine stderr to the app log for diagnostics.
    _process!.stderr.transform(utf8.decoder).listen((line) {
      // ignore: avoid_print
      print('[rclone] $line');
    });

    await _awaitReady();
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

  @override
  Future<void> quit() async {
    final proc = _process;
    if (proc == null) return;
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
