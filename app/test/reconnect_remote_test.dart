/// "Sign in again" (issue #27): what it puts on the wire, and what it must
/// never do.
///
/// The promise to the user is "only the sign-in is replaced". On the wire that
/// means: config/update (never create, never delete), the refresh answered up
/// front, and none of the saved values re-sent.
library;

import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/add_remote_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/providers_provider.dart';
import 'package:airclone/src/state/reconnect.dart';
import 'package:airclone/src/ui/add_remote_dialog.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

class _Client implements RcloneClient {
  final calls = <({String method, Map<String, dynamic>? params})>[];

  /// Queued answers to config/update, in order.
  final scripted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    switch (method) {
      case 'config/get':
        return {
          'type': 'drive',
          'scope': 'drive',
          'team_drive': '0ABCdef',
          'token': '{"access_token":"x","refresh_token":"y"}',
        };
      case 'config/oauthstatus':
        return {'status': 'stopped'};
      case 'config/update':
        return scripted.isEmpty ? <String, dynamic>{} : scripted.removeAt(0);
      default:
        return <String, dynamic>{};
    }
  }

  /// The calls that write the config.
  Iterable<({String method, Map<String, dynamic>? params})> get configCalls =>
      calls.where(
        (c) => const {
          'config/create',
          'config/update',
          'config/delete',
        }.contains(c.method),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._client);
  final RcloneClient _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);
}

const _drive = RcloneProvider(
  name: 'drive',
  description: 'Google Drive',
  options: [
    ProviderOption(name: 'client_id'),
    ProviderOption(name: 'scope'),
    ProviderOption(name: 'team_drive', advanced: true),
    ProviderOption(name: 'token', advanced: true),
  ],
);

const _sftp = RcloneProvider(
  name: 'sftp',
  description: 'SSH/SFTP',
  options: [ProviderOption(name: 'host', required: true)],
);

const _gd = Remote(name: 'gd', type: 'drive', fs: 'gd:');

ProviderContainer _container(_Client client) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      providersProvider.overrideWith((ref) async => [_drive, _sftp]),
      urlOpenerProvider.overrideWithValue((_) async => true),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  widgetTests();

  test('startReconnect lands on the sign-in screen as an edit', () async {
    final client = _Client();
    final c = _container(client);
    await c.read(addRemoteControllerProvider.notifier).startReconnect(_gd);

    final s = c.read(addRemoteControllerProvider);
    expect(s.phase, AddPhase.setup);
    expect(s.mode, AddMode.guided);
    expect(s.reconnect, isTrue);
    // isEdit is what keeps cancel from deleting the remote.
    expect(s.isEdit, isTrue);
    expect(s.editName, 'gd');
    expect(s.sticky[kRefreshTokenAnswer], 'true');
    // Loaded to name the cloud, never to be sent; the token is not even kept.
    expect(s.values.containsKey('token'), isFalse);
    expect(client.configCalls, isEmpty);
  });

  test(
    'signing in sends config/update with only the config_* answers',
    () async {
      final client = _Client();
      final c = _container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      await ctrl.startReconnect(_gd);
      await ctrl.signIn(SignInMethod.thisDevice);

      final calls = client.configCalls.toList();
      expect(calls.map((x) => x.method), ['config/update']);
      final params = calls.single.params!;
      expect(params['name'], 'gd');
      expect(params.containsKey('type'), isFalse);
      final sent = params['parameters'] as Map<String, dynamic>;
      // Every key ephemeral: nothing rclone would persist, and none of the saved
      // values (scope, team_drive) re-sent.
      expect(
        sent.keys.every((k) => k.startsWith('config_')),
        isTrue,
        reason: '$sent',
      );
      expect(sent[kRefreshTokenAnswer], 'true');
      expect(sent['config_is_local'], 'true');
      expect(sent['config_auth_no_browser'], 'true');

      final s = c.read(addRemoteControllerProvider);
      expect(s.phase, AddPhase.done);
      expect(s.reconnect, isTrue);
    },
  );

  test(
    'a question after the sign-in continues as an update, refresh kept',
    () async {
      final client = _Client()
        ..scripted.add({
          'State': 'teamdrive_ok',
          'Option': {'Name': 'config_change_team_drive', 'Type': 'bool'},
        });
      final c = _container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      await ctrl.startReconnect(_gd);
      await ctrl.signIn(SignInMethod.thisDevice);
      expect(c.read(addRemoteControllerProvider).phase, AddPhase.question);

      await ctrl.answer('false');
      final cont = client.configCalls.last.params!;
      expect(
        client.configCalls.every((x) => x.method == 'config/update'),
        isTrue,
      );
      expect((cont['opt'] as Map)['continue'], isTrue);
      expect((cont['parameters'] as Map)[kRefreshTokenAnswer], 'true');
    },
  );

  test(
    'cancelling deletes nothing and returns to the sign-in screen',
    () async {
      final client = _Client();
      final c = _container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      await ctrl.startReconnect(_gd);
      await ctrl.cancelSignIn();

      expect(client.calls.any((x) => x.method == 'config/delete'), isFalse);
      final s = c.read(addRemoteControllerProvider);
      expect(s.phase, AddPhase.setup);
      expect(s.reconnect, isTrue);
    },
  );

  test('a remote without a sign-in is refused, with nothing sent', () async {
    final client = _Client();
    final c = _container(client);
    await c
        .read(addRemoteControllerProvider.notifier)
        .startReconnect(const Remote(name: 'box', type: 'sftp', fs: 'box:'));

    final s = c.read(addRemoteControllerProvider);
    expect(s.phase, AddPhase.error);
    expect(s.reconnect, isTrue);
    expect(client.configCalls, isEmpty);
  });

  test('remoteUsesSignInProvider follows the backend options', () async {
    final c = _container(_Client());
    await c.read(providersProvider.future);
    expect(c.read(remoteUsesSignInProvider('drive')), isTrue);
    expect(c.read(remoteUsesSignInProvider('sftp')), isFalse);
    expect(c.read(remoteUsesSignInProvider('nope')), isFalse);
  });

  group('looksLikeExpiredSignIn', () {
    for (final m in [
      'oauth2: "invalid_grant" "Token has been expired or revoked."',
      "couldn't fetch token: unauthorized_client",
      'failed to get token: oauth2: cannot fetch token: 400 Bad Request',
      'empty token found - please run "rclone config reconnect gd:"',
      'InvalidAuthenticationToken: Access token has expired',
      'HTTP error 401 (401 Unauthorized)',
    ]) {
      test('yes: $m', () => expect(looksLikeExpiredSignIn(m), isTrue));
    }
    for (final m in [
      null,
      '',
      'directory not found',
      'context deadline exceeded',
      'quota exceeded',
    ]) {
      test('no: $m', () => expect(looksLikeExpiredSignIn(m), isFalse));
    }
  });
}

/// The dialog itself, at phone width: the reconnect screen names the remote,
/// asks for no name, and fits.
Future<void> _pumpReconnect(WidgetTester tester, _Client client) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        providersProvider.overrideWith((ref) async => [_drive, _sftp]),
        urlOpenerProvider.overrideWithValue((_) async => true),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showReconnectRemoteDialog(ctx, _gd),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void widgetTests() {
  testWidgets('the reconnect screen names the remote and asks no name', (
    tester,
  ) async {
    await _pumpReconnect(tester, _Client());
    expect(find.text('Sign in to gd again'), findsOneWidget);
    expect(find.text('Name'), findsNothing);
    expect(find.text('Advanced'), findsNothing);
    expect(find.byKey(const ValueKey('sign-in-primary')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finished reconnect says so and offers no "Add another"', (
    tester,
  ) async {
    final client = _Client();
    await _pumpReconnect(tester, client);
    await tester.tap(find.byKey(const ValueKey('sign-in-primary')));
    await tester.pumpAndSettle();
    expect(find.text('Signed in to gd again'), findsOneWidget);
    expect(find.text('Add another'), findsNothing);
    expect(
      client.configCalls.map((x) => x.method),
      everyElement('config/update'),
    );
  });
}
