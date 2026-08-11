import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import '../state/diagnostics.dart';
import '../state/engine_controller.dart';
import '../state/open_external.dart';
import 'format.dart';
import 'pane_drag.dart';
import 'theme/tokens.dart';

/// Opens [file] (at [parentPath] within [remote]) in another app.
///
/// A local remote hands its real OS path straight over. Anything else is staged
/// first — the bytes stream into the app cache behind a cancellable progress
/// dialog, because no external app can authenticate against the engine's
/// loopback object URL. See [stageForExternalOpen].
///
/// Never throws: engine/transport/chooser failures land in a SnackBar.
Future<void> openFileInAnotherApp(
  BuildContext context,
  WidgetRef ref,
  Remote remote,
  String parentPath,
  RcloneFile file, {
  ExternalOpenMode mode = ExternalOpenMode.view,
}) async {
  if (file.isDir) return;
  final within = joinPath(parentPath, file.name);
  final mime = mimeForName(file.name, fallback: file.mimeType);

  // Local remote: the file already exists on this device, so skip staging
  // entirely — no copy, no wait, works for a 40 GB video.
  if (remote.isLocal) {
    await _handOff(context, '${remote.fs}$within', mime, mode);
    return;
  }

  final client = ref.read(engineControllerProvider).client;
  if (client == null) {
    _toast(context, 'The rclone engine is not running.');
    return;
  }
  final ObjectRef object;
  try {
    object = client.objectRef(remote.fs, within);
  } catch (e) {
    _toast(context, 'Could not locate the file: $e');
    return;
  }

  final staged = await showDialog<_StageOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _StagingDialog(object: object, name: file.name, size: file.size),
  );
  if (staged == null || staged.cancelled) return;
  if (!context.mounted) return;
  final error = staged.error;
  if (error != null) {
    _toast(context, 'Could not download the file: $error');
    return;
  }
  await _handOff(context, staged.path!, mime, mode);
}

Future<void> _handOff(
  BuildContext context,
  String path,
  String mime,
  ExternalOpenMode mode,
) async {
  try {
    await handOffToOs(path, mime: mime, mode: mode);
  } catch (e) {
    logDiagnostic(
      DiagLevel.error,
      'open-external',
      'Hand-off to another app failed (mime $mime)',
      detail: e,
    );
    if (context.mounted) _toast(context, _handOffMessage(e));
  }
}

/// Turns the platform failure into something a user can act on. The Android
/// side reports "no app can open this" and "outside every shareable root" as
/// distinct codes so we don't blame the download for a missing viewer, or show
/// the user a raw FileProvider message they cannot act on.
String _handOffMessage(Object e) {
  final text = e.toString();
  if (text.contains('no_handler')) {
    return 'No app on this device can open this kind of file.';
  }
  if (text.contains('not_shareable')) {
    // handOffToOs already retried via a staged copy; reaching here means the
    // copy itself failed (no space, or the volume went away mid-copy).
    return "Couldn't prepare this file to hand to another app — check there is "
        'free space on this device.';
  }
  return 'Could not open the file in another app: $e';
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

/// Result of the staging dialog: exactly one of [path]/[error] is set unless
/// the user cancelled.
class _StageOutcome {
  const _StageOutcome.done(this.path) : error = null, cancelled = false;
  const _StageOutcome.failed(this.error) : path = null, cancelled = false;
  const _StageOutcome.cancelled() : path = null, error = null, cancelled = true;

  final String? path;
  final Object? error;
  final bool cancelled;
}

/// Modal progress while the object streams into the staging dir. Owns the
/// [ExternalOpenTask] so Cancel stops the download rather than just hiding it.
class _StagingDialog extends StatefulWidget {
  const _StagingDialog({
    required this.object,
    required this.name,
    required this.size,
  });

  final ObjectRef object;
  final String name;

  /// Listing size, used for the progress bar when the server sends no
  /// Content-Length. Negative when rclone didn't report one.
  final int size;

  @override
  State<_StagingDialog> createState() => _StagingDialogState();
}

class _StagingDialogState extends State<_StagingDialog> {
  final _task = ExternalOpenTask();
  int _received = 0;
  int? _total;

  @override
  void initState() {
    super.initState();
    _total = widget.size >= 0 ? widget.size : null;
    _run();
  }

  Future<void> _run() async {
    _StageOutcome outcome;
    try {
      final path = await stageForExternalOpen(
        object: widget.object,
        name: widget.name,
        task: _task,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total != null) _total = total;
          });
        },
      );
      outcome = path == null
          ? const _StageOutcome.cancelled()
          : _StageOutcome.done(path);
    } catch (e) {
      outcome = _StageOutcome.failed(e);
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final total = _total;
    // Indeterminate until we know the size; otherwise clamp so a server that
    // over-reports can't drive the bar past 1.0.
    final value = (total == null || total <= 0)
        ? null
        : (_received / total).clamp(0.0, 1.0);
    final detail = total == null || total <= 0
        ? humanSize(_received)
        : '${humanSize(_received)} of ${humanSize(total)}';

    return AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Preparing to open…'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.text, fontSize: 14),
          ),
          const SizedBox(height: Space.x3),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.full),
            child: LinearProgressIndicator(value: value, minHeight: 6),
          ),
          const SizedBox(height: Space.x2),
          Text(detail, style: TextStyle(color: c.textFaint, fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            // The stream loop pops the dialog once it notices; don't pop here
            // or the download would keep running unobserved.
            _task.cancel();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
