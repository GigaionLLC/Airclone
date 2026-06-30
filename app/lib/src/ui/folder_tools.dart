import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/browser_controller.dart';
import '../state/file_ops.dart';
import 'format.dart';
import 'theme/tokens.dart';

// ── Compare / verify two locations ──────────────────────────────────────────

/// Compares the active pane against the other pane (`operations/check`) and
/// shows the match / differ / missing buckets. Needs a remote open in each pane.
Future<void> showCompareDialog(BuildContext context, WidgetRef ref) async {
  final active = ref.read(activePaneProvider);
  final src = ref.read(paneProvider(active));
  final dst = ref.read(paneProvider(active == 0 ? 1 : 0));
  if (src.remote == null || dst.remote == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Open a remote in each pane (dual-pane view) to compare them.',
        ),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _CompareDialog(
      srcFs: '${src.remote!.fs}${src.path}',
      dstFs: '${dst.remote!.fs}${dst.path}',
      srcLabel: '${src.remote!.name}:${src.path}',
      dstLabel: '${dst.remote!.name}:${dst.path}',
    ),
  );
}

class _CompareDialog extends ConsumerStatefulWidget {
  const _CompareDialog({
    required this.srcFs,
    required this.dstFs,
    required this.srcLabel,
    required this.dstLabel,
  });
  final String srcFs;
  final String dstFs;
  final String srcLabel;
  final String dstLabel;

  @override
  ConsumerState<_CompareDialog> createState() => _CompareDialogState();
}

class _CompareDialogState extends ConsumerState<_CompareDialog> {
  CompareResult? _result;
  bool _loading = true;
  bool _download = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(fileOpsProvider)
          .compare(widget.srcFs, widget.dstFs, download: _download);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final r = _result;
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: const Text('Compare'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.srcLabel}  →  ${widget.dstLabel}',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
            const SizedBox(height: Space.x3),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Space.x4),
                child: Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: c.error, fontSize: 12))
            else if (r != null) ...[
              _row(
                c,
                Icons.check_circle_outline,
                'Identical',
                r.match.length,
                c.success,
              ),
              _row(
                c,
                Icons.compare_arrows,
                'Different',
                r.differ.length,
                r.differ.isEmpty ? c.textMuted : c.warning,
                r.differ,
              ),
              _row(
                c,
                Icons.south_west,
                'Only on ${widget.dstLabel}',
                r.missingOnSrc.length,
                c.textMuted,
                r.missingOnSrc,
              ),
              _row(
                c,
                Icons.north_east,
                'Only on ${widget.srcLabel}',
                r.missingOnDst.length,
                c.textMuted,
                r.missingOnDst,
              ),
              if (r.error.isNotEmpty)
                _row(
                  c,
                  Icons.error_outline,
                  'Errors',
                  r.error.length,
                  c.error,
                  r.error,
                ),
              const SizedBox(height: Space.x3),
              Text(
                r.usedHash
                    ? 'Compared by ${r.hashType} checksum.'
                    : 'No shared checksum — compared by size + time.'
                          '${_download ? ' (downloaded to verify bytes)' : ' Use "Compare by downloading" to verify contents.'}',
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_loading && !_download)
          TextButton(
            onPressed: () {
              setState(() => _download = true);
              _run();
            },
            child: const Text('Compare by downloading'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _row(
    AircloneColors c,
    IconData icon,
    String label,
    int count,
    Color color, [
    List<String>? files,
  ]) {
    final subtitle = (files != null && files.isNotEmpty && count <= 8)
        ? files.join(', ')
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: c.text, fontSize: 12)),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(color: c.textFaint, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Upload from URL ─────────────────────────────────────────────────────────

/// Prompts for a URL and streams it straight into [state]'s folder
/// (`operations/copyurl`) — no local round-trip.
Future<void> showCopyUrlDialog(
  BuildContext context,
  WidgetRef ref,
  int index,
) async {
  final state = ref.read(paneProvider(index));
  if (state.remote == null) return;
  final controller = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (dctx) {
      final c = AircloneTheme.of(dctx);
      String? result() =>
          controller.text.trim().isEmpty ? null : controller.text.trim();
      return AlertDialog(
        backgroundColor: c.surfaceRaised,
        title: const Text('Upload from URL'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'https://example.com/file.zip',
              helperText: 'Downloaded by the engine straight into this folder.',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
            onSubmitted: (_) => Navigator.of(dctx).pop(result()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(result()),
            child: const Text('Upload'),
          ),
        ],
      );
    },
  );
  if (url == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(fileOpsProvider).copyUrl(state.remote!, state.path, url);
    await ref.read(paneProvider(index).notifier).refresh();
    messenger.showSnackBar(const SnackBar(content: Text('Uploaded from URL.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Upload failed: $e')));
  }
}

// ── Folder size ─────────────────────────────────────────────────────────────

/// Computes and shows the total file count + byte size of [state]'s folder
/// (`operations/size`).
Future<void> showFolderSizeDialog(
  BuildContext context,
  WidgetRef ref,
  int index,
) async {
  final state = ref.read(paneProvider(index));
  if (state.remote == null) return;
  final fs = '${state.remote!.fs}${state.path}';
  await showDialog<void>(
    context: context,
    builder: (dctx) =>
        _SizeDialog(fs: fs, label: '${state.remote!.name}:${state.path}'),
  );
}

class _SizeDialog extends ConsumerStatefulWidget {
  const _SizeDialog({required this.fs, required this.label});
  final String fs;
  final String label;

  @override
  ConsumerState<_SizeDialog> createState() => _SizeDialogState();
}

class _SizeDialogState extends ConsumerState<_SizeDialog> {
  (int, int)? _size;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final s = await ref.read(fileOpsProvider).folderSize(widget.fs);
      if (mounted) setState(() => _size = s);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final s = _size;
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: const Text('Folder size'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
            const SizedBox(height: Space.x3),
            if (_error != null)
              Text(_error!, style: TextStyle(color: c.error, fontSize: 12))
            else if (s == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(Space.x3),
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              Text(
                s.$2 < 0 ? 'Size unknown' : humanSize(s.$2),
                style: TextStyle(
                  color: c.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${s.$1} file${s.$1 == 1 ? '' : 's'}',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ── Empty trash / cleanup ───────────────────────────────────────────────────

/// Confirms then empties the backend trash / aborts incomplete uploads
/// (`operations/cleanup`). Surfaces an honest error when the backend lacks it.
Future<void> confirmEmptyTrash(
  BuildContext context,
  WidgetRef ref,
  int index,
) async {
  final state = ref.read(paneProvider(index));
  if (state.remote == null) return;
  final c = AircloneTheme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: const Text('Empty trash'),
      content: Text(
        'Permanently remove "${state.remote!.name}"\'s trashed files and '
        'incomplete uploads to reclaim space? This cannot be undone.',
        style: TextStyle(color: c.textMuted, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('Empty'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(fileOpsProvider).cleanup(state.remote!);
    messenger.showSnackBar(const SnackBar(content: Text('Trash emptied.')));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('This remote can\'t empty trash, or it failed: $e'),
      ),
    );
  }
}
