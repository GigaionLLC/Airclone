import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/mount_options.dart';
import '../rclone/rclone_client.dart';
import '../state/mount_controller.dart';
import '../state/mount_defaults.dart';
import '../state/mount_letters.dart';
import '../state/mount_policy.dart';
import '../state/remotes_provider.dart';
import 'dialog_body.dart';
import 'disclosure.dart';
import 'mount_options_editor.dart';
import 'theme/tokens.dart';
import '../state/build_flavor.dart';
import '../state/host_platform.dart';
import '../state/mount_point.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the Mount manager (mount remotes as drives + list/unmount running ones).
Future<void> showMountDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _MountDialog());

/// Why mounting is missing in a Flatpak, and what to use instead.
///
/// Shown rather than hiding the button, because hiding it reads as "Airclone
/// cannot do this" when the truth is "this PACKAGE cannot, and another one can".
///
/// There is deliberately no "grant a permission" instruction, because no
/// permission delivers it. `--device=all` would expose /dev/fuse, but a Flatpak
/// has its own MOUNT NAMESPACE: a drive mounted inside the sandbox is visible
/// only to Airclone, and the entire point of mounting is that OTHER programs —
/// a file manager, an editor — can open the files. The only way out is
/// `--talk-name=org.freedesktop.Flatpak`, which lets the app run arbitrary
/// commands on the host and is a sandbox escape in everything but name. Trading
/// the sandbox away for one feature that two other packages already provide
/// would be a bad bargain, so the answer is the other package.
Future<void> showMountUnavailableInFlatpakDialog(BuildContext context) {
  final c = AircloneTheme.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      title: Row(
        children: [
          Icon(Icons.usb_off_outlined, size: 20, color: c.primary),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              'Mounting needs a different package',
              style: TextStyle(
                color: c.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: DialogBody(
        width: 460,
        child: Text(
          'This is the Flatpak build, and it runs in a sandbox with its own view '
          'of the filesystem. A drive mounted inside it would be visible only to '
          'Airclone — not to your file manager, your editor, or anything else — '
          'which is the whole point of mounting one. No permission setting '
          'changes that.\n\n'
          'This is a limit of Flatpak itself, not something Airclone can fix '
          'from inside it.\n\n'
          'To mount a remote as a drive, use the AppImage or the tar.gz instead. '
          'Everything else Airclone does works here, and browsing a remote in '
          'Airclone needs no mount at all — it is usually faster than one.',
          style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.45),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.x4,
        0,
        Space.x4,
        Space.x4,
      ),
      actions: [
        // The direct-download bundle gets a link to the package that CAN
        // mount. A build shipped BY Flathub does not: sending its users off to
        // download a different package from outside the store is the kind of
        // link a store rejects, and the Microsoft Store already failed an
        // Airclone submission on policy 10.2.5 for linking to GitHub releases.
        if (!kFlathubChannel)
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(kReleasesPageUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Get the AppImage'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _MountDialog extends ConsumerStatefulWidget {
  const _MountDialog();
  @override
  ConsumerState<_MountDialog> createState() => _MountDialogState();
}

class _MountDialogState extends ConsumerState<_MountDialog> {
  final _subdir = TextEditingController();
  String? _remote;
  String _drive = '*'; // auto

  /// Drive letters on Windows, a FOLDER everywhere else.
  ///
  /// This dialog used to offer drive letters on every platform. rclone honours
  /// "*" and drive letters on Windows only, so on Linux and macOS every choice
  /// here failed with "cannot open: *: no such file or directory" - mounting
  /// never worked there through the app. See state/mount_point.dart.
  static final bool _letters = mountsOntoDriveLetters(
    windows: HostPlatform.isWindows,
    web: HostPlatform.isWeb,
  );

  /// The folder a non-Windows mount goes into.
  final _folder = TextEditingController();

  /// Set once the user types or picks a folder, so changing the remote stops
  /// overwriting what they chose with a fresh default.
  bool _folderEdited = false;
  String? _error;
  bool _starting = false;

  /// Pin this mount's drive letter to this fs, so it comes back on the same one
  /// next time. Ticked automatically when the fs already has a pin.
  bool _rememberDrive = false;

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
  void initState() {
    super.initState();
    // The pin is per fs, and the subfolder is part of the fs — so typing one
    // has to re-check for a pin, not just picking the remote.
    _subdir.addListener(_applyPinnedDrive);
    _subdir.addListener(_refreshDefaultFolder);
  }

  /// Keeps the suggested folder in step with the remote and subfolder, until
  /// the user has chosen one of their own.
  void _refreshDefaultFolder() {
    if (_letters || _folderEdited || _remote == null) return;
    final home = HostPlatform.environment['HOME'] ?? '';
    if (home.isEmpty) return;
    final next = defaultMountFolder(home: home, fs: _fs);
    if (_folder.text != next) _folder.text = next;
  }

  @override
  void dispose() {
    _subdir.removeListener(_applyPinnedDrive);
    _subdir.removeListener(_refreshDefaultFolder);
    _subdir.dispose();
    _folder.dispose();
    super.dispose();
  }

  /// The fs this dialog would mount, assembled the way [_start] assembles it.
  String get _fs {
    final sub = _subdir.text.trim();
    return sub.isEmpty ? '$_remote:' : '$_remote:$sub';
  }

  /// Preselect the letter this fs is pinned to, if any. Silent when there is no
  /// pin: a remote nobody has pinned keeps whatever the user last chose here,
  /// rather than being reset to Auto under their hands.
  void _applyPinnedDrive() {
    if (_remote == null) return;
    final pinned = ref.read(mountLettersProvider)[_fs];
    // A pin is a drive letter on Windows and a folder elsewhere. One of the
    // wrong shape is ignored rather than applied: a letter handed to rclone on
    // Linux is exactly the failure this dialog used to produce.
    final rightShape =
        pinned != null &&
        (_letters ? !pinned.startsWith('/') : pinned.startsWith('/'));
    if (pinned == null || !rightShape) {
      if (_rememberDrive) setState(() => _rememberDrive = false);
      return;
    }
    if (!_letters) {
      if (_folder.text == pinned && _rememberDrive) return;
      setState(() {
        _folder.text = pinned;
        _folderEdited = true;
        _rememberDrive = true;
      });
      return;
    }
    if (pinned == _drive && _rememberDrive) return;
    setState(() {
      _drive = pinned;
      _rememberDrive = true;
    });
  }

  Future<void> _start() async {
    if (_remote == null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    final sub = _subdir.text.trim();
    final fs = sub.isEmpty ? '$_remote:' : '$_remote:$sub';
    final String mountPoint;
    if (_letters) {
      mountPoint = _drive;
    } else {
      // rclone will not create the folder and refuses a non-empty one with an
      // error that says nothing useful, so both are handled here first.
      final problem = await prepareMountFolder(_folder.text);
      if (problem != null) {
        if (mounted) {
          setState(() {
            _starting = false;
            _error = problem;
          });
        }
        return;
      }
      mountPoint = _folder.text.trim();
    }
    try {
      final actual = await ref
          .read(mountControllerProvider.notifier)
          .mount(fs: fs, mountPoint: mountPoint, options: _effectiveOptions);
      // Pinned AFTER the mount succeeds, and to the letter rclone actually
      // used: with Auto selected that is the assigned one, which is exactly the
      // "put it back where it was" case worth remembering.
      final letters = ref.read(mountLettersProvider.notifier);
      if (_rememberDrive) {
        await letters.remember(fs, actual);
      } else {
        await letters.forget(fs);
      }
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = friendlyMountError(
            e is RcloneException ? e.message : '$e',
            windows: HostPlatform.isWindows,
          );
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
      // An empty mount-type list means the FUSE layer is missing. That is WinFsp
      // on Windows and FUSE elsewhere; naming WinFsp to a Linux user was wrong.
      if (winfspMissing && _letters) _winfspBanner(c),
      if (winfspMissing && !_letters) _fuseBanner(c),
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
                onChanged: (v) {
                  setState(() => _remote = v);
                  _refreshDefaultFolder();
                  _applyPinnedDrive();
                },
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
      if (!_letters) _folderRow(c),
      if (_letters)
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
      _rememberDriveRow(c),
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
  /// "Use this drive letter next time" — the opt-in that turns a one-off letter
  /// into a pin for this fs.
  ///
  /// Offered even with Auto selected: the pin is written from the letter rclone
  /// actually assigned, so "whatever I got this time, keep giving me that" is a
  /// single tick rather than a thing to notice and re-enter afterwards.
  Widget _rememberDriveRow(AircloneColors c) => Padding(
    padding: const EdgeInsets.only(top: Space.x1),
    child: InkWell(
      onTap: () => setState(() => _rememberDrive = !_rememberDrive),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.all(Space.x1),
        child: Row(
          children: [
            SizedBox(
              height: 20,
              width: 20,
              child: Checkbox(
                value: _rememberDrive,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => _rememberDrive = v ?? false),
              ),
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                !_letters
                    ? 'Always mount this in this folder'
                    : _drive == '*'
                    ? 'Reuse whichever letter this mount gets, next time'
                    : 'Always mount this on $_drive',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );

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

  /// Linux and macOS: the folder the drive appears in.
  Widget _folderRow(AircloneColors c) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: _field(
          c,
          'Folder',
          TextField(
            controller: _folder,
            decoration: _dec(c, '/home/you/Airclone/remote'),
            style: TextStyle(color: c.text, fontSize: 13),
            onChanged: (_) => _folderEdited = true,
          ),
        ),
      ),
      const SizedBox(width: Space.x2),
      Padding(
        padding: const EdgeInsets.only(bottom: Space.x3),
        child: OutlinedButton(
          onPressed: () async {
            final picked = await getDirectoryPath(
              confirmButtonText: 'Mount here',
              initialDirectory: _folder.text.isEmpty ? null : _folder.text,
            );
            if (picked == null || !mounted) return;
            setState(() {
              _folder.text = picked;
              _folderEdited = true;
            });
          },
          child: const Text('Choose…'),
        ),
      ),
    ],
  );

  Widget _fuseBanner(AircloneColors c) => Container(
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
            HostPlatform.isMacOS
                ? 'Mounting on macOS needs macFUSE or FUSE-T. Install one, then '
                      'restart Airclone.'
                : 'Mounting needs FUSE. Install it (for example '
                      '`sudo apt install fuse3`), then restart Airclone.',
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
        ),
      ],
    ),
  );

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
