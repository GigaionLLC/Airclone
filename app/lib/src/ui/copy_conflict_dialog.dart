import 'package:flutter/material.dart';

import '../state/name_conflict.dart';
import 'theme/tokens.dart';

/// Asks how to handle [collisions] of [total] pasted items that already exist
/// at the destination. Returns the chosen [ConflictChoice] (or
/// [ConflictChoice.cancel] if dismissed).
Future<ConflictChoice> showCopyConflictDialog(
  BuildContext context, {
  required List<String> collisions,
  required int total,
}) async {
  final c = AircloneTheme.of(context);
  final n = collisions.length;
  final choice = await showDialog<ConflictChoice>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: Text('$n of $total already exist here'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These items have the same name as something in this folder:',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const SizedBox(height: Space.x2),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                color: c.surfaceSunken,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final name in collisions)
                      Text(
                        name,
                        style: TextStyle(color: c.text, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictChoice.cancel),
          child: Text('Cancel', style: TextStyle(color: c.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictChoice.skip),
          child: const Text('Skip these'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ConflictChoice.overwrite),
          child: Text('Replace', style: TextStyle(color: c.error)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ConflictChoice.keepBoth),
          child: const Text('Keep both'),
        ),
      ],
    ),
  );
  return choice ?? ConflictChoice.cancel;
}
