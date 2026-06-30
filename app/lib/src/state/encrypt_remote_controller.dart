import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/rclone_client.dart';
import 'engine_controller.dart';
import 'remotes_provider.dart';

enum EncryptPhase { form, creating, verifying, done, error }

/// State of the encrypt-a-remote (crypt) wizard. **Holds no secrets** — the
/// password is passed as a transient argument to [EncryptRemoteController.submit]
/// and never stored here (or in any provider), so it can't outlive the dialog.
@immutable
class EncryptRemoteState {
  const EncryptRemoteState({
    this.phase = EncryptPhase.form,
    this.error,
    this.verifyOk,
    this.verifyMessage,
  });

  final EncryptPhase phase;
  final String? error;

  /// Verification outcome once [phase] is done: true = reachable/clean,
  /// false = differences reported, null = couldn't run the check (non-fatal).
  final bool? verifyOk;
  final String? verifyMessage;
}

/// Creates a `crypt` remote wrapping an existing one, then (best-effort) verifies
/// it. The plaintext password travels exactly once, over the loopback rcd (same
/// trust boundary as the add-remote flow), is obscured server-side by rclone
/// (`opt.obscure`), and is never persisted or logged by Airclone.
class EncryptRemoteController extends Notifier<EncryptRemoteState> {
  @override
  EncryptRemoteState build() => const EncryptRemoteState();

  void reset() => state = const EncryptRemoteState();

  /// [baseFs] is the already-assembled `base:subdir` (no secret). [password] /
  /// [password2] are transient — used to build the request and then dropped.
  Future<void> submit({
    required String name,
    required String baseFs,
    required String filenameEncryption,
    required bool dirNameEncryption,
    required String password,
    String? password2,
  }) async {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      state = const EncryptRemoteState(
        phase: EncryptPhase.error,
        error: 'Engine not ready',
      );
      return;
    }
    state = const EncryptRemoteState(phase: EncryptPhase.creating);
    final cryptName = name.trim();
    try {
      final res = await client.rpc('config/create', {
        'name': cryptName,
        'type': 'crypt',
        'parameters': {
          'remote': baseFs,
          'filename_encryption': filenameEncryption,
          'directory_name_encryption': '$dirNameEncryption',
          'password': password,
          if (password2 != null && password2.isNotEmpty) 'password2': password2,
        },
        // obscure: rclone obscures the IsPassword fields server-side. Do NOT
        // also pre-obscure (would double-obscure). Never log this body.
        'opt': {'nonInteractive': true, 'obscure': true},
      });
      final err = (res['Error'] as String?) ?? '';
      if (err.isNotEmpty) {
        state = EncryptRemoteState(phase: EncryptPhase.error, error: err);
        return;
      }
      // The crypt remote now exists — surface it in the sidebar.
      ref.invalidate(remotesProvider);
      state = const EncryptRemoteState(phase: EncryptPhase.verifying);
      await _verify(client, baseFs, '$cryptName:');
    } on RcloneException catch (e) {
      state = EncryptRemoteState(phase: EncryptPhase.error, error: e.message);
    } catch (e) {
      state = EncryptRemoteState(phase: EncryptPhase.error, error: '$e');
    }
  }

  /// Best-effort verify via `cryptcheck` (desktop core/command). Never fails the
  /// wizard — the remote already exists; the exit/error field is the source of
  /// truth (output text is for display only).
  Future<void> _verify(
    RcloneClient client,
    String baseFs,
    String cryptFs,
  ) async {
    try {
      final res = await client.rpc('core/command', {
        'command': 'cryptcheck',
        'arg': [baseFs, cryptFs],
        'opt': {'one-way': 'true'},
        'returnType': 'COMBINED_OUTPUT',
      });
      final errVal = res['error'];
      final failed = errVal == true || (errVal is num && errVal != 0);
      final out = (res['result'] as String?)?.trim();
      state = EncryptRemoteState(
        phase: EncryptPhase.done,
        verifyOk: !failed,
        verifyMessage: (out == null || out.isEmpty) ? null : out,
      );
    } catch (_) {
      // core/command unavailable or transport error — created, just unverified.
      state = const EncryptRemoteState(
        phase: EncryptPhase.done,
        verifyOk: null,
        verifyMessage: null,
      );
    }
  }
}

final encryptRemoteControllerProvider =
    NotifierProvider<EncryptRemoteController, EncryptRemoteState>(
      EncryptRemoteController.new,
    );
