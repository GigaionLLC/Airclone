/// Google's retiring shared sign-in, replayed from the real transcript.
///
/// rclone 1.75 stopped opening Drive and Google Photos straight into OAuth: it
/// asks first, because the shared client_id is being retired "during 2026", and
/// its own default answer is to decline. A one-click sign-in that quietly
/// answered yes would enrol people in something with a stated expiry, so this
/// is a screen — and it is driven by the question rclone asks rather than by a
/// list of provider names, which these tests are what prove.
library;

import 'package:airclone/src/state/add_remote_controller.dart';
import 'package:airclone/src/ui/add_remote/own_client_id_step.dart';
import 'package:airclone_rc/airclone_rc.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

import 'support/config_flow_fixtures.dart';

void main() {
  group('the captured transcript itself', () {
    test('Drive opens on the warning, not on OAuth', () {
      final flow = ConfigFlow('drive_declines_shared_id');
      final option = flow.opening['Option'] as Map<String, dynamic>;
      expect(flow.opening['State'], 'client_id_warning');
      expect(option['Name'], 'config_shared_client_id');
      expect(option['Type'], 'bool');
      // rclone's own default is to DECLINE the shared id.
      expect(option['DefaultStr'], 'false');
      expect(
        (option['Help'] as String),
        contains('will stop working during 2026'),
      );
    });

    test('Google Photos asks the same question', () {
      expect(
        ConfigFlow('googlephotos_declines_shared_id').questionNames.first,
        'config_shared_client_id',
      );
    });

    test('Google Cloud Storage does NOT', () {
      // Same vendor, no warning — which is why the screen has to follow the
      // question rather than the provider name.
      final flow = ConfigFlow('googlecloudstorage');
      expect(flow.questionNames.first, 'config_is_local');
      expect(flow.opening['State'], startsWith('*oauth'));
    });

    test('accepting the shared id goes straight to sign-in', () {
      final flow = ConfigFlow('drive_accepts_shared_id');
      final next = flow.resultAfter('client_id_warning')!;
      expect(next['State'], '*oauth-islocal,teamdrive,oauth,');
      expect((next['Option'] as Map)['Name'], 'config_is_local');
    });

    test('declining asks for the client id, which is required', () {
      final flow = ConfigFlow('drive_declines_shared_id');
      final next = flow.resultAfter('client_id_warning')!;
      expect(next['State'], 'client_id_set');
      final option = next['Option'] as Map<String, dynamic>;
      expect(option['Name'], 'client_id');
      expect(option['Required'], isTrue);
    });

    test('OneDrive has a question AFTER sign-in, unlike Dropbox', () {
      // The state carries the step to run once OAuth finishes, so the flow
      // cannot assume sign-in is the last thing that happens.
      expect(
        ConfigFlow('onedrive').opening['State'],
        '*oauth-islocal,choose_type,,',
      );
      expect(ConfigFlow('dropbox').opening['State'], '*oauth-islocal,,,');
    });

    test('backends with no interactive config ask nothing at all', () {
      // 46 of 69 are like this: with `all` off they return immediately, having
      // written only `type = <backend>`. That is what the recipes exist for.
      for (final name in ['b2_asks_nothing', 'sftp_asks_nothing']) {
        final flow = ConfigFlow(name);
        expect(flow.opening['State'], '');
        expect(flow.opening['Option'], isNull);
      }
    });
  });

  group('routing', () {
    test('the warning is recognised by its question name', () {
      const q = ProviderOption(name: 'config_shared_client_id', type: 'bool');
      expect(isSharedClientIdQuestion(q), isTrue);
      expect(isOwnClientIdQuestion(q), isFalse);
      expect(isSharedClientIdQuestion(null), isFalse);
    });

    test('the two follow-up fields get their own screen', () {
      expect(
        isOwnClientIdQuestion(const ProviderOption(name: 'client_id')),
        isTrue,
      );
      expect(
        isOwnClientIdQuestion(const ProviderOption(name: 'client_secret')),
        isTrue,
      );
      expect(
        isOwnClientIdQuestion(const ProviderOption(name: 'config_is_local')),
        isFalse,
      );
    });
  });

  group('driving the flow', () {
    test('declining reaches the client_id question', () async {
      final client = TranscriptClient(ConfigFlow('drive_declines_shared_id'));
      final c = flowContainer(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProviderGuided(oauthProvider('drive'));
      ctrl.setName('gdrive');
      await ctrl.signIn(SignInMethod.thisDevice);

      var state = c.read(addRemoteControllerProvider);
      expect(state.phase, AddPhase.question);
      expect(state.question!.name, 'config_shared_client_id');

      await ctrl.answer('false');
      state = c.read(addRemoteControllerProvider);
      expect(state.phase, AddPhase.question);
      expect(state.question!.name, 'client_id');
      expect(isOwnClientIdQuestion(state.question), isTrue);
    });

    test('accepting reaches the sign-in question', () async {
      final client = TranscriptClient(ConfigFlow('drive_accepts_shared_id'));
      final c = flowContainer(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProviderGuided(oauthProvider('drive'));
      ctrl.setName('gdrive');
      await ctrl.signIn(SignInMethod.thisDevice);
      await ctrl.answer('true');

      final state = c.read(addRemoteControllerProvider);
      expect(state.question!.name, 'config_is_local');
      expect(state.questionState, startsWith('*oauth'));
    });

    test('the sign-in answers ride along on every later call', () async {
      // config_is_local and config_auth_no_browser are ephemeral: rclone strips
      // them before saving and rebuilds its answers from `parameters`, so an
      // answer sent once is gone by the next step.
      final client = TranscriptClient(ConfigFlow('drive_declines_shared_id'));
      final c = flowContainer(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProviderGuided(oauthProvider('drive'));
      ctrl.setName('gdrive');
      await ctrl.signIn(SignInMethod.thisDevice);
      await ctrl.answer('false');

      for (final call in client.callsTo('config/create')) {
        final params = call.params!['parameters'] as Map;
        expect(params['config_is_local'], 'true');
        expect(params['config_auth_no_browser'], 'true');
      }
    });

    test('signing in elsewhere asks rclone for the other flow', () async {
      final client = TranscriptClient(ConfigFlow('drive_accepts_shared_id'));
      final c = flowContainer(client);
      final ctrl = c.read(addRemoteControllerProvider.notifier);
      ctrl.pickProviderGuided(oauthProvider('drive'));
      ctrl.setName('gdrive');
      await ctrl.signIn(SignInMethod.otherDevice);

      final params =
          client.callsTo('config/create').first.params!['parameters'] as Map;
      expect(params['config_is_local'], 'false');
      // Nothing local is being opened, so suppressing the browser is moot and
      // must not be sent — it would be answering a question nobody asked.
      expect(params.containsKey('config_auth_no_browser'), isFalse);
    });
  });
}
