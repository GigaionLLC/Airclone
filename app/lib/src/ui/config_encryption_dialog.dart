import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cache_crypto.dart';
import '../state/config_encryption.dart';
import '../state/config_transfer_controller.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// The Settings → Config controls for rclone's OWN config-file encryption
/// (distinct from the "Airclone encrypted" export ENVELOPE, which is a separate
/// AES-256-GCM backup format). Shows "Encrypt this config…" when the active
/// config is plaintext, or "Change password…" / "Remove encryption…" when it is
/// already encrypted. Desktop + Android only — the underlying `rclone config
/// encryption` CLI needs a real binary (the in-process engine has none).
///
/// "Encrypted?" is read from the live engine state exactly as the status row
/// above it: the held session password ([cachePassphraseProvider]) is non-null
/// only for an unlocked encrypted config.
class ConfigEncryptionControls extends ConsumerWidget {
  const ConfigEncryptionControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final encrypted = ref.watch(cachePassphraseProvider) != null;

    return Padding(
      padding: const EdgeInsets.only(top: Space.x3),
      child: Wrap(
        spacing: Space.x2,
        runSpacing: Space.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!encrypted)
            OutlinedButton.icon(
              onPressed: () => showEncryptConfigDialog(context),
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Encrypt this config…'),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: () => showChangeConfigPasswordDialog(context),
              icon: const Icon(Icons.password_outlined, size: 16),
              label: const Text('Change password…'),
            ),
            TextButton.icon(
              onPressed: () => showDecryptConfigDialog(context),
              icon: Icon(Icons.lock_open_outlined, size: 16, color: c.error),
              label: Text(
                'Remove encryption…',
                style: TextStyle(color: c.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> showEncryptConfigDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _PassphraseDialog(
    op: ConfigEncryptionOp.encrypt,
    title: 'Encrypt this config',
    intro:
        'rclone will encrypt your rclone.conf with a password. You will need '
        'this password to unlock it every time Airclone starts (you can let '
        'Airclone remember it in your OS keychain). This briefly restarts the '
        'engine, so finish any running transfers first.',
    actionLabel: 'Encrypt',
  ),
);

Future<void> showChangeConfigPasswordDialog(
  BuildContext context,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _PassphraseDialog(
    op: ConfigEncryptionOp.changePassword,
    title: 'Change config password',
    intro:
        'Set a new password for your encrypted rclone.conf. The current '
        'password (already unlocked this session) is used to re-encrypt it. '
        'The previous config is backed up first. This briefly restarts the '
        'engine, so finish any running transfers first.',
    actionLabel: 'Change password',
  ),
);

Future<void> showDecryptConfigDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _DecryptDialog(),
);

/// Shared new-passphrase + confirm dialog for encrypt / change-password. Both
/// only differ in copy and the [ConfigEncryptionOp] dispatched.
class _PassphraseDialog extends ConsumerStatefulWidget {
  const _PassphraseDialog({
    required this.op,
    required this.title,
    required this.intro,
    required this.actionLabel,
  });

  final ConfigEncryptionOp op;
  final String title;
  final String intro;
  final String actionLabel;

  @override
  ConsumerState<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends ConsumerState<_PassphraseDialog> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _pass.text;
    if (pass.isEmpty) {
      setState(() => _error = 'Enter a password.');
      return;
    }
    if (pass != _confirm.text) {
      setState(() => _error = "The passwords don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(configTransferControllerProvider)
          .applyConfigEncryption(widget.op, newPassword: pass);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            widget.op == ConfigEncryptionOp.encrypt
                ? 'Config encrypted.'
                : 'Config password changed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: DialogBody(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.intro,
                style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: Space.x4),
              _passwordField(c, _pass, 'New password', autofocus: true),
              const SizedBox(height: Space.x2),
              _passwordField(c, _confirm, 'Confirm password'),
              const SizedBox(height: Space.x2),
              Text(
                "There's no recovery — if you lose this password the config can't "
                'be opened. Store it in a password manager.',
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.x2),
                Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.actionLabel),
          ),
        ],
      ),
    );
  }
}

/// Remove-encryption dialog. Decryption writes every remote secret back to disk
/// in PLAINTEXT, so it carries a hard warning and a typed confirmation rather
/// than a single tap.
class _DecryptDialog extends ConsumerStatefulWidget {
  const _DecryptDialog();

  @override
  ConsumerState<_DecryptDialog> createState() => _DecryptDialogState();
}

class _DecryptDialogState extends ConsumerState<_DecryptDialog> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _phrase = 'DECRYPT';

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_confirm.text.trim().toUpperCase() != _phrase) {
      setState(() => _error = 'Type $_phrase to confirm.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(configTransferControllerProvider)
          .applyConfigEncryption(ConfigEncryptionOp.decrypt);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Config encryption removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        title: Text(
          'Remove config encryption?',
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: DialogBody(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This writes every remote secret back to disk in PLAINTEXT — '
                'anyone who can read the file can read your credentials. The '
                'current encrypted config is backed up first.',
                style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: Space.x4),
              TextField(
                controller: _confirm,
                autofocus: true,
                style: TextStyle(color: c.text),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Type $_phrase to confirm',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.x2),
                Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.error),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Remove encryption'),
          ),
        ],
      ),
    );
  }
}

Widget _passwordField(
  AircloneColors c,
  TextEditingController ctrl,
  String label, {
  bool autofocus = false,
}) => TextField(
  controller: ctrl,
  obscureText: true,
  autofocus: autofocus,
  style: TextStyle(color: c.text),
  decoration: InputDecoration(
    isDense: true,
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md)),
  ),
);

String _messageFor(Object e) {
  if (e is ConfigTransferError) return e.message;
  return '$e';
}
