import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/archive_command.dart';
import '../state/archive_service.dart';
import 'theme/tokens.dart';

/// The result of the Compress dialog: which format, where to save it, and whether
/// to keep the source path prefix inside the archive.
typedef CompressChoice = ({ArchiveFormat format, String dest, bool fullPath});

/// Compress dialog — pick a format, edit the destination (a full `remote:path`
/// string, so cross-remote works by typing another remote), and optionally keep
/// full paths. [initialDest] is a sensible default; [singleSource] gates the
/// full-path toggle (it only makes sense for one source). [what] labels what's
/// being compressed. Returns null if cancelled.
Future<CompressChoice?> showCompressDialog(
  BuildContext context, {
  required String initialDest,
  required String what,
  required bool singleSource,
  ArchiveFormat initialFormat = ArchiveFormat.zip,
}) => showDialog<CompressChoice>(
  context: context,
  builder: (_) => _CompressDialog(
    initialDest: initialDest,
    what: what,
    singleSource: singleSource,
    initialFormat: initialFormat,
  ),
);

class _CompressDialog extends StatefulWidget {
  const _CompressDialog({
    required this.initialDest,
    required this.what,
    required this.singleSource,
    required this.initialFormat,
  });
  final String initialDest;
  final String what;
  final bool singleSource;
  final ArchiveFormat initialFormat;

  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  late ArchiveFormat _format = widget.initialFormat;
  late final TextEditingController _dest = TextEditingController(
    text: widget.initialDest,
  );
  bool _fullPath = false;
  String? _error;

  @override
  void dispose() {
    _dest.dispose();
    super.dispose();
  }

  /// When the format changes, swap the destination's extension to match (only if
  /// it currently ends in a known archive extension, so we never mangle a name
  /// the user typed deliberately).
  void _onFormat(ArchiveFormat f) {
    final old = archiveFormatForName(_dest.text);
    if (old != null) {
      final base = _dest.text.substring(0, _dest.text.length - old.ext.length);
      _dest.text = '$base${f.ext}';
    }
    setState(() => _format = f);
  }

  void _submit() {
    final dest = _dest.text.trim();
    if (dest.isEmpty || !dest.contains(':')) {
      setState(() => _error = 'Enter a destination like remote:path/name.zip');
      return;
    }
    Navigator.of(
      context,
    ).pop((format: _format, dest: dest, fullPath: _fullPath));
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      title: Text(
        'Compress',
        style: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.what,
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
            const SizedBox(height: Space.x4),
            _label(c, 'Format'),
            DropdownButtonFormField<ArchiveFormat>(
              initialValue: _format,
              isDense: true,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
              ),
              items: [
                for (final f in ArchiveFormat.values)
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: (f) => f == null ? null : _onFormat(f),
            ),
            const SizedBox(height: Space.x3),
            _label(c, 'Save archive to'),
            TextField(
              controller: _dest,
              style: TextStyle(color: c.text, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'remote:path/name${_format.ext}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
              ),
            ),
            const SizedBox(height: Space.x1),
            Text(
              'Type any remote here to save to a different one.',
              style: TextStyle(color: c.textFaint, fontSize: 11),
            ),
            if (widget.singleSource) ...[
              const SizedBox(height: Space.x2),
              InkWell(
                onTap: () => setState(() => _fullPath = !_fullPath),
                child: Row(
                  children: [
                    Checkbox(
                      value: _fullPath,
                      onChanged: (v) => setState(() => _fullPath = v ?? false),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Text(
                        'Keep the full source path inside the archive',
                        style: TextStyle(color: c.textMuted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
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
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Compress')),
      ],
    );
  }
}

/// Extract-to dialog — edit the destination folder (a full `remote:path`, so
/// cross-remote works). Returns the dest, or null if cancelled.
Future<String?> showExtractToDialog(
  BuildContext context, {
  required String initialDest,
  required String what,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ExtractToDialog(initialDest: initialDest, what: what),
);

class _ExtractToDialog extends StatefulWidget {
  const _ExtractToDialog({required this.initialDest, required this.what});
  final String initialDest;
  final String what;

  @override
  State<_ExtractToDialog> createState() => _ExtractToDialogState();
}

class _ExtractToDialogState extends State<_ExtractToDialog> {
  late final TextEditingController _dest = TextEditingController(
    text: widget.initialDest,
  );
  String? _error;

  @override
  void dispose() {
    _dest.dispose();
    super.dispose();
  }

  void _submit() {
    final dest = _dest.text.trim();
    if (dest.isEmpty || !dest.contains(':')) {
      setState(() => _error = 'Enter a destination like remote:folder');
      return;
    }
    Navigator.of(context).pop(dest);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      title: Text(
        'Extract to…',
        style: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.what,
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
            const SizedBox(height: Space.x4),
            _label(c, 'Extract into'),
            TextField(
              controller: _dest,
              autofocus: true,
              style: TextStyle(color: c.text, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'remote:folder',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
              ),
            ),
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
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Extract')),
      ],
    );
  }
}

/// Shows an archive's contents (`rclone archive list`) in a scrollable viewer.
Future<void> showArchiveContentsDialog(
  BuildContext context,
  WidgetRef ref, {
  required String archivePath,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ArchiveContentsDialog(archivePath: archivePath),
);

class _ArchiveContentsDialog extends ConsumerStatefulWidget {
  const _ArchiveContentsDialog({required this.archivePath});
  final String archivePath;

  @override
  ConsumerState<_ArchiveContentsDialog> createState() =>
      _ArchiveContentsDialogState();
}

class _ArchiveContentsDialogState
    extends ConsumerState<_ArchiveContentsDialog> {
  String? _contents;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final out = await ref
          .read(archiveServiceProvider)
          .listContents(
            buildArchiveCommand(op: ArchiveOp.list, source: widget.archivePath),
          );
      if (!mounted) return;
      setState(() => _contents = out.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ArchiveError ? e.message : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      title: Text(
        'Archive contents',
        style: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 520,
        height: 360,
        child: _error != null
            ? Text(_error!, style: TextStyle(color: c.error, fontSize: 12))
            : _contents == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : SingleChildScrollView(
                child: SelectableText(
                  _contents!.isEmpty ? '(empty)' : _contents!,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

Widget _label(AircloneColors c, String text) => Padding(
  padding: const EdgeInsets.only(bottom: Space.x1),
  child: Text(
    text,
    style: TextStyle(
      color: c.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  ),
);
