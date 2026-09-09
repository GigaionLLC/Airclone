import 'package:flutter/material.dart';

import '../rclone/models/remote.dart';
import 'destination_picker.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// One end of a transfer: a remote plus a path inside it.
typedef FolderRef = ({Remote remote, String path});

/// Both ends, once the user has chosen them.
typedef FromTo = ({FolderRef src, FolderRef dst});

/// Asks for a source and a destination folder, independent of the browser panes.
///
/// Saving a task used to require a dual-pane layout arranged in advance: the
/// source was read from the active pane and the destination from the other one,
/// and it refused outright if either was empty. That made a feature depend on a
/// layout, and made it impossible on any shell that has no second pane — which
/// is every phone.
///
/// The panes are still the fast path: pass what they hold as [src] / [dst] and
/// they arrive pre-filled. They are no longer a prerequisite.
///
/// Resolves to both ends, or null if cancelled.
Future<FromTo?> showFromToPicker(
  BuildContext context, {
  FolderRef? src,
  FolderRef? dst,
}) => showDialog<FromTo?>(
  context: context,
  builder: (_) => _FromToDialog(initialSrc: src, initialDst: dst),
);

/// How a chosen folder reads back to the user: `remote:path`, or just `remote:`
/// at the root. Same shape the task list and the transfer dialog use, so the
/// string does not change meaning between screens.
String folderRefLabel(FolderRef f) => '${f.remote.name}:${f.path}';

class _FromToDialog extends StatefulWidget {
  const _FromToDialog({this.initialSrc, this.initialDst});
  final FolderRef? initialSrc;
  final FolderRef? initialDst;

  @override
  State<_FromToDialog> createState() => _FromToDialogState();
}

class _FromToDialogState extends State<_FromToDialog> {
  FolderRef? _src;
  FolderRef? _dst;

  @override
  void initState() {
    super.initState();
    _src = widget.initialSrc;
    _dst = widget.initialDst;
  }

  /// True when both ends name the same folder on the same remote.
  ///
  /// Blocked rather than warned about: for Sync it would be a no-op at best and
  /// for Move it is a request to move a folder into itself. Neither is anything
  /// a user meant to schedule.
  bool get _same =>
      _src != null &&
      _dst != null &&
      _src!.remote.fs == _dst!.remote.fs &&
      _src!.path == _dst!.path;

  bool get _ready => _src != null && _dst != null && !_same;

  Future<void> _pick({required bool source}) async {
    final picked = await showDestinationPicker(
      context,
      title: source ? 'Choose the source folder' : 'Choose the destination',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (source) {
        _src = picked;
      } else {
        _dst = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: const Text('New task'),
      content: DialogBody(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EndRow(
              label: 'From',
              icon: Icons.upload_file,
              value: _src,
              onPick: () => _pick(source: true),
            ),
            const SizedBox(height: Space.x2),
            Icon(Icons.arrow_downward, size: 16, color: c.textFaint),
            const SizedBox(height: Space.x2),
            _EndRow(
              label: 'To',
              icon: Icons.folder_open,
              value: _dst,
              onPick: () => _pick(source: false),
            ),
            if (_same) ...[
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 14, color: c.error),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      'The source and the destination are the same folder.',
                      style: TextStyle(color: c.error, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _ready
              ? () => Navigator.of(context).pop((src: _src!, dst: _dst!))
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

/// One end of the picker: its label, what is currently chosen, and the button
/// that changes it.
class _EndRow extends StatelessWidget {
  const _EndRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onPick,
  });

  final String label;
  final IconData icon;
  final FolderRef? value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final chosen = value != null;
    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: chosen ? c.primary : c.textFaint),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.textFaint,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chosen ? folderRefLabel(value!) : 'Not chosen yet',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: chosen ? c.text : c.textFaint,
                    fontSize: 12,
                    fontStyle: chosen ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          TextButton(
            onPressed: onPick,
            child: Text(chosen ? 'Change' : 'Choose…'),
          ),
        ],
      ),
    );
  }
}
