import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/serve_server.dart';
import '../rclone/rclone_client.dart';
import '../state/remotes_provider.dart';
import '../state/serve_controller.dart';
import '../state/serve_policy.dart';
import 'theme/tokens.dart';

const _defaultPorts = {
  'http': 8080,
  'webdav': 8080,
  'ftp': 2121,
  'sftp': 2022,
  'dlna': 8200,
};

/// Opens the Serve / Share manager (start a server + list/stop running ones).
Future<void> showServeDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ServeDialog());

class _ServeDialog extends ConsumerStatefulWidget {
  const _ServeDialog();
  @override
  ConsumerState<_ServeDialog> createState() => _ServeDialogState();
}

class _ServeDialogState extends ConsumerState<_ServeDialog> {
  final _subdir = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _remote;
  String _type = 'http';
  bool _lan = false;
  int _port = 8080;
  bool _readOnly = false;
  bool _dlnaAck = false;
  String? _error;
  bool _starting = false;

  @override
  void dispose() {
    _subdir.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _authCapable => serveAuthCapable.contains(_type);

  bool get _canStart {
    if (_remote == null || _starting) return false;
    if (_lan && _authCapable && (_user.text.isEmpty || _pass.text.isEmpty)) {
      return false;
    }
    if (_lan && _type == 'dlna' && !_dlnaAck) return false;
    return true;
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    final sub = _subdir.text.trim();
    final fs = sub.isEmpty ? '$_remote:' : '$_remote:$sub';
    try {
      await ref
          .read(serveControllerProvider.notifier)
          .start(
            type: _type,
            fs: fs,
            lan: _lan,
            port: _port,
            user: _user.text,
            pass: _pass.text,
            readOnly: _readOnly,
            dlnaAcknowledged: _dlnaAck,
          );
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = e is RcloneException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final enabled = ref.watch(serveEnabledProvider);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: 560,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x5,
                Space.x4,
                Space.x3,
                Space.x3,
              ),
              child: Row(
                children: [
                  Icon(Icons.cast_connected, size: 20, color: c.primary),
                  const SizedBox(width: Space.x2),
                  Text(
                    'Serve / Share on LAN',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    color: c.textMuted,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Expanded(
              child: enabled
                  ? ListView(
                      padding: const EdgeInsets.all(Space.x5),
                      children: [
                        ..._startForm(c),
                        const SizedBox(height: Space.x5),
                        ..._running(c),
                      ],
                    )
                  : _disabledByPolicy(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disabledByPolicy(AircloneColors c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.x6),
      child: Text(
        'Serving is disabled by policy.',
        style: TextStyle(color: c.textMuted, fontSize: 13),
      ),
    ),
  );

  List<Widget> _startForm(AircloneColors c) {
    final remotes = ref.watch(remotesProvider).valueOrNull ?? const [];
    final types = ref.watch(serveTypesProvider).valueOrNull ?? const ['http'];
    return [
      Text(
        'Start a server',
        style: TextStyle(
          color: c.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: Space.x3),
      Row(
        children: [
          Expanded(
            child: _field(
              c,
              'Remote',
              DropdownButtonFormField<String>(
                initialValue: _remote,
                isExpanded: true,
                dropdownColor: c.surfaceRaised,
                decoration: _dec(c, 'Pick a remote'),
                items: [
                  for (final r in remotes)
                    DropdownMenuItem(value: r.name, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() => _remote = v),
              ),
            ),
          ),
          const SizedBox(width: Space.x3),
          SizedBox(
            width: 150,
            child: _field(
              c,
              'Subfolder',
              TextField(
                controller: _subdir,
                decoration: _dec(c, 'optional'),
                style: TextStyle(color: c.text, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: _field(
              c,
              'Protocol',
              DropdownButtonFormField<String>(
                initialValue: types.contains(_type) ? _type : types.first,
                isExpanded: true,
                dropdownColor: c.surfaceRaised,
                decoration: _dec(c, ''),
                items: [
                  for (final t in types)
                    DropdownMenuItem(value: t, child: Text(t.toUpperCase())),
                ],
                onChanged: (v) => setState(() {
                  _type = v ?? _type;
                  _port = _defaultPorts[_type] ?? _port;
                  _dlnaAck = false;
                }),
              ),
            ),
          ),
          const SizedBox(width: Space.x3),
          SizedBox(
            width: 110,
            child: _field(
              c,
              'Port',
              TextField(
                controller: TextEditingController(text: '$_port'),
                keyboardType: TextInputType.number,
                decoration: _dec(c, ''),
                style: TextStyle(color: c.text, fontSize: 13),
                onChanged: (v) => _port = int.tryParse(v) ?? _port,
              ),
            ),
          ),
        ],
      ),
      _field(
        c,
        'Reachable from',
        Row(
          children: [
            Expanded(
              child: RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: false,
                // ignore: deprecated_member_use
                groupValue: _lan,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _lan = false),
                title: const Text(
                  'This device only',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: true,
                // ignore: deprecated_member_use
                groupValue: _lan,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _lan = true),
                title: const Text(
                  'My local network',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
      if (_lan && _type != 'dlna')
        Row(
          children: [
            Expanded(
              child: _field(
                c,
                'Username',
                TextField(
                  controller: _user,
                  decoration: _dec(c, 'required for network'),
                  style: TextStyle(color: c.text, fontSize: 13),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: _field(
                c,
                'Password',
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: _dec(c, 'required for network'),
                  style: TextStyle(color: c.text, fontSize: 13),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ],
        ),
      Row(
        children: [
          Switch(
            value: _readOnly,
            onChanged: (v) => setState(() => _readOnly = v),
          ),
          Text('Read-only', style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      ),
      if (_lan) _warningBanner(c),
      if (_lan && _type == 'dlna')
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _dlnaAck,
          onChanged: (v) => setState(() => _dlnaAck = v ?? false),
          title: Text(
            'I understand DLNA has no password — anyone on my network can stream this.',
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
        ),
      if (_error != null) ...[
        const SizedBox(height: Space.x2),
        Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
      ],
      const SizedBox(height: Space.x3),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: _canStart ? _start : null,
          icon: _starting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 16),
          label: const Text('Start server'),
        ),
      ),
    ];
  }

  Widget _warningBanner(AircloneColors c) => Container(
    margin: const EdgeInsets.only(top: Space.x2),
    padding: const EdgeInsets.all(Space.x3),
    decoration: BoxDecoration(
      color: c.warningBg,
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Row(
      children: [
        Icon(Icons.wifi_tethering, size: 16, color: c.warning),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(
            _type == 'dlna'
                ? 'Anyone on your local network can browse and stream this — DLNA has no password.'
                : 'This will be reachable by other devices on your network. It stops when Airclone\'s engine restarts or the app quits.',
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
        ),
      ],
    ),
  );

  List<Widget> _running(AircloneColors c) {
    final servers = ref.watch(serveControllerProvider);
    final lanIp = ref.watch(lanIpProvider).valueOrNull;
    return [
      Row(
        children: [
          Text(
            'Running servers',
            style: TextStyle(
              color: c.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (servers.isNotEmpty)
            TextButton(
              onPressed: () =>
                  ref.read(serveControllerProvider.notifier).panicStopAll(),
              child: Text('Stop all', style: TextStyle(color: c.error)),
            ),
        ],
      ),
      const SizedBox(height: Space.x2),
      if (servers.isEmpty)
        Text(
          'No servers running.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        )
      else
        for (final s in servers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Row(
              children: [
                Icon(
                  s.isLoopback ? Icons.lock_outline : Icons.public,
                  size: 16,
                  color: s.isLoopback ? c.textMuted : c.warning,
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s.type.toUpperCase()} · ${s.fs}',
                        style: TextStyle(color: c.text, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${s.displayUrl(lanIp: lanIp)}  ·  ${s.isLoopback ? 'this device only' : 'reachable on your network'}',
                        style: TextStyle(color: c.textFaint, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy URL',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: s.displayUrl(lanIp: lanIp)),
                  ),
                  icon: const Icon(Icons.copy, size: 15),
                  color: c.textMuted,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Stop',
                  onPressed: () =>
                      ref.read(serveControllerProvider.notifier).stop(s.id),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  color: c.error,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
    ];
  }

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
    hintStyle: TextStyle(color: c.textFaint, fontSize: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md)),
  );
}
