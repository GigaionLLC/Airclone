/// Replays real rclone config transcripts through a fake client.
///
/// The transcripts in `test/fixtures/config_flows/interactive_flows.json` were
/// captured from rclone v1.75.1 by driving librclone directly
/// (`dev/plans/fd2-probe/capture_flow.dart`). Replaying them is the difference
/// between testing what rclone does and testing what we assumed it does — the
/// shared-client_id warning was found exactly this way, by capturing rather
/// than imagining.
library;

import 'dart:convert';
import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/state/add_remote_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/providers_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

Map<String, dynamic> _flows() {
  final raw = File(
    'test/fixtures/config_flows/interactive_flows.json',
  ).readAsStringSync();
  return (jsonDecode(raw) as Map<String, dynamic>)['flows']
      as Map<String, dynamic>;
}

/// One captured walk through the config machine.
class ConfigFlow {
  ConfigFlow(this.name) : _steps = _load(name);

  static List<Map<String, dynamic>> _load(String name) {
    final flow = _flows()[name];
    if (flow == null) {
      throw StateError('no captured flow called "$name"');
    }
    return ((flow as Map)['steps'] as List).cast<Map<String, dynamic>>();
  }

  final String name;
  final List<Map<String, dynamic>> _steps;

  /// The backend this flow was captured against.
  String get type => ((_flows()[name] as Map)['type'] ?? '') as String;

  /// What the opening `config/create` returned.
  Map<String, dynamic> get opening =>
      _steps.first['result'] as Map<String, dynamic>;

  /// What a continue answering [state] returned.
  Map<String, dynamic>? resultAfter(String state) {
    for (var i = 0; i < _steps.length - 1; i++) {
      final result = _steps[i]['result'] as Map<String, dynamic>;
      if (result['State'] == state) {
        return _steps[i + 1]['result'] as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// The questions this flow asked, in order.
  List<String> get questionNames => [
    for (final s in _steps)
      if ((s['result'] as Map)['Option'] != null)
        (((s['result'] as Map)['Option'] as Map)['Name'] ?? '') as String,
  ];
}

/// A client that answers config calls from a captured transcript.
class TranscriptClient implements RcloneClient {
  TranscriptClient(this.flow);

  final ConfigFlow flow;
  final calls = <({String method, Map<String, dynamic>? params})>[];

  /// Existing remotes, for the name check and the post-delete verification.
  final Set<String> remotes = {};

  /// When false, `config/oauthstop` fails the way an engine without the method
  /// does, so the fallback path can be exercised.
  bool oauthStopSupported = true;

  /// When true, `config/delete` reports success but the section survives —
  /// which is what a config file that cannot be written looks like from here.
  bool deleteSilentlyFails = false;

  /// Set once the opening call has run, mirroring rclone writing the section
  /// as soon as a call returns at a question.
  bool sectionWritten = false;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    switch (method) {
      case 'config/dump':
        return {
          for (final r in remotes) r: {'type': flow.type},
        };
      case 'config/oauthstatus':
        return const {'status': 'stopped'};
      case 'config/oauthstop':
        if (!oauthStopSupported) {
          throw RcloneException(method, 'method not found', statusCode: 404);
        }
        return const <String, dynamic>{};
      case 'config/delete':
        final name = params?['name'] as String?;
        if (!deleteSilentlyFails && name != null) remotes.remove(name);
        // rclone answers 200 whether it deleted anything or not.
        return const <String, dynamic>{};
      case 'config/create':
        final opt = params?['opt'] as Map<String, dynamic>?;
        if (opt?['continue'] == true) {
          final next = flow.resultAfter(opt!['state'] as String);
          return next ?? const <String, dynamic>{};
        }
        sectionWritten = true;
        final name = params?['name'] as String?;
        if (name != null) remotes.add(name);
        return flow.opening;
      default:
        return const <String, dynamic>{};
    }
  }

  Iterable<({String method, Map<String, dynamic>? params})> callsTo(
    String method,
  ) => calls.where((c) => c.method == method);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEngine extends EngineController {
  FakeEngine(this._client);
  final RcloneClient _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);
}

/// A provider list good enough for the driver: the name and a `token` option,
/// which is how the app detects that a backend signs in.
RcloneProvider oauthProvider(String name) => RcloneProvider(
  name: name,
  description: name,
  options: const [
    ProviderOption(name: 'client_id'),
    ProviderOption(name: 'client_secret'),
    ProviderOption(name: 'token', advanced: true),
  ],
);

ProviderContainer flowContainer(
  TranscriptClient client, {
  List<RcloneProvider>? providers,
  List<Uri>? opened,
}) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => FakeEngine(client)),
      providersProvider.overrideWith(
        (ref) async => providers ?? [oauthProvider(client.flow.type)],
      ),
      urlOpenerProvider.overrideWithValue((url) async {
        opened?.add(url);
        return true;
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}
