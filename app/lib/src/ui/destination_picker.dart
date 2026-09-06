import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/engine_controller.dart';
import '../state/local_locations.dart';
import '../state/remotes_provider.dart';
import 'home_view.dart' show localKindIcon;
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// Opens a modal dialog that lets the user pick a destination folder for a
/// "Copy to…" / "Move to…" operation.
///
/// Flow: pick a remote (from [remotesProvider]), browse INTO its directories
/// (only folders are shown), then confirm with "Select this folder".
///
/// Resolves to a record `({Remote remote, String path})` for the currently-open
/// folder, or `null` if the user cancels.
Future<({Remote remote, String path})?> showDestinationPicker(
  BuildContext context, {
  String title = 'Choose destination',
}) {
  return showDialog<({Remote remote, String path})?>(
    context: context,
    builder: (_) => _DestinationPickerDialog(title: title),
  );
}

class _DestinationPickerDialog extends ConsumerStatefulWidget {
  const _DestinationPickerDialog({required this.title});

  final String title;

  @override
  ConsumerState<_DestinationPickerDialog> createState() =>
      _DestinationPickerDialogState();
}

class _DestinationPickerDialogState
    extends ConsumerState<_DestinationPickerDialog> {
  /// The remote being browsed; `null` while on the remote-selection step.
  Remote? _selectedRemote;

  /// Current path within [_selectedRemote] (relative to its fs).
  String _currentPath = '';

  /// Directory entries for [_currentPath].
  List<RcloneFile> _dirs = const [];

  bool _loading = false;
  String? _error;

  /// Path split into navigable breadcrumb segments.
  List<String> get _segments => _currentPath.isEmpty
      ? const []
      : _currentPath.split('/').where((s) => s.isNotEmpty).toList();

  // ── navigation ──────────────────────────────────────────────────────────────

  Future<void> _openRemote(Remote remote) async {
    setState(() {
      _selectedRemote = remote;
      _currentPath = '';
    });
    await _load();
  }

  Future<void> _enterDir(RcloneFile dir) async {
    if (!dir.isDir) return;
    final next = _currentPath.isEmpty ? dir.name : '$_currentPath/${dir.name}';
    setState(() => _currentPath = next);
    await _load();
  }

  Future<void> _goToSegment(int index) async {
    final segs = _segments;
    final next = (index < 0) ? '' : segs.take(index + 1).join('/');
    setState(() => _currentPath = next);
    await _load();
  }

  Future<void> _up() async {
    if (_segments.isEmpty) return;
    await _goToSegment(_segments.length - 2);
  }

  /// Back out of the open remote to the remote-selection step.
  void _backToRemotes() {
    setState(() {
      _selectedRemote = null;
      _currentPath = '';
      _dirs = const [];
      _error = null;
      _loading = false;
    });
  }

  /// Lists the current folder via `operations/list`, keeping only directories.
  Future<void> _load() async {
    final remote = _selectedRemote;
    if (remote == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _dirs = const [];
        _error = 'Engine not ready';
      });
      return;
    }
    try {
      final res = await client.rpc(
        'operations/list',
        remote.listParams(_currentPath),
      );
      final dirs =
          (res['list'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(RcloneFile.fromJson)
              .where((f) => f.isDir)
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dirs = const [];
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _confirm() {
    final remote = _selectedRemote;
    if (remote == null) return;
    Navigator.of(context).pop((remote: remote, path: _currentPath));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: DialogBody(
        width: 520,
        height: 560,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: _selectedRemote == null
              ? _buildRemoteStep(c)
              : _buildBrowseStep(c),
        ),
      ),
    );
  }

  // Step 1 — pick where to browse.
  //
  // The same three sections as the sidebar (LOCATIONS / DISKS / CLOUD), and for
  // the same reason: this used to list `remotesProvider` alone, which is the
  // rclone remotes plus one synthetic home folder. A local disk was therefore
  // impossible to choose as a destination — "Copy to…" could not reach the
  // drive sitting in the sidebar two inches away, and the only way through was
  // to navigate a pane there by hand and paste. Local disks and saved folders
  // live in their own providers, and nothing here knew about them.
  Widget _buildRemoteStep(AircloneColors c) {
    final remotes = ref.watch(remotesProvider);
    final locations = ref.watch(userLocationsProvider);
    final drives = ref.watch(drivesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(c, widget.title, subtitle: 'Pick where to browse to.'),
        Expanded(
          child: remotes.when(
            data: (list) {
              final rows = <Widget>[
                if (locations.isNotEmpty) ...[
                  _sectionLabel(c, 'LOCATIONS'),
                  for (final l in locations)
                    _remoteTile(c, l.remote, icon: localKindIcon(l.kind)),
                ],
                if (drives.isNotEmpty) ...[
                  _sectionLabel(c, 'DISKS'),
                  for (final d in drives)
                    _remoteTile(c, d.remote, icon: localKindIcon(d.kind)),
                ],
                if (list.isNotEmpty) ...[
                  _sectionLabel(c, 'CLOUD'),
                  for (final r in list) _remoteTile(c, r),
                ],
              ];
              if (rows.isEmpty) {
                return _empty(c, 'Nothing to copy to yet.');
              }
              return ListView(children: rows);
            },
            // A failed remote list must not hide the local disks, which need no
            // engine and are always available. Losing the cloud section is bad;
            // losing the whole dialog with it is worse.
            loading: () => _localOnly(
              c,
              locations,
              drives,
              const Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) =>
                _localOnly(c, locations, drives, _errorBox(c, '$e')),
          ),
        ),
        const SizedBox(height: Space.x3),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  /// The cloud section still loading or broken, with the local sections — which
  /// need no engine — kept usable underneath it.
  Widget _localOnly(
    AircloneColors c,
    List<LocalLocation> locations,
    List<LocalLocation> drives,
    Widget cloudState,
  ) => ListView(
    children: [
      if (locations.isNotEmpty) ...[
        _sectionLabel(c, 'LOCATIONS'),
        for (final l in locations)
          _remoteTile(c, l.remote, icon: localKindIcon(l.kind)),
      ],
      if (drives.isNotEmpty) ...[
        _sectionLabel(c, 'DISKS'),
        for (final d in drives)
          _remoteTile(c, d.remote, icon: localKindIcon(d.kind)),
      ],
      _sectionLabel(c, 'CLOUD'),
      SizedBox(height: 80, child: cloudState),
    ],
  );

  Widget _sectionLabel(AircloneColors c, String label) => Padding(
    padding: const EdgeInsets.only(
      top: Space.x3,
      bottom: Space.x1,
      left: Space.x2,
    ),
    child: Text(
      label,
      style: TextStyle(
        color: c.textFaint,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _remoteTile(AircloneColors c, Remote remote, {IconData? icon}) =>
      InkWell(
        onTap: () => _openRemote(remote),
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x2,
            vertical: Space.x3,
          ),
          child: Row(
            children: [
              Icon(
                icon ??
                    (remote.isLocal
                        ? Icons.computer_outlined
                        : Icons.cloud_outlined),
                size: 20,
                color: c.primary,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remote.name,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      remote.type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textFaint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: c.textFaint),
            ],
          ),
        ),
      );

  // Step 2 — browse into folders of the chosen remote.
  Widget _buildBrowseStep(AircloneColors c) {
    final remote = _selectedRemote!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _backToRemotes,
              icon: const Icon(Icons.arrow_back, size: 18),
              tooltip: 'Back to remotes',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: Space.x1),
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        _breadcrumbBar(c, remote),
        const SizedBox(height: Space.x3),
        Expanded(child: _folderList(c)),
        const SizedBox(height: Space.x3),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: Space.x2),
            FilledButton(
              onPressed: _confirm,
              child: const Text('Select this folder'),
            ),
          ],
        ),
      ],
    );
  }

  /// Breadcrumb (remote root + segments) with an Up button.
  Widget _breadcrumbBar(AircloneColors c, Remote remote) {
    final segs = _segments;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x2,
        vertical: Space.x1,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: segs.isEmpty ? null : _up,
            icon: const Icon(Icons.arrow_upward, size: 16),
            tooltip: 'Up',
            visualDensity: VisualDensity.compact,
            color: c.textMuted,
            disabledColor: c.textFaint,
          ),
          const SizedBox(width: Space.x1),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _crumb(c, remote.name, () => _goToSegment(-1), root: true),
                  for (var i = 0; i < segs.length; i++) ...[
                    Icon(Icons.chevron_right, size: 14, color: c.textFaint),
                    _crumb(
                      c,
                      segs[i],
                      () => _goToSegment(i),
                      isLast: i == segs.length - 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _crumb(
    AircloneColors c,
    String label,
    VoidCallback onTap, {
    bool root = false,
    bool isLast = false,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(Radii.sm),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x2,
        vertical: Space.x1,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (root) ...[
            Icon(Icons.home_outlined, size: 14, color: c.textMuted),
            const SizedBox(width: Space.x1),
          ],
          Text(
            label,
            style: TextStyle(
              color: isLast ? c.text : c.textMuted,
              fontSize: 13,
              fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );

  /// The directory listing for the current folder, with loading/empty/error.
  Widget _folderList(AircloneColors c) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _errorBox(c, _error!);
    }
    if (_dirs.isEmpty) {
      return _empty(c, 'No subfolders here.');
    }
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Space.x1),
        itemCount: _dirs.length,
        itemBuilder: (_, i) => _folderTile(c, _dirs[i]),
      ),
    );
  }

  Widget _folderTile(AircloneColors c, RcloneFile dir) => InkWell(
    onTap: () => _enterDir(dir),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x3,
        vertical: Space.x3,
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 18, color: c.primary),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Text(
              dir.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.text, fontSize: 14),
            ),
          ),
          Icon(Icons.chevron_right, size: 16, color: c.textFaint),
        ],
      ),
    ),
  );

  // ── shared bits ─────────────────────────────────────────────────────────────

  Widget _header(AircloneColors c, String title, {String? subtitle}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: c.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: Space.x1),
        Text(subtitle, style: TextStyle(color: c.textMuted, fontSize: 13)),
      ],
      const SizedBox(height: Space.x4),
    ],
  );

  Widget _empty(AircloneColors c, String message) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_off_outlined, size: 32, color: c.textFaint),
        const SizedBox(height: Space.x2),
        Text(message, style: TextStyle(color: c.textMuted, fontSize: 13)),
      ],
    ),
  );

  Widget _errorBox(AircloneColors c, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 32, color: c.error),
          const SizedBox(height: Space.x2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
          if (_selectedRemote != null) ...[
            const SizedBox(height: Space.x3),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ],
      ),
    ),
  );
}
