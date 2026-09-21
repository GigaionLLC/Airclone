/// Cancelling a sign-in, and cleaning up after one.
///
/// Two things have to happen and neither is optional. rclone blocks on a
/// listener holding port 53682, so an abandoned sign-in makes the NEXT attempt
/// fail to bind. And it writes `[name] type = …` as soon as a call returns at a
/// question, so an abandoned CREATE can leave behind a remote that exists and
/// cannot connect to anything.
library;

import 'dart:async';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/state/add_remote_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/providers_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

const _drive = RcloneProvider(
  name: 'drive',
  description: 'Google Drive',
  options: [ProviderOption(name: 'token', advanced: true)],
);

/// An engine with a sign-in genuinely in progress: the create runs as a job
/// that does not finish until the flow is cancelled.
class _SignInClient implements RcloneClient {
  _SignInClient({this.authUrl = 'http://127.0.0.1:53682/auth?state=abc123'});

  final String authUrl;
  final calls = <({String method, Map<String, dynamic>? params})>[];
  final Set<String> remotes = {};

  bool oauthRunning = false;
  bool finished = false;
  String jobError = '';

  /// Mimics a config file that cannot be written: delete reports 200 and the
  /// section survives.
  bool deleteSilentlyFails = false;

  /// An engine older than 1.75 has neither oauth method.
  bool modernOAuthMethods = true;

  /// A bind failure instead of a working listener.
  String? openingError;

  /// When set, the job finishes immediately with this question instead of
  /// blocking on a sign-in.
  Map<String, dynamic>? question;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    switch (method) {
      case 'config/dump':
        return {
          for (final r in remotes) r: {'type': 'drive'},
        };
      case 'config/create':
        final name = params?['name'] as String?;
        if (name != null) remotes.add(name);
        // A new call is a NEW job: a real engine does not hand the previous
        // job's outcome to the next one.
        finished = false;
        jobError = '';
        if (openingError != null) {
          finished = true;
          jobError = openingError!;
        } else if (question != null) {
          finished = true;
        } else {
          oauthRunning = true;
        }
        return {'jobid': 1};
      case 'job/status':
        return {
          'finished': finished,
          'error': jobError,
          'output': question ?? <String, dynamic>{},
        };
      case 'config/oauthstatus':
        if (!modernOAuthMethods) {
          throw RcloneException(method, 'method not found', statusCode: 404);
        }
        return oauthRunning
            ? {'status': 'running', 'authUrl': authUrl}
            : const {'status': 'stopped'};
      case 'config/oauthstop':
        if (!modernOAuthMethods) {
          throw RcloneException(method, 'method not found', statusCode: 404);
        }
        if (!oauthRunning) {
          // What rclone actually answers when nothing is running.
          throw RcloneException(
            method,
            'no oauth authentication is in progress',
            statusCode: 500,
          );
        }
        oauthRunning = false;
        finished = true;
        jobError =
            'config failed to refresh token: '
            'oauth authentication was cancelled';
        return const <String, dynamic>{};
      case 'config/delete':
        final name = params?['name'] as String?;
        if (!deleteSilentlyFails && name != null) remotes.remove(name);
        return const <String, dynamic>{};
      default:
        return const <String, dynamic>{};
    }
  }

  Iterable<({String method, Map<String, dynamic>? params})> to(String m) =>
      calls.where((c) => c.method == m);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._client);
  final RcloneClient _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);
}

ProviderContainer _container(_SignInClient client, {List<Uri>? opened}) {
  final c = ProviderContainer(
    overrides: [
      engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      providersProvider.overrideWith((ref) async => [_drive]),
      urlOpenerProvider.overrideWithValue((url) async {
        opened?.add(url);
        return true;
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Starts a sign-in and waits for the flow to reach the waiting screen.
Future<AddRemoteController> _reachSignIn(
  ProviderContainer c, {
  SignInMethod method = SignInMethod.thisDevice,
  String name = 'gdrive',
}) async {
  final ctrl = c.read(addRemoteControllerProvider.notifier);
  ctrl.pickProviderGuided(_drive);
  ctrl.setName(name);
  unawaited(ctrl.signIn(method));
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (c.read(addRemoteControllerProvider).phase == AddPhase.signingIn) break;
  }
  return ctrl;
}

void main() {
  test('the sign-in link comes from config/oauthstatus', () async {
    final opened = <Uri>[];
    final client = _SignInClient();
    final c = _container(client, opened: opened);
    await _reachSignIn(c);

    final state = c.read(addRemoteControllerProvider);
    expect(state.phase, AddPhase.signingIn);
    expect(
      state.authUrl.toString(),
      'http://127.0.0.1:53682/auth?state=abc123',
    );
    // "Sign in on this device" opens it; the others only show it.
    expect(opened, [state.authUrl]);
  });

  test('showing the link does not open a browser', () async {
    final opened = <Uri>[];
    final client = _SignInClient();
    final c = _container(client, opened: opened);
    await _reachSignIn(c, method: SignInMethod.showLink);
    expect(c.read(addRemoteControllerProvider).authUrl, isNotNull);
    expect(opened, isEmpty);
  });

  test('a url that is not rclone own listener is refused', () async {
    // config/oauthstatus is our own engine, but there is exactly one
    // definition of "a URL this app may open" and it is applied everywhere.
    final client = _SignInClient(authUrl: 'http://evil.example/auth?state=x');
    final opened = <Uri>[];
    final c = _container(client, opened: opened);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProviderGuided(_drive);
    ctrl.setName('gdrive');
    unawaited(ctrl.signIn(SignInMethod.thisDevice));
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(opened, isEmpty);
    expect(c.read(addRemoteControllerProvider).authUrl, isNull);
    await ctrl.cancelSignIn();
  });

  group('cancel', () {
    test('stops the flow and deletes the half-created remote', () async {
      final client = _SignInClient();
      final c = _container(client);
      final ctrl = await _reachSignIn(c);
      expect(client.remotes, contains('gdrive'));

      await ctrl.cancelSignIn();

      expect(client.to('config/oauthstop'), hasLength(1));
      expect(client.to('config/delete'), hasLength(1));
      expect(client.remotes, isNot(contains('gdrive')));
      final state = c.read(addRemoteControllerProvider);
      expect(state.phase, AddPhase.pickProvider);
      expect(state.error, isNull);
    });

    test('verifies the delete instead of trusting the status code', () async {
      // config/delete calls rclone DeleteRemote, which is void: deleting a
      // section that is not there is a no-op, and SaveConfig swallows its own
      // failure after retrying. So 200 means nothing, and the only way to know
      // is to look.
      final client = _SignInClient()..deleteSilentlyFails = true;
      final c = _container(client);
      final ctrl = await _reachSignIn(c);
      await ctrl.cancelSignIn();

      expect(client.to('config/dump'), isNotEmpty);
      final state = c.read(addRemoteControllerProvider);
      expect(state.phase, AddPhase.error);
      expect(state.error, contains('still in your config'));
    });

    test('an edit is never deleted', () async {
      final client = _SignInClient()..remotes.add('gdrive');
      final c = _container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      await ctrl.startEdit(
        const Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:'),
      );
      unawaited(ctrl.submitEdit());
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (c.read(addRemoteControllerProvider).phase == AddPhase.signingIn) {
          break;
        }
      }
      await ctrl.cancelSignIn();

      // Re-authorising an existing remote and changing your mind must not
      // remove the remote.
      expect(client.to('config/delete'), isEmpty);
      expect(client.remotes, contains('gdrive'));
    });

    test('cancelling twice is not an error', () async {
      // rclone answers 500 "no oauth authentication is in progress" the second
      // time. That is the state cancel wanted, not a failure.
      final client = _SignInClient();
      final c = _container(client);
      final ctrl = await _reachSignIn(c);
      await ctrl.cancelSignIn();
      await ctrl.cancelSignIn();
      expect(c.read(addRemoteControllerProvider).error, isNull);
    });

    test('an engine without oauthstop still gets cancelled', () async {
      // Pre-1.75 engines have neither method; the loopback GET is the fallback
      // and it is allowed to fail with nothing listening.
      final client = _SignInClient()..modernOAuthMethods = false;
      final c = _container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProviderGuided(_drive);
      ctrl.setName('gdrive');
      unawaited(ctrl.signIn(SignInMethod.thisDevice));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await ctrl.cancelSignIn();

      // The remote still has to go, whatever happened to the listener.
      expect(client.to('config/delete'), hasLength(1));
      expect(client.remotes, isNot(contains('gdrive')));
    });
  });

  test('an old engine that never reports a link says so', () async {
    final client = _SignInClient()..modernOAuthMethods = false;
    final c = _container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProviderGuided(_drive);
    ctrl.setName('gdrive');
    unawaited(ctrl.signIn(SignInMethod.thisDevice));
    // The deadline is 10s; wait past it rather than spin on a spinner that
    // would never move.
    for (var i = 0; i < 240; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (c.read(addRemoteControllerProvider).authUrlUnavailable) break;
    }
    final state = c.read(addRemoteControllerProvider);
    expect(state.phase, AddPhase.signingIn);
    expect(state.authUrlUnavailable, isTrue);
    expect(state.authUrl, isNull);
    await ctrl.cancelSignIn();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('abandoning at a QUESTION also leaves nothing behind', () async {
    // rclone writes the section as soon as a call returns at a question, so
    // walking away from the shared-client_id screen leaves exactly the same
    // unusable remote as abandoning the sign-in would.
    final client = _SignInClient()
      ..question = {
        'State': 'client_id_warning',
        'Option': {'Name': 'config_shared_client_id', 'Type': 'bool'},
      };
    final c = _container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProviderGuided(_drive);
    ctrl.setName('gdrive');
    await ctrl.signIn(SignInMethod.thisDevice);

    final state = c.read(addRemoteControllerProvider);
    expect(state.phase, AddPhase.question);
    // This is the marker the dialog's dispose keys its cleanup on.
    expect(state.createdName, 'gdrive');

    await ctrl.cancelSignIn();
    expect(client.remotes, isNot(contains('gdrive')));
  });

  test('a finished create is not something cancel would delete', () async {
    final client = _SignInClient()..question = <String, dynamic>{};
    final c = _container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProviderGuided(_drive);
    ctrl.setName('gdrive');
    await ctrl.signIn(SignInMethod.thisDevice);

    final state = c.read(addRemoteControllerProvider);
    expect(state.phase, AddPhase.done);
    // Cleared on success. A `createdName: null` in copyWith could NOT clear it
    // — the field merges with `??` — and a stale marker here would have the
    // dialog delete the remote it had just successfully created.
    expect(state.createdName, isNull);
  });

  test('a retry may reuse the name this same flow claimed', () async {
    // The taken-name guard exists to stop config/create silently REPLACING
    // somebody else's remote. It must not refuse the stub this attempt wrote
    // a moment ago, or Retry and "enter the details myself" both dead-end.
    final client = _SignInClient();
    final c = _container(client);
    final ctrl = await _reachSignIn(c);
    expect(client.remotes, contains('gdrive'));

    // Not awaited: a successful retry blocks on the NEW sign-in, exactly as
    // the first attempt did.
    unawaited(ctrl.retryAfterCancel());
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (c.read(addRemoteControllerProvider).phase == AddPhase.signingIn) {
        break;
      }
    }

    final state = c.read(addRemoteControllerProvider);
    expect(state.error, isNull, reason: 'the retry must not be refused');
    expect(state.phase, AddPhase.signingIn);
    expect(client.to('config/delete'), isNotEmpty);
    expect(client.to('config/create'), hasLength(2));
    await ctrl.cancelSignIn();
  });

  test(
    'an error quoting a credential is redacted before it is shown',
    () async {
      final client = _SignInClient()
        ..openingError =
            'failed to connect to '
            'https://admin:hunter2@nas.example/dav: 401';
      final c = _container(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProviderGuided(_drive);
      ctrl.setName('gdrive');
      await ctrl.signIn(SignInMethod.thisDevice);

      final error = c.read(addRemoteControllerProvider).error!;
      // Redaction runs at ingest for diagnostics; a screen needs the same
      // treatment, because a screenshot is a publishing channel.
      expect(error, isNot(contains('hunter2')));
      expect(error, contains('<credentials>'));
    },
  );

  test('renaming after a failure does not orphan the first stub', () async {
    // The user reaches the failure screen, chooses "enter the details myself",
    // and types a different name. Nothing else would ever clean up the section
    // written under the FIRST name — cancel only knows about the current one.
    final client = _SignInClient()..openingError = 'something went wrong';
    final c = _container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProviderGuided(_drive);
    ctrl.setName('gdrive');
    await ctrl.signIn(SignInMethod.thisDevice);
    expect(client.remotes, contains('gdrive'));
    expect(c.read(addRemoteControllerProvider).phase, AddPhase.error);

    ctrl.switchToAdvanced();
    ctrl.setName('gdrive-personal');
    await ctrl.submit();

    expect(
      client.remotes,
      isNot(contains('gdrive')),
      reason: 'the abandoned stub must not be left behind',
    );
    expect(client.remotes, contains('gdrive-personal'));
  });

  test('a message from startEdit is redacted before it is shown', () async {
    final client = _RefusingEditClient();
    final c = _container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    await ctrl.startEdit(const Remote(name: 'nas', type: 'drive', fs: 'nas:'));
    final error = c.read(addRemoteControllerProvider).error!;
    expect(error, isNot(contains('hunter2')));
    expect(error, contains('<credentials>'));
  });

  test('a bind failure is explained, not echoed', () async {
    final client = _SignInClient()
      ..openingError =
          'failed to start auth webserver: listen tcp '
          '127.0.0.1:53682: bind: address already in use';
    final c = _container(client);
    final ctrl = c.read(addRemoteControllerProvider.notifier);
    ctrl.pickProviderGuided(_drive);
    ctrl.setName('gdrive');
    await ctrl.signIn(SignInMethod.thisDevice);

    final state = c.read(addRemoteControllerProvider);
    expect(state.phase, AddPhase.error);
    expect(state.error, contains('$kOAuthPort'));
    expect(state.error, contains('already in use'));
    // The error screen offers a retry that cancels first, which is what makes
    // the port recoverable.
    expect(state.error, contains('Try again'));
  });
}

/// An engine whose `config/get` fails with a message quoting a credential.
class _RefusingEditClient extends _SignInClient {
  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'config/get') {
      throw RcloneException(
        method,
        'cannot read https://admin:hunter2@nas.example/dav',
      );
    }
    return super.rpc(method, params);
  }
}
