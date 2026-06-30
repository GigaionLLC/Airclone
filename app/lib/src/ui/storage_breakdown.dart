import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/browser_controller.dart';
import '../state/file_ops.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// Shows where space goes in the current folder: each subfolder sized via
/// `operations/size`, sorted largest-first with a relative bar.
Future<void> showStorageBreakdown(
  BuildContext context,
  WidgetRef ref,
  int index,
) => showDialog<void>(
  context: context,
  builder: (_) => _StorageBreakdownDialog(index: index),
);

class _Row {
  const _Row(this.name, this.bytes, this.count);
  final String name;
  final int bytes;
  final int count;
}

class _StorageBreakdownDialog extends ConsumerStatefulWidget {
  const _StorageBreakdownDialog({required this.index});
  final int index;
  @override
  ConsumerState<_StorageBreakdownDialog> createState() =>
      _StorageBreakdownDialogState();
}

class _StorageBreakdownDialogState
    extends ConsumerState<_StorageBreakdownDialog> {
  List<_Row>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final state = ref.read(paneProvider(widget.index));
    final remote = state.remote;
    if (remote == null) {
      setState(() => _error = 'No remote open.');
      return;
    }
    final dirs = state.visibleEntries.where((e) => e.isDir).toList();
    final ops = ref.read(fileOpsProvider);
    try {
      final sizes = await Future.wait(
        dirs.map((d) {
          final sub = state.path.isEmpty ? d.name : '${state.path}/${d.name}';
          return ops.folderSize('${remote.fs}$sub');
        }),
      );
      final rows = <_Row>[
        for (var i = 0; i < dirs.length; i++)
          _Row(dirs[i].name, sizes[i].$2, sizes[i].$1),
      ]..sort((a, b) => b.bytes.compareTo(a.bytes));
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final rows = _rows;
    final maxBytes = (rows != null && rows.isNotEmpty && rows.first.bytes > 0)
        ? rows.first.bytes
        : 1;
    final total =
        rows?.fold<int>(0, (s, r) => s + (r.bytes < 0 ? 0 : r.bytes)) ?? 0;
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: const Text('Storage breakdown'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: _error != null
            ? Text(_error!, style: TextStyle(color: c.error, fontSize: 12))
            : rows == null
            ? const Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : rows.isEmpty
            ? Center(
                child: Text(
                  'No subfolders here.',
                  style: TextStyle(color: c.textFaint, fontSize: 12),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rows.length} folders · ${humanSize(total)} total',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: Space.x2),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) => _bar(c, rows[i], maxBytes),
                    ),
                  ),
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

  Widget _bar(AircloneColors c, _Row r, int maxBytes) {
    final frac = maxBytes > 0 && r.bytes > 0
        ? (r.bytes / maxBytes).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 14, color: c.primary),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  r.name,
                  style: TextStyle(color: c.text, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                r.bytes < 0 ? '—' : humanSize(r.bytes),
                style: TextStyle(color: c.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 4,
              backgroundColor: c.surfaceSunken,
              color: c.primary,
            ),
          ),
        ],
      ),
    );
  }
}
