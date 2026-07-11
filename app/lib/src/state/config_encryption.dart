import 'package:flutter/foundation.dart';

/// The three native-rclone config-encryption operations Airclone drives through
/// the `rclone config encryption` CLI subcommands. There is NO RC method for
/// these (verified against `rc/list` on rclone v1.74) and setting
/// `RCLONE_CONFIG_PASS` on a plaintext config does NOT encrypt it on save — so
/// the only mechanism is the binary subcommand, which means this whole feature
/// needs a real rclone binary (desktop + Android; not the pure-FFI/librclone
/// engine, which can still *use* an encrypted config but not change its state).
enum ConfigEncryptionOp {
  /// Plaintext config -> encrypted. `config encryption set` with no existing
  /// password; the new password is read from stdin (twice).
  encrypt,

  /// Change the password of an already-encrypted config. `config encryption set`
  /// with the OLD password in `RCLONE_CONFIG_PASS` and the NEW read from stdin.
  changePassword,

  /// Encrypted config -> plaintext. `config encryption remove` with the current
  /// password in `RCLONE_CONFIG_PASS`.
  decrypt,
}

/// The exact argv + environment + stdin for one config-encryption invocation.
/// Pure data so [buildConfigEncryptionCommand] is unit-tested without spawning
/// anything, mirroring how [configDumpArgs]/[resolveConfigPath] are tested.
@immutable
class ConfigEncryptionCommand {
  const ConfigEncryptionCommand({
    required this.args,
    required this.env,
    required this.stdin,
  });

  /// Argv passed to the rclone binary (WITHOUT the binary itself).
  final List<String> args;

  /// Extra environment for the child. Carries `RCLONE_CONFIG_PASS` (the CURRENT
  /// password) for the change/decrypt ops; empty for a first-time encrypt.
  final Map<String, String> env;

  /// Text written to the child's stdin then closed (the NEW password, twice, for
  /// set; null for remove, which needs no interactive input). rclone reads the
  /// password from stdin when it is a pipe rather than a TTY (verified), so the
  /// secret never appears on the command line or in the process list.
  final String? stdin;
}

/// Builds the argv/env/stdin for a config-encryption [op] — pure and total, so
/// every branch (and every missing-argument guard) is unit-tested without a
/// process. [configPath] is the resolved config-file path (null/empty ⇒ let
/// rclone use its default location, exactly as the engine spawns).
///
/// Throws [ArgumentError] when a required password is missing or empty, so a
/// half-specified operation can never be dispatched (an empty new password would
/// otherwise "encrypt" with no protection; a missing current password would hang
/// rclone waiting on a prompt).
ConfigEncryptionCommand buildConfigEncryptionCommand({
  required ConfigEncryptionOp op,
  String? configPath,
  String? currentPassword,
  String? newPassword,
}) {
  final configArgs = (configPath != null && configPath.isNotEmpty)
      ? <String>['--config', configPath]
      : const <String>[];

  void requireNew() {
    if (newPassword == null || newPassword.isEmpty) {
      throw ArgumentError.value(
        newPassword,
        'newPassword',
        'a non-empty new password is required for ${op.name}',
      );
    }
  }

  void requireCurrent() {
    if (currentPassword == null || currentPassword.isEmpty) {
      throw ArgumentError.value(
        currentPassword,
        'currentPassword',
        'the current password is required for ${op.name}',
      );
    }
  }

  switch (op) {
    case ConfigEncryptionOp.encrypt:
      requireNew();
      return ConfigEncryptionCommand(
        args: ['config', 'encryption', 'set', ...configArgs],
        env: const {},
        // `password:` then `Confirm NEW configuration password:` — the same
        // value twice.
        stdin: '$newPassword\n$newPassword\n',
      );
    case ConfigEncryptionOp.changePassword:
      requireCurrent();
      requireNew();
      return ConfigEncryptionCommand(
        args: ['config', 'encryption', 'set', ...configArgs],
        // The OLD password decrypts the current config; the NEW is read from
        // stdin. (rclone: "otherwise it changes the existing config password".)
        env: {'RCLONE_CONFIG_PASS': currentPassword!},
        stdin: '$newPassword\n$newPassword\n',
      );
    case ConfigEncryptionOp.decrypt:
      requireCurrent();
      return ConfigEncryptionCommand(
        args: ['config', 'encryption', 'remove', ...configArgs],
        env: {'RCLONE_CONFIG_PASS': currentPassword!},
        stdin: null,
      );
  }
}
