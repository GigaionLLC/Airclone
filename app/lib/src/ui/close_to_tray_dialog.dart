import 'package:flutter/material.dart';

/// The answer to "keep running in the tray?" (#54).
enum CloseToTrayAnswer {
  /// Hide the window and keep going; remember it.
  keepRunning,

  /// Quit as before; remember it.
  quit,

  /// Dismissed: neither close nor remember anything.
  cancel,
}

/// Asked once, the first time the window is closed while transfers are
/// running and the user has never chosen what closing should do. The answer
/// is saved (Settings > Tray changes it later), so this never shows again.
///
/// Lives apart from `app.dart` so it can be widget-tested without the whole
/// application.
Future<CloseToTrayAnswer> askCloseToTray(
  BuildContext context, {
  required String activity,
}) async {
  final answer = await showDialog<CloseToTrayAnswer>(
    context: context,
    barrierDismissible: false,
    builder: (dctx) => AlertDialog(
      title: const Text('Keep Airclone running in the tray?'),
      content: Text(
        '$activity. Airclone can keep working in the tray when you close the '
        'window: transfers, mounted drives and scheduled tasks carry on, and '
        'you quit from the tray icon. Or it can quit now, which stops them.\n\n'
        'You can change this later in Settings > Tray.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, CloseToTrayAnswer.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dctx, CloseToTrayAnswer.quit),
          child: const Text('Quit Airclone'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dctx, CloseToTrayAnswer.keepRunning),
          child: const Text('Keep running in the tray'),
        ),
      ],
    ),
  );
  return answer ?? CloseToTrayAnswer.cancel;
}
