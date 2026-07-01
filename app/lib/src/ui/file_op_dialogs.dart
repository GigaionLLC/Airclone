import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// Compact, themed dialogs for the browser's quick file operations
/// (new folder / rename / delete). Each returns a Future the caller awaits to
/// learn the user's choice; none of them touch rclone directly.

/// Prompts for a new folder name. Resolves to the trimmed name, or `null` when
/// the user cancels or submits an empty value.
Future<String?> showNewFolderDialog(
  BuildContext context, {
  Set<String> taken = const {},
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(
    title: 'New folder',
    hint: 'Folder name',
    confirmLabel: 'Create',
    taken: taken,
  ),
);

/// Prompts to rename an entry, prefilled with [currentName]. Resolves to the
/// trimmed new name, or `null` when cancelled or unchanged/empty. [taken] is the
/// set of sibling names (excluding [currentName]); submitting a name already in
/// it is blocked inline so a rename can never silently overwrite another entry.
Future<String?> showRenameDialog(
  BuildContext context,
  String currentName, {
  Set<String> taken = const {},
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(
    title: 'Rename',
    hint: 'New name',
    confirmLabel: 'Rename',
    initial: currentName,
    taken: taken,
  ),
);

/// Asks the user to confirm deleting [label]. When [isDir] is true the copy
/// warns that the folder's contents go too. Resolves to `true` on confirm.
Future<bool> showDeleteConfirm(
  BuildContext context,
  String label, {
  bool isDir = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = AircloneTheme.of(ctx);
      return AlertDialog(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        title: Text(
          'Delete "$label"?',
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          isDir
              ? 'This permanently deletes the folder and everything inside it. '
                    'This cannot be undone.'
              : 'This permanently deletes the file. This cannot be undone.',
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          Space.x4,
          0,
          Space.x4,
          Space.x4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: c.textMuted)),
          ),
          const SizedBox(width: Space.x1),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.error,
              foregroundColor: c.onPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Shared single-text-field dialog used by the new-folder and rename flows.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.initial = '',
    this.taken = const {},
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final String initial;

  /// Names that already exist at the destination; submitting one is blocked.
  final Set<String> taken;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _error;

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      Navigator.of(context).pop(null);
      return;
    }
    // Block a name that already exists at the target (unchanged rename is fine).
    if (value != widget.initial && widget.taken.contains(value)) {
      setState(
        () => _error = 'A file or folder named "$value" already exists here.',
      );
      return;
    }
    Navigator.of(context).pop(value);
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
        widget.title,
        style: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          style: TextStyle(color: c.text, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            errorText: _error,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.x4,
        0,
        Space.x4,
        Space.x4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: c.textMuted)),
        ),
        const SizedBox(width: Space.x1),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
