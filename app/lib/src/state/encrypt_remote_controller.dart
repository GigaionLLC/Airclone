import 'dart:math';

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

  /// Round-trip canary outcome once [phase] is done (see [_verify]): true =
  /// names proven to encrypt AND decrypt end-to-end, false = the probe's name
  /// showed up unencrypted on the base remote (encryption not taking effect),
  /// null = couldn't confirm (name encryption off by design, or the check
  /// itself errored). Always non-fatal — the remote already exists either way.
  final bool? verifyOk;
  final String? verifyMessage;
}

/// Creates a `crypt` remote wrapping an existing one, then (best-effort) verifies
/// it. The plaintext password travels exactly once, over the loopback rcd (same
/// trust boundary as the add-remote flow), is obscured server-side by rclone
/// (`opt.obscure`), and is never persisted or logged by Airclone.
class EncryptRemoteController extends Notifier<EncryptRemoteState> {
  static final _rng = Random();

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
      await _verify(
        client,
        baseFs,
        '$cryptName:',
        filenameEncryption,
        dirNameEncryption,
      );
    } on RcloneException catch (e) {
      state = EncryptRemoteState(phase: EncryptPhase.error, error: e.message);
    } catch (e) {
      state = EncryptRemoteState(phase: EncryptPhase.error, error: '$e');
    }
  }

  /// Best-effort **round-trip canary** that actually exercises the configured
  /// key — replacing the old `cryptcheck`, which trivially passed on empty
  /// remotes and false-alarmed on populated ones without ever proving the key
  /// decrypts. Uses only safe RC primitives (this project avoids `core/command`
  /// where possible). Never fails the wizard — the remote already exists; the
  /// result is the tri-state hint documented on [EncryptRemoteState.verifyOk].
  ///
  /// The probe is a directory (`operations/mkdir` — the one write primitive that
  /// needs no payload) created THROUGH the crypt remote, then read back two
  /// ways: through the crypt remote (its plaintext name reappearing proves
  /// rclone decrypted what it just wrote) and through the BASE remote (a
  /// *different*, scrambled name there proves the name was encrypted on the way
  /// down). A wrong key on reattach yields garbage/mismatch; a mis-wired remote
  /// leaks the plaintext name straight through to the base.
  Future<void> _verify(
    RcloneClient client,
    String baseFs,
    String cryptFs,
    String filenameEncryption,
    bool dirNameEncryption,
  ) async {
    // Our probe is a *directory*, so its name is only encrypted when BOTH
    // filename encryption is on AND directory-name encryption is on; otherwise
    // rclone stores the folder name verbatim and a base/crypt name diff is
    // impossible by design — we can then only honestly report reachability.
    final dirNamesEncrypted = filenameEncryption != 'off' && dirNameEncryption;
    // UNIQUE per-run probe name (random suffix). With `filename_encryption=off`
    // the crypt stores the name verbatim, so this dir is a REAL dir at the
    // wrapped base location — a fixed name could collide with a user-owned
    // `.airclone-verify` (or a stale crashed-run dir) and get destroyed on
    // cleanup. A random suffix guarantees the name is ours alone.
    final probe = '.airclone-verify-${_rng.nextInt(1 << 32).toRadixString(36)}';
    // Only clean up a dir OUR mkdir call actually created — never a pre-existing
    // dir (rclone's Mkdir is idempotent, so a plain success doesn't prove we
    // made it; the unique name makes a collision astronomically unlikely, and
    // this flag skips cleanup entirely on the mkdir-threw path).
    var created = false;
    try {
      // 1. Create the probe THROUGH the crypt remote.
      await client.rpc('operations/mkdir', {'fs': cryptFs, 'remote': probe});
      created = true;
      // 2. Read the crypt root back — the probe under its plaintext name proves
      //    rclone decrypted the name it just wrote.
      final cryptHasProbe = (await _dirNames(client, cryptFs)).contains(probe);

      if (!dirNamesEncrypted) {
        // Names match by design; the only honest claim is reachability.
        state = EncryptRemoteState(
          phase: EncryptPhase.done,
          verifyOk: null,
          verifyMessage: cryptHasProbe
              ? 'Created — reachability checked; folder-name encryption is off.'
              : null,
        );
      } else {
        // 3. List the SAME location through the BASE remote. If names encrypt,
        //    the base shows a scrambled name, never the plaintext probe.
        final baseHasPlain = (await _dirNames(client, baseFs)).contains(probe);
        final bool? ok;
        final String? msg;
        if (cryptHasProbe && !baseHasPlain) {
          // Decrypt (crypt shows plaintext) AND encrypt (base scrambled) proven.
          ok = true;
          msg = null;
        } else if (baseHasPlain) {
          // The folder name landed verbatim on the base — encryption isn't
          // taking effect for this remote.
          ok = false;
          msg = 'The probe folder appears unencrypted on the base remote.';
        } else {
          // Probe not visible where expected — inconclusive, not a failure.
          ok = null;
          msg = null;
        }
        state = EncryptRemoteState(
          phase: EncryptPhase.done,
          verifyOk: ok,
          verifyMessage: msg,
        );
      }
    } catch (_) {
      // A primitive was unavailable or the transport failed — created, just
      // unverified. Never surfaced as a wizard error.
      state = const EncryptRemoteState(
        phase: EncryptPhase.done,
        verifyOk: null,
        verifyMessage: null,
      );
    } finally {
      // Best-effort cleanup: remove the probe THROUGH the crypt remote so its
      // encrypted counterpart on the base goes with it. Use operations/rmdir,
      // NOT operations/purge: rmdir removes only an EMPTY dir and refuses a
      // non-empty one, so even in the impossible case of a name collision it can
      // never recursively delete a user's populated directory (the old purge
      // could). Only runs when our own mkdir created the probe; a leftover empty
      // dir is inert if this fails, so we swallow any error.
      if (created) {
        try {
          await client.rpc('operations/rmdir', {
            'fs': cryptFs,
            'remote': probe,
          });
        } catch (_) {
          /* ignore — leftover empty probe dir is harmless */
        }
      }
    }
  }

  /// Names of the entries at the root of [fs] via `operations/list` (light
  /// options — we only compare names). Returned as a set for O(1) probe lookup.
  Future<Set<String>> _dirNames(RcloneClient client, String fs) async {
    final res = await client.rpc('operations/list', {
      'fs': fs,
      'remote': '',
      'opt': {'noModTime': true, 'showHash': false},
    });
    final list = (res['list'] as List?) ?? const [];
    return {
      for (final e in list.cast<Map<String, dynamic>>())
        (e['Name'] ?? '') as String,
    };
  }
}

final encryptRemoteControllerProvider =
    NotifierProvider<EncryptRemoteController, EncryptRemoteState>(
      EncryptRemoteController.new,
    );
