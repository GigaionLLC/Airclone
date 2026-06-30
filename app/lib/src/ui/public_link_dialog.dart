import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rclone/rclone_client.dart';
import 'theme/tokens.dart';

const _expiryPresets = <(String, String)>[
  ('off', 'No expiry'),
  ('1h', '1 hour'),
  ('24h', '1 day'),
  ('7d', '1 week'),
  ('30d', '1 month'),
];

/// Shows a public-link dialog for [remote] on [fs]: pick an expiry, create the
/// link, copy it, or revoke it. Expiry/revoke support varies by backend — the
/// engine error is surfaced if unsupported. [name] is for display only.
Future<void> showPublicLinkDialog(
  BuildContext context,
  RcloneClient client, {
  required String fs,
  required String remote,
  required String name,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _PublicLinkDialog(client: client, fs: fs, remote: remote, name: name),
);

class _PublicLinkDialog extends StatefulWidget {
  const _PublicLinkDialog({
    required this.client,
    required this.fs,
    required this.remote,
    required this.name,
  });
  final RcloneClient client;
  final String fs;
  final String remote;
  final String name;

  @override
  State<_PublicLinkDialog> createState() => _PublicLinkDialogState();
}

class _PublicLinkDialogState extends State<_PublicLinkDialog> {
  String _expire = 'off';
  String? _url;
  bool _busy = false;
  String? _error;
  String? _status;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final res = await widget.client.rpc('operations/publiclink', {
        'fs': widget.fs,
        'remote': widget.remote,
        if (_expire != 'off') 'expire': _expire,
      });
      if (!mounted) return;
      final url = (res['url'] ?? '').toString();
      setState(() {
        _busy = false;
        if (url.isEmpty) {
          _error = 'No link returned (this remote may not support it).';
        } else {
          _url = url;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is RcloneException ? e.message : '$e';
      });
    }
  }

  Future<void> _revoke() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.rpc('operations/publiclink', {
        'fs': widget.fs,
        'remote': widget.remote,
        'unlink': true,
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _url = null;
        _status = 'Link revoked.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is RcloneException ? e.message : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final url = _url;
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: const Text('Public link'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.name,
              style: TextStyle(color: c.textMuted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Space.x3),
            if (url == null) ...[
              Text(
                'Expires',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _expire,
                isExpanded: true,
                dropdownColor: c.surfaceRaised,
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                items: [
                  for (final (v, label) in _expiryPresets)
                    DropdownMenuItem(value: v, child: Text(label)),
                ],
                onChanged: (v) => setState(() => _expire = v ?? 'off'),
              ),
              if (_expire != 'off') ...[
                const SizedBox(height: 4),
                Text(
                  'Some backends ignore expiry — treat it as best-effort.',
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                ),
              ],
            ] else
              Container(
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: SelectableText(
                  url,
                  style: TextStyle(color: c.text, fontSize: 12),
                ),
              ),
            if (_status != null) ...[
              const SizedBox(height: Space.x2),
              Text(_status!, style: TextStyle(color: c.success, fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.x2),
              Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: c.textMuted)),
        ),
        if (url != null) ...[
          TextButton(
            onPressed: _busy ? null : _revoke,
            child: _busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.error,
                    ),
                  )
                : Text('Revoke', style: TextStyle(color: c.error)),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              setState(() => _status = 'Link copied.');
            },
            icon: const Icon(Icons.copy, size: 15),
            label: const Text('Copy'),
          ),
        ] else
          FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create link'),
          ),
      ],
    );
  }
}
