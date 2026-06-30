import 'package:flutter/material.dart';

import 'theme/tokens.dart';

const _groups = <(String, List<(String, String)>)>[
  (
    'Navigate',
    [
      ('Ctrl + K', 'Command palette'),
      ('Alt + ←', 'Back'),
      ('Alt + →', 'Forward'),
      ('Alt + ↑', 'Up a folder'),
      ('Ctrl + F', 'Filter the list'),
      ('type…', 'Jump to a name'),
    ],
  ),
  (
    'Tabs & panes',
    [
      ('Ctrl + T', 'New tab'),
      ('Ctrl + W', 'Close tab'),
      ('Ctrl + I', 'Toggle details'),
    ],
  ),
  (
    'Select',
    [
      ('Ctrl + A', 'Select all'),
      ('Esc', 'Clear selection'),
      ('Enter', 'Open folder / preview file'),
      ('Space', 'Quick Look'),
    ],
  ),
  (
    'Edit',
    [
      ('F2', 'Rename'),
      ('Del', 'Delete'),
      ('Ctrl + C', 'Copy'),
      ('Ctrl + X', 'Cut'),
      ('Ctrl + V', 'Paste'),
    ],
  ),
];

/// A read-only cheat-sheet of the Explorer keyboard shortcuts (opened with F1).
Future<void> showShortcutsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ShortcutsDialog(),
);

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.keyboard_outlined, size: 20, color: c.primary),
                  const SizedBox(width: Space.x2),
                  Text(
                    'Keyboard shortcuts',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    color: c.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: Space.x3),
              Wrap(
                spacing: Space.x6,
                runSpacing: Space.x4,
                children: [
                  for (final (title, rows) in _groups)
                    SizedBox(width: 220, child: _group(c, title, rows)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(AircloneColors c, String title, List<(String, String)> rows) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: c.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: Space.x2),
          for (final (key, desc) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceSunken,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      key,
                      style: TextStyle(color: c.textMuted, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      desc,
                      style: TextStyle(color: c.text, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}
