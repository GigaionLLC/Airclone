import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import '../state/browser_controller.dart';
import '../state/engine_controller.dart';
import '../state/remote_features.dart';
import '../state/thumbnail_prefs.dart';
import '../state/thumbnail_service.dart';
import '../state/transfer_service.dart';
import 'file_icon.dart';
import 'format.dart';
import 'pane_drag.dart';
import 'preview_dialog.dart';
import 'theme/tokens.dart';
import 'thumbnail_image.dart';

/// Whether the right-rail inspector is shown (off by default).
final inspectorVisibleProvider = StateProvider<bool>((ref) => false);

/// Right-rail details panel reflecting the ACTIVE pane's current selection:
/// a single-file detail card, a multi-select summary, or an empty/folder state.
class InspectorPanel extends ConsumerStatefulWidget {
  const InspectorPanel({super.key});

  @override
  ConsumerState<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends ConsumerState<InspectorPanel> {
  int _tab = 0; // 0 = Overview, 1 = More.

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final active = ref.watch(activePaneProvider);
    final state = ref.watch(paneProvider(active));
    final sel = state.selectedEntries;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(left: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(c),
          _tabs(c),
          Expanded(child: _body(c, state, sel)),
        ],
      ),
    );
  }

  /// "DETAILS" label + close button.
  Widget _header(AircloneColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x2, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'DETAILS',
              style: TextStyle(
                color: c.textFaint,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: c.textMuted,
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                ref.read(inspectorVisibleProvider.notifier).state = false,
          ),
        ],
      ),
    );
  }

  /// Small segmented Overview / More header.
  Widget _tabs(AircloneColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.x4,
        Space.x1,
        Space.x4,
        Space.x2,
      ),
      child: Row(
        children: [
          _tabButton(c, 'Overview', 0),
          const SizedBox(width: Space.x2),
          _tabButton(c, 'More', 1),
        ],
      ),
    );
  }

  Widget _tabButton(AircloneColors c, String label, int index) {
    final on = _tab == index;
    return TextButton(
      onPressed: () => setState(() => _tab = index),
      style: TextButton.styleFrom(
        backgroundColor: on ? c.surfaceSunken : Colors.transparent,
        foregroundColor: on ? c.text : c.textMuted,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: Space.x3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  Widget _body(AircloneColors c, BrowserState state, List<RcloneFile> sel) {
    if (sel.length == 1) {
      return _tab == 0
          ? _singleOverview(c, state, sel.first)
          : _singleMore(c, state, sel.first);
    }
    if (sel.length > 1) return _multi(c, state, sel);
    return _empty(c, state);
  }

  // ── Empty / folder summary ────────────────────────────────────────────────

  Widget _empty(AircloneColors c, BrowserState state) {
    final remote = state.remote;
    if (remote == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined, size: 40, color: c.textFaint),
              const SizedBox(height: Space.x3),
              Text(
                'Select a file to see details',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        _card(c, [
          Row(
            children: [
              Icon(Icons.folder_rounded, size: 20, color: c.primary),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  remote.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          _row(c, 'Path', state.path.isEmpty ? '/' : state.path),
          _row(c, 'Items', '${state.entries.length} items'),
        ]),
      ],
    );
  }

  // ── Single file — Overview ────────────────────────────────────────────────

  Widget _singleOverview(AircloneColors c, BrowserState state, RcloneFile f) {
    final remote = state.remote!;
    final fullPath = joinPath(state.path, f.name);
    final kindName = kindOf(f).name;
    final kindLabel = kindName.isEmpty
        ? kindName
        : '${kindName[0].toUpperCase()}${kindName.substring(1)}';
    final sub = f.size < 0 ? kindLabel : '$kindLabel · ${humanSize(f.size)}';

    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        _preview(c, state, f),
        const SizedBox(height: Space.x3),
        Text(
          f.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.x1),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
        const SizedBox(height: Space.x3),
        _pills(c, state, f),
        const SizedBox(height: Space.x3),
        _card(c, [
          _row(c, 'Modified', relativeTime(f.modTime)),
          _row(c, 'Path', fullPath),
          _row(c, 'Remote', remote.name),
        ]),
      ],
    );
  }

  /// Big square thumbnail/icon preview box.
  Widget _preview(AircloneColors c, BrowserState state, RcloneFile f) {
    final remote = state.remote!;
    final client = ref.read(engineControllerProvider).client;
    final thumbsOn =
        thumbnailsOn(remote, ref.watch(thumbnailsDisabledProvider)) &&
        isThumbnailable(f) &&
        client != null;

    final placeholder = Center(
      child: Icon(iconFor(f), color: iconColorFor(f, c), size: 56),
    );

    Widget inner = placeholder;
    if (thumbsOn) {
      final ObjectRef oref = client.objectRef(
        remote.fs,
        joinPath(state.path, f.name),
      );
      inner = ThumbnailImage(
        request: ThumbRequest(
          url: oref.url,
          headers: oref.headers,
          cacheKey: thumbCacheKey(remote.fs, f.path, f.modTime, f.size, 512),
          cacheSecret: remote.name,
          size: 512,
          isVideo: isVideoThumbnailable(f),
        ),
        placeholder: placeholder,
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(color: c.surfaceSunken, child: inner),
      ),
    );
  }

  /// Quick-action pills: Preview, Download, and Copy link (when supported).
  Widget _pills(AircloneColors c, BrowserState state, RcloneFile f) {
    final remote = state.remote!;
    final feats = ref.watch(remoteFeaturesProvider(remote.fs));
    final canLink = feats.maybeWhen(
      data: (m) => m['PublicLink'] == true,
      orElse: () => false,
    );

    return Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      alignment: WrapAlignment.center,
      children: [
        _pill(c, Icons.visibility, 'Preview', () {
          showPreviewDialog(context, ref, remote, state.path, f);
        }),
        _pill(c, Icons.download, 'Download', () => _download(state, f)),
        if (canLink)
          _pill(c, Icons.link, 'Copy link', () => _publicLink(state, f)),
      ],
    );
  }

  Widget _pill(
    AircloneColors c,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Material(
      color: c.surfaceSunken,
      borderRadius: BorderRadius.circular(Radii.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.full),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x3,
            vertical: Space.x1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: c.textMuted),
              const SizedBox(width: Space.x1),
              Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Single file — More ────────────────────────────────────────────────────

  Widget _singleMore(AircloneColors c, BrowserState state, RcloneFile f) {
    final remote = state.remote!;
    final feats = ref.watch(remoteFeaturesProvider(remote.fs));
    final links = feats.maybeWhen(
      data: (m) => m['PublicLink'] == true ? 'yes' : 'no',
      orElse: () => '—',
    );

    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        _card(c, [
          _row(c, 'MIME', f.mimeType.isEmpty ? '—' : f.mimeType),
          _row(c, 'Full path', joinPath(state.path, f.name)),
          _row(c, 'Remote fs', remote.fs),
          _row(c, 'Backend type', remote.type),
          _row(c, 'Public links', links),
        ]),
      ],
    );
  }

  // ── Multi-select ──────────────────────────────────────────────────────────

  Widget _multi(AircloneColors c, BrowserState state, List<RcloneFile> sel) {
    var total = 0;
    for (final f in sel) {
      if (f.size >= 0) total += f.size;
    }

    if (_tab == 1) {
      return ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          _card(c, [
            _row(c, 'Selected', '${sel.length} items'),
            _row(c, 'Total', humanSize(total)),
          ]),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        _card(c, [
          Text(
            '${sel.length} items selected',
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.x1),
          Text(
            'Total ${humanSize(total)}',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          const SizedBox(height: Space.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: _pill(c, Icons.download, 'Download all', () {
              for (final f in sel) {
                _download(state, f);
              }
            }),
          ),
        ]),
      ],
    );
  }

  // ── Shared building blocks ────────────────────────────────────────────────

  Widget _card(AircloneColors c, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// A label/value detail row.
  Widget _row(AircloneColors c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.textFaint, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '—' : value,
            style: TextStyle(color: c.text, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Copy [f] from the active pane's remote into the OS Downloads folder.
  Future<void> _download(BrowserState state, RcloneFile f) async {
    final remote = state.remote;
    if (remote == null) return;
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final downloads =
        '${home.replaceAll(String.fromCharCode(92), '/')}/Downloads';
    final local = Remote(
      name: 'Downloads',
      type: 'local',
      fs: '$downloads/',
      isLocal: true,
    );
    await ref
        .read(transferServiceProvider)
        .transfer(
          srcRemote: remote,
          srcPath: joinPath(state.path, f.name),
          dstRemote: local,
          dstPath: f.name,
          type: JobType.copy,
        );
  }

  /// Request a public link for [f] and surface it in a small dialog.
  Future<void> _publicLink(BrowserState state, RcloneFile f) async {
    final remote = state.remote;
    final client = ref.read(engineControllerProvider).client;
    if (remote == null || client == null) return;
    try {
      final res = await client.rpc('operations/publiclink', {
        'fs': remote.fs,
        'remote': joinPath(state.path, f.name),
      });
      final url = (res['url'] ?? '').toString();
      if (!mounted) return;
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No public link available.')),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Public link'),
          content: SelectableText(url),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create link: $e')));
    }
  }
}
