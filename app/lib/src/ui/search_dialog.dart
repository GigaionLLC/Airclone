import 'package:flutter/material.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/rclone_client.dart';
import 'file_icon.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// How many matches to render before collapsing the rest into a "+N more" note.
const _displayCap = 500;

/// Recursive find: lists everything under [basePath] on [remote] (one
/// `operations/list` with `recurse:true`) and filters by name/path. Selecting a
/// result calls [onOpen] — the caller reveals it in the active pane.
Future<void> showSearchDialog(
  BuildContext context, {
  required RcloneClient client,
  required String fs,
  required String label,
  required String basePath,
  required void Function(RcloneFile match) onOpen,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SearchDialog(
    client: client,
    fs: fs,
    label: label,
    basePath: basePath,
    onOpen: onOpen,
  ),
);

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({
    required this.client,
    required this.fs,
    required this.label,
    required this.basePath,
    required this.onOpen,
  });
  final RcloneClient client;
  final String fs;
  final String label;
  final String basePath;
  final void Function(RcloneFile match) onOpen;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _controller = TextEditingController();
  bool _running = false;
  String? _error;
  List<RcloneFile>? _results;
  int _total = 0;

  /// Bumped on each search so a slow scan that returns after the dialog moved
  /// on (or closed) is dropped instead of overwriting newer state.
  int _gen = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return;
    final g = ++_gen;
    setState(() {
      _running = true;
      _error = null;
      _results = null;
    });
    try {
      final res = await widget.client.rpc('operations/list', {
        'fs': widget.fs,
        'remote': widget.basePath,
        // Keep MimeType so result icons classify extensionless files the same
        // way the browser does; only drop modtimes (not shown in results).
        'opt': {'recurse': true, 'noModTime': true},
      });
      if (g != _gen || !mounted) return;
      final tokens = query
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
      // Filter in one pass, holding at most _displayCap matches in memory while
      // still counting the true total — so a query that hits a huge subtree
      // can't balloon the kept list (the cap is a real bound, not just display).
      var total = 0;
      final kept = <RcloneFile>[];
      for (final item in (res['list'] as List? ?? const [])) {
        final f = RcloneFile.fromJson((item as Map).cast<String, dynamic>());
        final hay = '${f.name} ${f.path}'.toLowerCase();
        if (!tokens.every(hay.contains)) continue;
        total++;
        if (kept.length < _displayCap) kept.add(f);
      }
      // Folders first, then by path for a stable, scannable order.
      kept.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      setState(() {
        _running = false;
        _total = total;
        _results = kept;
      });
    } catch (e) {
      if (g != _gen || !mounted) return;
      setState(() {
        _running = false;
        _error = e is RcloneException ? e.message : '$e';
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
      child: SizedBox(
        width: 600,
        height: 520,
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.search, size: 18, color: c.primary),
                  const SizedBox(width: Space.x2),
                  Text(
                    'Search in ${widget.label}',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Name contains…',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  FilledButton(
                    onPressed: (_running || _controller.text.trim().isEmpty)
                        ? null
                        : _search,
                    child: const Text('Search'),
                  ),
                ],
              ),
              const SizedBox(height: Space.x2),
              Text(
                'Scans every file and folder under this location.',
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
              const SizedBox(height: Space.x3),
              Expanded(child: _body(c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(AircloneColors c) {
    if (_running) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: Space.x3),
            Text(
              'Scanning…',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
      );
    }
    final results = _results;
    if (results == null) {
      return Center(
        child: Text(
          'Type a name and press Search.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No matches.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _total > _displayCap
              ? 'Showing first $_displayCap of $_total matches — refine your search.'
              : '$_total ${_total == 1 ? 'match' : 'matches'}',
          style: TextStyle(color: c.textMuted, fontSize: 11),
        ),
        const SizedBox(height: Space.x1),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (_, i) => _row(c, results[i]),
          ),
        ),
      ],
    );
  }

  Widget _row(AircloneColors c, RcloneFile f) {
    // The parent folder of the match, relative to the searched location.
    final slash = f.path.lastIndexOf('/');
    final parent = slash < 0 ? '' : f.path.substring(0, slash);
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        widget.onOpen(f);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x2,
          vertical: Space.x2,
        ),
        child: Row(
          children: [
            Icon(
              iconFor(f),
              size: 18,
              color: f.isDir ? c.warning : c.textMuted,
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    style: TextStyle(color: c.text, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (parent.isNotEmpty)
                    Text(
                      parent,
                      style: TextStyle(color: c.textFaint, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (!f.isDir && f.size >= 0)
              Text(
                humanSize(f.size),
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
