import 'package:flutter/material.dart';

/// Asks whether to go ahead with closing while OS mounts are still live.
///
/// Mounted drives are the one thing closing Airclone takes away from OTHER
/// apps — an editor holding an unsaved file on `X:`, a copy running in
/// Explorer. Disconnecting them silently is the kind of surprise that loses
/// someone's work, so the close stops here first.
///
/// Returns true to continue closing, false to stay open. A dismissed dialog
/// counts as "did not agree" and keeps the app open.
///
/// Lives apart from `app.dart` so it can be widget-tested without standing up
/// the whole application, its providers, and a live engine.
Future<bool> confirmCloseWithMounts(
  BuildContext context,
  List<String> mountPoints,
) async {
  final many = mountPoints.length > 1;
  final points = mountPoints.join(', ');
  final answer = await showDialog<bool>(
    context: context,
    // Deliberately not barrier-dismissible: a stray click outside must not
    // decide something this consequential either way.
    barrierDismissible: false,
    builder: (dctx) => AlertDialog(
      title: Text(
        many
            ? 'Disconnect mounted drives?'
            : 'Disconnect ${mountPoints.first}?',
      ),
      content: Text(
        '$points ${many ? 'are' : 'is'} mounted through Airclone. Closing '
        'disconnects ${many ? 'them' : 'it'} — any app still using '
        '${many ? 'those drives' : 'that drive'} may lose unsaved work.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, false),
          child: const Text('Keep Airclone open'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Disconnect and close'),
        ),
      ],
    ),
  );
  return answer ?? false;
}
