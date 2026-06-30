import 'package:flutter/material.dart';

import '../rclone/rclone_client.dart';
import '../state/dedupe.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// Finds content-identical files (same size + hash) under [basePath] and lets
/// the user keep one copy per group and delete the rest. Deletion targets each
/// copy by its unique path via `operations/deletefile`, so it is unambiguous
/// (unlike same-name Drive duplicates, which share a path). [onChanged] is
/// called after any deletion so the caller can refresh the pane.
Future<void> showDedupeDialog(
  BuildContext context, {
  required RcloneClient client,
  required String fs,
  required String label,
  required String basePath,
  required Future<void> Function() onChanged,
}) => showDialog<void>(
  context: context,
  // Closed only via the (busy-guarded) X — never scrim-tap mid-delete.
  barrierDismissible: false,
  builder: (_) => _DedupeDialog(
    client: client,
    fs: fs,
    label: label,
    basePath: basePath,
    onChanged: onChanged,
  ),
);

class _DedupeDialog extends StatefulWidget {
  const _DedupeDialog({
    required this.client,
    required this.fs,
    required this.label,
    required this.basePath,
    required this.onChanged,
  });
  final RcloneClient client;
  final String fs;
  final String label;
  final String basePath;
  final Future<void> Function() onChanged;

  @override
  State<_DedupeDialog> createState() => _DedupeDialogState();
}

class _DedupeDialogState extends State<_DedupeDialog> {
  bool _scanning = false;
  bool _deleting = false;
  String? _error;
  String? _status;
  List<DupGroup>? _groups;

  /// Per-group index of the copy to KEEP (default 0); the rest are deleted.
  final _keep = <int, int>{};

  /// Groups the user opted out of (keep every copy).
  final _skip = <int>{};

  int _gen = 0;

  Future<void> _scan() async {
    final g = ++_gen;
    setState(() {
      _scanning = true;
      _error = null;
      _status = null;
      _groups = null;
      _keep.clear();
      _skip.clear();
    });
    try {
      final res = await widget.client.rpc('operations/list', {
        'fs': widget.fs,
        'remote': widget.basePath,
        'opt': {'recurse': true, 'showHash': true, 'noModTime': true},
      });
      if (g != _gen || !mounted) return;
      final files = <DupFile>[];
      for (final item in (res['list'] as List? ?? const [])) {
        final f = DupFile.fromJson((item as Map).cast<String, dynamic>());
        if (f != null) files.add(f);
      }
      final groups = findDuplicateGroups(files);
      setState(() {
        _scanning = false;
        _groups = groups;
      });
    } catch (e) {
      if (g != _gen || !mounted) return;
      setState(() {
        _scanning = false;
        _error = e is RcloneException ? e.message : '$e';
      });
    }
  }

  /// The copies queued for deletion across all non-skipped groups.
  List<DupFile> _targets() {
    final groups = _groups ?? const [];
    final out = <DupFile>[];
    for (var gi = 0; gi < groups.length; gi++) {
      if (_skip.contains(gi)) continue;
      final keep = _keep[gi] ?? 0;
      final files = groups[gi].files;
      for (var fi = 0; fi < files.length; fi++) {
        if (fi != keep) out.add(files[fi]);
      }
    }
    return out;
  }

  Future<void> _delete() async {
    final targets = _targets();
    if (targets.isEmpty) return;
    final ok = await _confirm(targets.length);
    if (!ok || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
      _status = null;
    });
    var done = 0;
    var failed = 0;
    String? firstError;
    for (final t in targets) {
      try {
        final remote = widget.basePath.isEmpty
            ? t.path
            : '${widget.basePath}/${t.path}';
        await widget.client.rpc('operations/deletefile', {
          'fs': widget.fs,
          'remote': remote,
        });
        done++;
      } catch (e) {
        failed++;
        firstError ??= e is RcloneException ? e.message : '$e';
      }
    }
    // Pane refresh is best-effort — never let it strand the dialog as busy.
    try {
      await widget.onChanged();
    } catch (_) {
      /* ignore */
    }
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _status = failed == 0
          ? 'Deleted $done duplicate ${done == 1 ? 'copy' : 'copies'}.'
          : 'Deleted $done; $failed could not be removed'
                '${firstError != null ? ' ($firstError)' : ''}.';
    });
    await _scan(); // re-scan so the list reflects what's left
  }

  Future<bool> _confirm(int n) async {
    final c = AircloneTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surfaceRaised,
        title: const Text('Delete duplicates?'),
        content: Text(
          'Permanently delete $n duplicate ${n == 1 ? 'copy' : 'copies'}? '
          'One copy of each file is kept. This cannot be undone.',
          style: TextStyle(color: c.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete $n'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final busy = _scanning || _deleting;
    return PopScope(
      // Block Escape/back while a scan or delete is in flight.
      canPop: !busy,
      child: Dialog(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: SizedBox(
          width: 640,
          height: 560,
          child: Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.content_copy_outlined,
                      size: 18,
                      color: c.primary,
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Text(
                        'Find duplicates in ${widget.label}',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                      color: c.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: Space.x1),
                Text(
                  'Matches files with identical content (size + hash). Remotes '
                  'that expose no file hashes can’t be scanned.',
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                ),
                const SizedBox(height: Space.x3),
                Expanded(child: _body(c)),
                const SizedBox(height: Space.x2),
                _footer(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AircloneColors c) {
    if (_scanning) {
      return _centered(c, spinner: true, text: 'Scanning… (computing hashes)');
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
      );
    }
    final groups = _groups;
    if (groups == null) {
      return _centered(c, text: 'Scan this folder to find duplicate files.');
    }
    if (groups.isEmpty) {
      return _centered(c, text: 'No duplicates found. 🎉');
    }
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (_, gi) => _groupTile(c, groups[gi], gi),
    );
  }

  Widget _groupTile(AircloneColors c, DupGroup g, int gi) {
    final keep = _keep[gi] ?? 0;
    final skipped = _skip.contains(gi);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.x2),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${g.files.length} copies · ${humanSize(g.size)} each · '
                    '${humanSize(g.reclaimable)} reclaimable',
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    skipped ? _skip.remove(gi) : _skip.add(gi);
                  }),
                  child: Text(
                    skipped ? 'Include' : 'Skip group',
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          for (var fi = 0; fi < g.files.length; fi++)
            _fileRow(c, g, gi, fi, keep, skipped),
          const SizedBox(height: Space.x1),
        ],
      ),
    );
  }

  Widget _fileRow(
    AircloneColors c,
    DupGroup g,
    int gi,
    int fi,
    int keep,
    bool skipped,
  ) {
    final f = g.files[fi];
    final isKeep = fi == keep;
    final willDelete = !skipped && !isKeep;
    return InkWell(
      onTap: skipped ? null : () => setState(() => _keep[gi] = fi),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 3),
        child: Row(
          children: [
            // Tap the row to choose the copy to keep; this is the indicator.
            Padding(
              padding: const EdgeInsets.only(right: Space.x2),
              child: Icon(
                isKeep
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: skipped
                    ? c.textFaint
                    : (isKeep ? c.primary : c.textMuted),
              ),
            ),
            Expanded(
              child: Text(
                f.path,
                style: TextStyle(
                  color: willDelete ? c.textFaint : c.text,
                  fontSize: 12,
                  decoration: willDelete ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Space.x2),
            Text(
              isKeep ? 'keep' : (skipped ? '' : 'delete'),
              style: TextStyle(
                color: isKeep ? c.success : c.error,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(AircloneColors c) {
    final groups = _groups;
    final targets = groups == null ? const <DupFile>[] : _targets();
    final reclaim = targets.fold<int>(0, (s, f) => s + f.size);
    return Row(
      children: [
        if (_status != null)
          Expanded(
            child: Text(
              _status!,
              style: TextStyle(color: c.success, fontSize: 12),
            ),
          )
        else if (groups != null && groups.isNotEmpty)
          Expanded(
            child: Text(
              '${targets.length} marked · ${humanSize(reclaim)} to free',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          )
        else
          const Spacer(),
        OutlinedButton(
          onPressed: (_scanning || _deleting) ? null : _scan,
          child: Text(groups == null ? 'Scan' : 'Re-scan'),
        ),
        const SizedBox(width: Space.x2),
        FilledButton(
          onPressed: (_deleting || _scanning || targets.isEmpty)
              ? null
              : _delete,
          child: _deleting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Delete ${targets.length}'),
        ),
      ],
    );
  }

  Widget _centered(
    AircloneColors c, {
    bool spinner = false,
    required String text,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner) ...[
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: Space.x3),
          ],
          Text(text, style: TextStyle(color: c.textFaint, fontSize: 12)),
        ],
      ),
    );
  }
}
