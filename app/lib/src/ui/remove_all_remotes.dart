import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/config_transfer_controller.dart';
import '../state/remotes_provider.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// Confirm and then remove EVERY configured remote.
///
/// The sidebar's per-remote delete is right for a mistake and useless for a
/// clean slate: starting over meant sixteen separate confirmations, in a list
/// where several names differ only in their last two characters. This is the
/// bulk form — and because it is the most destructive thing the app can do to a
/// config, it asks for an acknowledgement rather than just a red button, and it
/// says up front that a backup is taken first.
Future<void> showRemoveAllRemotesDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  // Configured remotes only: the synthetic "This device" peer is not in the
  // config and cannot be deleted from it.
  final names = <String>[
    for (final r in ref.read(remotesProvider).valueOrNull ?? const <Remote>[])
      if (!r.isLocal) r.name,
  ];
  if (names.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('There are no remotes to remove.')),
    );
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _ConfirmRemoveAll(names: names),
  );
  if (confirmed != true || !context.mounted) return;

  final ({List<String> deleted, List<({String name, String error})> failed})
  result;
  try {
    result = await ref
        .read(configTransferControllerProvider)
        .removeAllRemotes();
  } on ConfigTransferError catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  // A pane still pointing at a remote that no longer exists would keep showing
  // its last listing and fail every action taken on it.
  for (final p in [browserAProvider, browserBProvider]) {
    if (ref.read(p).remote != null && !ref.read(p).remote!.isLocal) {
      ref.read(p.notifier).clear();
    }
  }
  if (!context.mounted) return;
  final failed = result.failed.length;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        failed == 0
            ? 'Removed ${result.deleted.length} remote(s). A backup of your '
                  'config was saved first.'
            : 'Removed ${result.deleted.length}, but $failed could not be '
                  'removed: ${result.failed.map((f) => f.name).join(', ')}',
      ),
    ),
  );
}

class _ConfirmRemoveAll extends StatefulWidget {
  const _ConfirmRemoveAll({required this.names});
  final List<String> names;

  @override
  State<_ConfirmRemoveAll> createState() => _ConfirmRemoveAllState();
}

class _ConfirmRemoveAllState extends State<_ConfirmRemoveAll> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final n = widget.names.length;
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      title: Text(
        'Remove all $n remotes?',
        style: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: DialogBody(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This empties your rclone config. Files stored on those remotes '
              'are not touched — but their credentials, paths and encryption '
              'settings are, and for an encrypted remote those settings are '
              'what makes its contents readable.',
              style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: Space.x3),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              width: double.infinity,
              padding: const EdgeInsets.all(Space.x2),
              decoration: BoxDecoration(
                color: c.surfaceSunken,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: Text(
                    widget.names.join('\n'),
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.x3),
            Text(
              'A copy of your config is saved to the backups folder first, so '
              'this can be undone from Settings → Config → Restore.',
              style: TextStyle(color: c.textFaint, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: Space.x2),
            InkWell(
              onTap: () => setState(() => _acknowledged = !_acknowledged),
              borderRadius: BorderRadius.circular(Radii.sm),
              child: Row(
                children: [
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: Checkbox(
                      value: _acknowledged,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) =>
                          setState(() => _acknowledged = v ?? false),
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      'I understand this removes every remote.',
                      style: TextStyle(color: c.text, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: c.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.error),
          // Deliberately inert until acknowledged: this is one click away from
          // an empty config, and a red button alone is not a decision.
          onPressed: _acknowledged
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text('Remove all $n'),
        ),
      ],
    );
  }
}
