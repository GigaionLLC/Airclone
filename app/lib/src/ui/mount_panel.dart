import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/mount_options.dart';
import '../rclone/rclone_client.dart';
import '../state/mount_controller.dart';
import '../state/mount_defaults.dart';
import '../state/mount_policy.dart';
import '../state/remotes_provider.dart';
import 'dialog_body.dart';
import 'disclosure.dart';
import 'mount_options_editor.dart';
import 'theme/tokens.dart';

/// Opens the Mount manager (mount remotes as drives + list/unmount running ones).
Future<void> showMountDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _MountDialog());

class _MountDialog extends ConsumerStatefulWidget {
  const _MountDialog();
  @override
  ConsumerState<_MountDialog> createState() => _MountDialogState();
}

class _MountDialogState extends ConsumerState<_MountDialog> {
  final _subdir = TextEditingController();
  String? _remote;
  String _drive = '*'; // auto
  String? _error;
  bool _starting = false;

  /// This mount's options, seeded from the saved defaults on first build and
  /// edited in place afterwards. Deliberately NOT written back: a tweak for one
  /// mount must not silently redefine what every later mount gets. The header
  /// says when the two differ, and offers a reset.
  MountOptions? _options;
  bool _showOptions = false;

  /// Inline outcome of the last cache-refresh click (a SnackBar would render
  /// behind this dialog's modal barrier and be easy to miss).
  String? _refreshMsg;

  @override
  void dispose() {
    _subdir.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_remote == null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    final sub = _subdir.text.trim();
    final fs = sub.isEmpty ? '$_remote:' : '$_remote:$sub';
    try {
      await ref
          .read(mountControllerProvider.notifier)
          .mount(fs: fs, mountPoint: _drive, options: _effectiveOptions);
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
    final enabled = ref.watch(mountEnabledProvider);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: DialogBody(
        width: 540,
        height: 560,
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
                  Icon(Icons.usb, size: 20, color: c.primary),
                  const SizedBox(width: Space.x2),
                  Text(
                    'Mount as a drive',
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
                        ..._form(c),
                        const SizedBox(height: Space.x5),
                        ..._running(c),
                      ],
                    )
                  : Center(
                      child: Text(
                        'Mounting is disabled by policy.',
                        style: TextStyle(color: c.textMuted, fontSize: 13),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _form(AircloneColors c) {
    final remotes = ref.watch(remotesProvider).valueOrNull ?? const [];
    final types = ref.watch(mountTypesProvider).valueOrNull;
    final winfspMissing = types != null && types.isEmpty;
    return [
      if (winfspMissing) _winfspBanner(c),
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
              'Drive',
              DropdownButtonFormField<String>(
                initialValue: _drive,
                isExpanded: true,
                dropdownColor: c.surfaceRaised,
                decoration: _dec(c, ''),
                items: [
                  const DropdownMenuItem(
                    value: '*',
                    child: Text('Auto (next free letter)'),
                  ),
                  for (final l in 'DEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
                    DropdownMenuItem(value: '$l:', child: Text('$l:')),
                ],
                onChanged: (v) => setState(() => _drive = v ?? '*'),
              ),
            ),
          ),
        ],
      ),
      _optionsDisclosure(c),
      if (_error != null) ...[
        const SizedBox(height: Space.x2),
        Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
      ],
      const SizedBox(height: Space.x3),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: (_remote == null || _starting) ? null : _start,
          icon: _starting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 16),
          label: const Text('Mount'),
        ),
      ),
    ];
  }

  /// The options this mount will actually start with: the saved defaults until
  /// the user touches something in the disclosure.
  MountOptions get _effectiveOptions =>
      _options ?? ref.read(mountDefaultsProvider);

  /// The tuning, folded away behind a line that doubles as its own summary.
  ///
  /// A bare "Advanced" header would make a user open the section just to learn
  /// what they are about to get. Showing the state on the collapsed row means
  /// the common case - glance, mount - never expands anything, and the "(N
  /// changed)" suffix is what stops the two places these options live (here and
  /// Settings) from becoming confusing: the dialog always says whether you are
  /// looking at your defaults or at a deviation from them.
  Widget _optionsDisclosure(AircloneColors c) {
    final defaults = ref.watch(mountDefaultsProvider);
    final options = _options ?? defaults;
    final changed = options.changedFrom(defaults);
    return Disclosure(
      label: 'Tuning',
      expanded: _showOptions,
      onToggle: () => setState(() => _showOptions = !_showOptions),
      summary: changed == 0
          ? options.summary
          : '${options.summary}  ($changed changed)',
      trailing: changed == 0
          ? null
          : TextButton(
              onPressed: () => setState(() => _options = null),
              style: TextButton.styleFrom(
                foregroundColor: c.primary,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: Space.x2),
              ),
              child: const Text('Reset to defaults'),
            ),
      children: [
        const SizedBox(height: Space.x2),
        MountOptionsEditor(
          value: options,
          onChanged: (v) => setState(() => _options = v),
        ),
        Text(
          'Applies to this mount only. Change what new mounts start with in '
          'Settings.',
          style: TextStyle(color: c.textFaint, fontSize: 11),
        ),
        const SizedBox(height: Space.x3),
      ],
    );
  }

  Widget _winfspBanner(AircloneColors c) => Container(
    margin: const EdgeInsets.only(bottom: Space.x3),
    padding: const EdgeInsets.all(Space.x3),
    decoration: BoxDecoration(
      color: c.warningBg,
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: c.warning),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(
            'Mounting on Windows needs WinFsp. Install it from winfsp.dev, then '
            'restart Airclone.',
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
        ),
      ],
    ),
  );

  List<Widget> _running(AircloneColors c) {
    final mounts = ref.watch(mountControllerProvider);
    return [
      Row(
        children: [
          Text(
            'Mounted drives',
            style: TextStyle(
              color: c.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (mounts.isNotEmpty)
            TextButton(
              onPressed: () =>
                  ref.read(mountControllerProvider.notifier).unmountAll(),
              child: Text('Unmount all', style: TextStyle(color: c.error)),
            ),
        ],
      ),
      const SizedBox(height: Space.x2),
      if (mounts.isEmpty)
        Text(
          'Nothing mounted.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        )
      else
        for (final m in mounts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Row(
              children: [
                Icon(Icons.usb, size: 16, color: c.textMuted),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    '${m.mountPoint}   ${m.fs}',
                    style: TextStyle(color: c.text, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh cache (pick up outside changes)',
                  onPressed: () async {
                    final err = await ref
                        .read(mountControllerProvider.notifier)
                        .refreshCache(m.fs);
                    if (!mounted) return;
                    setState(() {
                      _refreshMsg = err == null
                          ? 'Refreshing the directory cache of '
                                '${m.fs.isEmpty ? 'the mount' : m.fs} in the '
                                'background…'
                          : 'Refresh failed: $err';
                    });
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  color: c.textMuted,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Unmount',
                  onPressed: () => ref
                      .read(mountControllerProvider.notifier)
                      .unmount(m.mountPoint),
                  icon: const Icon(Icons.eject_outlined, size: 18),
                  color: c.error,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
      if (_refreshMsg != null) ...[
        const SizedBox(height: Space.x1),
        Text(
          _refreshMsg!,
          style: TextStyle(
            color: _refreshMsg!.startsWith('Refresh failed')
                ? c.error
                : c.textMuted,
            fontSize: 11,
          ),
        ),
      ],
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
