/// The setup and restore dialogs for the outside-the-sandbox config backup
/// (state/external_config_backup.dart).
///
/// The flow encodes the security decision rather than leaving it to a settings
/// toggle: turning the backup on ASKS FOR A PASSPHRASE. Continuing without one
/// is possible — some people want a plain `rclone.conf` they can copy to a
/// desktop — but only through a second, explicit confirmation that says what it
/// means in plain words. There is no way to end up with an unencrypted copy of
/// your cloud credentials in shared storage by accident.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/external_config_backup.dart';
import 'config_import_dialog.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// Runs the enable flow. Returns true when a backup was turned on.
Future<bool> showExternalBackupSetupDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => const _SetupDialog(),
    ) ??
    false;

class _SetupDialog extends ConsumerStatefulWidget {
  const _SetupDialog();

  @override
  ConsumerState<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends ConsumerState<_SetupDialog> {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();

  /// True once the user has asked to proceed WITHOUT a passphrase; the view
  /// switches to the danger confirmation.
  bool _unprotectedStep = false;

  /// The danger confirmation's acknowledgement tick. Deliberately a checkbox
  /// rather than a second button: it cannot be dismissed by muscle memory.
  bool _acknowledged = false;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _enableEncrypted() async {
    final pass = _passphrase.text;
    if (pass.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (pass != _confirm.text) {
      setState(() => _error = "The two passphrases don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(externalBackupProvider.notifier).enableEncrypted(pass);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ExternalBackupError ? e.message : '$e';
      });
    }
  }

  Future<void> _enablePlaintext() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(externalBackupProvider.notifier).enablePlaintext();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ExternalBackupError ? e.message : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: DialogBody(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: SingleChildScrollView(
            child: _unprotectedStep ? _dangerView(c) : _passphraseView(c),
          ),
        ),
      ),
    );
  }

  Widget _passphraseView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.shield_outlined, 'Survive uninstall', c.primary),
      const SizedBox(height: Space.x2),
      Text(
        'Airclone will keep an encrypted copy of your remotes in a folder '
        'outside the app, so reinstalling — or setting up a new phone — gets '
        'them back. Choose a passphrase to protect it.',
        style: TextStyle(color: c.textFaint, fontSize: 12),
      ),
      const SizedBox(height: Space.x3),
      TextField(
        controller: _passphrase,
        obscureText: true,
        autofocus: true,
        decoration: _field(c, 'Passphrase'),
        style: TextStyle(color: c.text, fontSize: 13),
      ),
      const SizedBox(height: Space.x2),
      TextField(
        controller: _confirm,
        obscureText: true,
        onSubmitted: (_) => _enableEncrypted(),
        decoration: _field(c, 'Confirm passphrase'),
        style: TextStyle(color: c.text, fontSize: 13),
      ),
      const SizedBox(height: Space.x2),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: c.textFaint),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              "Write this down. It is not stored anywhere you can reach after "
              'an uninstall — without it the backup cannot be opened, by you or '
              'anyone else.',
              style: TextStyle(color: c.textFaint, fontSize: 11),
            ),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: Space.x2),
        Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
      ],
      const SizedBox(height: Space.x4),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: Space.x2,
        runSpacing: Space.x2,
        children: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: c.textMuted)),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _unprotectedStep = true;
                    _error = null;
                  }),
            child: Text(
              'Continue without one…',
              style: TextStyle(color: c.textMuted),
            ),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _enableEncrypted,
            icon: _busy
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline, size: 16),
            label: const Text('Turn on'),
          ),
        ],
      ),
    ],
  );

  Widget _dangerView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        c,
        Icons.warning_amber_rounded,
        'Store your credentials unprotected?',
        c.error,
      ),
      const SizedBox(height: Space.x3),
      Container(
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(
          color: c.errorBg,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Without a passphrase, Airclone writes a plain rclone.conf to '
              'shared storage. That file holds the keys to every cloud account '
              'you have connected, and:',
              style: TextStyle(color: c.text, fontSize: 12),
            ),
            const SizedBox(height: Space.x2),
            _bullet(c, 'any app on this phone with file access can read it;'),
            _bullet(
              c,
              'it is copied by device backups, phone-to-phone transfers, and '
              'anything that syncs your files to a computer or the cloud;',
            ),
            _bullet(
              c,
              'anyone who picks up your unlocked phone can open it in a file '
              'manager.',
            ),
            const SizedBox(height: Space.x2),
            Text(
              'A passphrase removes all three. Use one unless you specifically '
              'need a plain file.',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.x3),
      InkWell(
        onTap: () => setState(() => _acknowledged = !_acknowledged),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _acknowledged,
              onChanged: (v) => setState(() => _acknowledged = v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'I understand my cloud credentials will be stored '
                  'unencrypted on this device.',
                  style: TextStyle(color: c.text, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: Space.x2),
        Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
      ],
      const SizedBox(height: Space.x4),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: Space.x2,
        runSpacing: Space.x2,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _unprotectedStep = false;
                    _acknowledged = false;
                    _error = null;
                  }),
            child: Text(
              'Use a passphrase instead',
              style: TextStyle(color: c.primary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.error,
              foregroundColor: c.onPrimary,
            ),
            onPressed: (_busy || !_acknowledged) ? null : _enablePlaintext,
            child: const Text('Turn on unprotected'),
          ),
        ],
      ),
    ],
  );

  Widget _bullet(AircloneColors c, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ', style: TextStyle(color: c.error, fontSize: 12)),
        Expanded(
          child: Text(text, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ),
      ],
    ),
  );

  InputDecoration _field(AircloneColors c, String hint) => InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md)),
  );

  Widget _title(AircloneColors c, IconData icon, String text, Color tint) =>
      Row(
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

/// The "we found your remotes" offer shown once on a fresh install when a
/// backup from a previous install is sitting in shared storage.
///
/// This is what makes the feature worth having: a user who reinstalls should get
/// their remotes back without having to remember that a setting existed. Accepting
/// hands the bytes to the normal import wizard, so the passphrase prompt and the
/// mandatory preview are the same reviewed flow as any other import.
Future<void> showRestoreBackupOffer(
  BuildContext context,
  FoundBackup backup,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final c = AircloneTheme.of(dialogContext);
      return AlertDialog(
        backgroundColor: c.surfaceRaised,
        title: Row(
          children: [
            Icon(Icons.restore, size: 20, color: c.primary),
            const SizedBox(width: Space.x2),
            const Expanded(child: Text('Restore your remotes?')),
          ],
        ),
        content: DialogBody(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Airclone found a backup left by a previous install on this '
                'device. You can bring those remotes back — you will review '
                'them before anything is written.',
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  Icon(
                    backup.encrypted ? Icons.lock_outline : Icons.lock_open,
                    size: 14,
                    color: backup.encrypted ? c.textFaint : c.warning,
                  ),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      backup.encrypted
                          ? 'Encrypted — you will be asked for its passphrase.'
                          : 'Not encrypted.',
                      style: TextStyle(color: c.textFaint, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                backup.path,
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Not now', style: TextStyle(color: c.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore…'),
          ),
        ],
      );
    },
  );
  if (accepted != true || !context.mounted) return;
  await showConfigImportDialog(
    context,
    initialBytes: backup.bytes,
    initialName: backup.name,
  );
}
