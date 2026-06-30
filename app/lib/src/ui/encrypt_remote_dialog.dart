import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/encrypt_remote_controller.dart';
import '../state/remotes_provider.dart';
import 'theme/tokens.dart';

/// Opens the "Encrypt a remote" wizard. [baseRemoteName] pre-selects the remote
/// to wrap (e.g. when launched from a remote's menu).
Future<void> showEncryptRemoteDialog(
  BuildContext context, {
  String? baseRemoteName,
}) => showDialog<void>(
  context: context,
  builder: (_) => _EncryptRemoteDialog(baseRemoteName: baseRemoteName),
);

class _EncryptRemoteDialog extends ConsumerStatefulWidget {
  const _EncryptRemoteDialog({this.baseRemoteName});
  final String? baseRemoteName;

  @override
  ConsumerState<_EncryptRemoteDialog> createState() =>
      _EncryptRemoteDialogState();
}

class _EncryptRemoteDialogState extends ConsumerState<_EncryptRemoteDialog> {
  // Secrets live ONLY in these controllers (disposed on close) — never copied
  // into provider state.
  final _name = TextEditingController();
  final _subdir = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _salt = TextEditingController();

  String? _base;
  String _filenameEnc = 'standard';
  bool _dirEnc = true;
  bool _advanced = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _base = widget.baseRemoteName;
    ref.read(encryptRemoteControllerProvider.notifier).reset();
  }

  @override
  void dispose() {
    _name.dispose();
    _subdir.dispose();
    _pass.dispose();
    _confirm.dispose();
    _salt.dispose();
    super.dispose();
  }

  void _submit(List<String> existingNames) {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _formError = 'Enter a name.');
    if (existingNames.contains(name)) {
      return setState(
        () => _formError = 'A remote named "$name" already exists.',
      );
    }
    if (_base == null) {
      return setState(() => _formError = 'Pick a remote to encrypt.');
    }
    if (_pass.text.isEmpty) {
      return setState(() => _formError = 'Enter a password.');
    }
    if (_pass.text != _confirm.text) {
      return setState(() => _formError = 'Passwords don\'t match.');
    }
    setState(() => _formError = null);
    final sub = _subdir.text.trim();
    final baseFs = sub.isEmpty ? '$_base:' : '$_base:$sub';
    ref
        .read(encryptRemoteControllerProvider.notifier)
        .submit(
          name: name,
          baseFs: baseFs,
          filenameEncryption: _filenameEnc,
          dirNameEncryption: _dirEnc,
          password: _pass.text,
          password2: _salt.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final st = ref.watch(encryptRemoteControllerProvider);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: switch (st.phase) {
            EncryptPhase.creating => _busy(c, 'Creating encrypted remote…'),
            EncryptPhase.verifying => _busy(c, 'Verifying…'),
            EncryptPhase.done => _done(c, st),
            EncryptPhase.error => _error(c, st.error),
            EncryptPhase.form => _form(c),
          },
        ),
      ),
    );
  }

  Widget _busy(AircloneColors c, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: Space.x4),
      const CircularProgressIndicator(strokeWidth: 2),
      const SizedBox(height: Space.x3),
      Text(label, style: TextStyle(color: c.textMuted, fontSize: 13)),
      const SizedBox(height: Space.x4),
    ],
  );

  Widget _form(AircloneColors c) {
    final remotes = ref.watch(remotesProvider).valueOrNull ?? const [];
    final bases = [
      for (final r in remotes)
        if (!r.isLocal && r.type != 'crypt') r.name,
    ];
    final names = [for (final r in remotes) r.name];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: c.primary),
            const SizedBox(width: Space.x2),
            Text(
              'Encrypt a remote',
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x2),
        Text(
          'Wrap an existing remote so files + names are encrypted before upload.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
        const SizedBox(height: Space.x4),
        _field(
          c,
          'New remote name',
          TextField(
            controller: _name,
            decoration: _dec(c, 'e.g. drive-secret'),
            style: TextStyle(color: c.text, fontSize: 13),
          ),
        ),
        _field(
          c,
          'Remote to encrypt',
          DropdownButtonFormField<String>(
            initialValue: _base,
            isExpanded: true,
            dropdownColor: c.surfaceRaised,
            decoration: _dec(c, 'Pick a remote'),
            items: [
              for (final b in bases)
                DropdownMenuItem(
                  value: b,
                  child: Text(b, style: TextStyle(color: c.text, fontSize: 13)),
                ),
            ],
            onChanged: (v) => setState(() => _base = v),
          ),
        ),
        _field(
          c,
          'Subfolder (optional)',
          TextField(
            controller: _subdir,
            decoration: _dec(c, 'e.g. Encrypted'),
            style: TextStyle(color: c.text, fontSize: 13),
          ),
        ),
        _field(
          c,
          'Encryption password',
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: _dec(c, ''),
            style: TextStyle(color: c.text, fontSize: 13),
          ),
        ),
        _field(
          c,
          'Confirm password',
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: _dec(c, ''),
            style: TextStyle(color: c.text, fontSize: 13),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _field(
                c,
                'Filenames',
                DropdownButtonFormField<String>(
                  initialValue: _filenameEnc,
                  isExpanded: true,
                  dropdownColor: c.surfaceRaised,
                  decoration: _dec(c, ''),
                  items: const [
                    DropdownMenuItem(
                      value: 'standard',
                      child: Text('Encrypt (standard)'),
                    ),
                    DropdownMenuItem(
                      value: 'obfuscate',
                      child: Text('Obfuscate'),
                    ),
                    DropdownMenuItem(
                      value: 'off',
                      child: Text('Leave readable'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _filenameEnc = v ?? _filenameEnc),
                ),
              ),
            ),
            const SizedBox(width: Space.x3),
            Padding(
              padding: const EdgeInsets.only(top: Space.x3),
              child: Row(
                children: [
                  Switch(
                    value: _dirEnc,
                    onChanged: (v) => setState(() => _dirEnc = v),
                  ),
                  Text(
                    'Encrypt\nfolder names',
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x2),
        InkWell(
          onTap: () => setState(() => _advanced = !_advanced),
          child: Row(
            children: [
              Icon(
                _advanced ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: c.textMuted,
              ),
              Text(
                'Advanced',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (_advanced)
          _field(
            c,
            'Salt / password2 (optional, recommended)',
            TextField(
              controller: _salt,
              obscureText: true,
              decoration: _dec(c, 'Different from the password'),
              style: TextStyle(color: c.text, fontSize: 13),
            ),
          ),
        if (_formError != null) ...[
          const SizedBox(height: Space.x2),
          Text(_formError!, style: TextStyle(color: c.error, fontSize: 12)),
        ],
        const SizedBox(height: Space.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: c.textMuted)),
            ),
            const SizedBox(width: Space.x2),
            FilledButton.icon(
              onPressed: () => _submit(names),
              icon: const Icon(Icons.lock, size: 16),
              label: const Text('Encrypt remote'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _done(AircloneColors c, EncryptRemoteState st) {
    final (icon, tint, title) = switch (st.verifyOk) {
      true => (
        Icons.check_circle_outline,
        c.success,
        'Encrypted remote created',
      ),
      false => (
        Icons.error_outline,
        c.warning,
        'Created, but verification reported differences',
      ),
      null => (
        Icons.check_circle_outline,
        c.success,
        'Encrypted remote created',
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        // Config-encryption nudge — shown regardless of verify outcome, since
        // rclone.conf only lightly obscures the password.
        Container(
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(
            color: c.warningBg,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, size: 16, color: c.warning),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  'rclone only lightly obscures this password in its config — '
                  'anyone with the file can recover it. To truly protect it, '
                  'enable rclone config encryption (you\'ll then unlock Airclone '
                  'with that password at startup). Airclone never saves your '
                  'encryption password.',
                  style: TextStyle(color: c.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        if (st.verifyOk == false && st.verifyMessage != null) ...[
          const SizedBox(height: Space.x3),
          Text(
            st.verifyMessage!,
            style: TextStyle(color: c.textFaint, fontSize: 11),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: Space.x4),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _error(AircloneColors c, String? error) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: c.error),
          const SizedBox(width: Space.x2),
          Text(
            'Couldn\'t create the remote',
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.x3),
      Text(
        error ?? 'Unknown error',
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      const SizedBox(height: Space.x4),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: c.textMuted)),
          ),
          const SizedBox(width: Space.x2),
          FilledButton(
            onPressed: () =>
                ref.read(encryptRemoteControllerProvider.notifier).reset(),
            child: const Text('Back'),
          ),
        ],
      ),
    ],
  );

  Widget _field(AircloneColors c, String label, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    ),
  );

  InputDecoration _dec(AircloneColors c, String hint) => InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md)),
  );
}
