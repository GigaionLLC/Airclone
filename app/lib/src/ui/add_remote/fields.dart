/// The input widgets shared by the guided steps and the advanced form.
///
/// One set, used by both, so a field behaves identically wherever it appears —
/// and so the rule about what gets obscured lives in exactly one place.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:airclone_rc/airclone_rc.dart';

import '../../state/remote_setup_recipes.dart';
import '../theme/tokens.dart';

/// A label, optional help, and the input under them.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.help,
    required this.child,
  });

  final String label;
  final String help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (help.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(help, style: TextStyle(color: c.textFaint, fontSize: 11)),
          ],
          const SizedBox(height: Space.x2),
          child,
        ],
      ),
    );
  }
}

/// A single-line text field. [obscure] hides what is typed, with a reveal.
class TextEntry extends StatefulWidget {
  const TextEntry({
    super.key,
    required this.initial,
    required this.onChanged,
    this.hint = '',
    this.obscure = false,
    this.keyboardNumber = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool obscure;
  final bool keyboardNumber;
  final bool autofocus;
  final VoidCallback? onSubmitted;

  @override
  State<TextEntry> createState() => _TextEntryState();
}

class _TextEntryState extends State<TextEntry> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );
  late bool _hidden = widget.obscure;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      obscureText: _hidden,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardNumber ? TextInputType.number : null,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        // A reveal, because these are pasted far more often than typed and a
        // silently mangled paste is the commonest reason a key "does not work".
        suffixIcon: widget.obscure
            ? IconButton(
                tooltip: _hidden ? 'Show' : 'Hide',
                icon: Icon(
                  _hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted == null
          ? null
          : (_) => widget.onSubmitted!(),
    );
  }
}

/// A yes/no switch.
class BoolEntry extends StatelessWidget {
  const BoolEntry({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Switch(value: value, onChanged: onChanged),
  );
}

/// A picker over an option's own `Examples`.
///
/// When the option is not [ProviderOption.exclusive] rclone will accept a value
/// that is not on the list, so the picker keeps a "Something else" escape and
/// falls back to free text — refusing to accept a legal value would be worse
/// than showing one more control.
class SelectEntry extends StatefulWidget {
  const SelectEntry({
    super.key,
    required this.value,
    required this.options,
    required this.exclusive,
    required this.onChanged,
  });

  final String value;
  final List<OptionExample> options;
  final bool exclusive;
  final ValueChanged<String> onChanged;

  @override
  State<SelectEntry> createState() => _SelectEntryState();
}

class _SelectEntryState extends State<SelectEntry> {
  /// Indices, not values. A string sentinel for "something else" would have to
  /// be a value no backend could ever return, and there is no such string —
  /// rclone examples are arbitrary text. An index cannot collide with one.
  static const int _customIndex = -1;

  late bool _custom =
      !widget.exclusive &&
      widget.value.isNotEmpty &&
      !widget.options.any((e) => e.value == widget.value);

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    if (_custom) {
      // The escape sits BELOW the field rather than beside it. Next to a text
      // field on a phone it does not fit, and a control that is drawn past the
      // screen edge is a control nobody can press.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextEntry(initial: widget.value, onChanged: widget.onChanged),
          TextButton(
            onPressed: () => setState(() => _custom = false),
            child: Text(
              'Choose from list',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ),
        ],
      );
    }
    final items = <DropdownMenuItem<int>>[
      for (var i = 0; i < widget.options.length; i++)
        DropdownMenuItem(
          value: i,
          child: Text(
            widget.options[i].value.isEmpty
                ? '(default)'
                : widget.options[i].value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.text, fontSize: 13),
          ),
        ),
      if (!widget.exclusive)
        DropdownMenuItem(
          value: _customIndex,
          child: Text(
            'Something else...',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
        ),
    ];
    final selected = widget.options.indexWhere((e) => e.value == widget.value);
    return DropdownButtonFormField<int>(
      initialValue: selected < 0 ? null : selected,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      items: items,
      onChanged: (i) {
        if (i == null) return;
        if (i == _customIndex) {
          setState(() => _custom = true);
          return;
        }
        widget.onChanged(widget.options[i].value);
      },
    );
  }
}

/// Picks one of the remotes already configured, plus an optional path inside
/// it — what `crypt` means by "the remote to encrypt".
///
/// A bare text field here is the current reality and it is a trap: the value
/// has to be `name:` or `name:folder`, and getting that wrong produces a remote
/// that lists as empty rather than one that reports an error.
class RemoteEntry extends StatelessWidget {
  const RemoteEntry({
    super.key,
    required this.value,
    required this.remoteNames,
    required this.onChanged,
  });

  final String value;
  final List<String> remoteNames;
  final ValueChanged<String> onChanged;

  /// Splits `name:path` into its two halves.
  static (String, String) split(String raw) {
    final colon = raw.indexOf(':');
    if (colon < 0) return (raw, '');
    return (raw.substring(0, colon), raw.substring(colon + 1));
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final (name, path) = split(value);
    final known = remoteNames.contains(name) ? name : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: known,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Remote',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
            items: [
              for (final n in remoteNames)
                DropdownMenuItem(
                  value: n,
                  child: Text(
                    n,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: 13),
                  ),
                ),
            ],
            onChanged: (v) => onChanged('${v ?? ''}:$path'),
          ),
        ),
        const SizedBox(width: Space.x2),
        Expanded(
          flex: 3,
          child: TextEntry(
            key: ValueKey('path-$known'),
            initial: path,
            hint: 'folder (optional)',
            onChanged: (p) => onChanged('${known ?? name}:$p'),
          ),
        ),
      ],
    );
  }
}

/// Renders one field of a guided [SetupRecipe].
///
/// The recipe decides how it looks; rclone supplies the choices and, when we
/// have written none of our own, the help text.
class RecipeFieldEntry extends StatelessWidget {
  const RecipeFieldEntry({
    super.key,
    required this.field,
    required this.option,
    required this.value,
    required this.remoteNames,
    required this.onChanged,
  });

  final RecipeField field;

  /// rclone's own description of the same option, when it has one.
  final ProviderOption? option;

  final String value;
  final List<String> remoteNames;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final Widget input = switch (field.kind) {
      FieldKind.secret => TextEntry(
        initial: value,
        obscure: true,
        hint: field.hint,
        onChanged: onChanged,
      ),
      FieldKind.number => TextEntry(
        initial: value,
        keyboardNumber: true,
        hint: field.hint.isEmpty ? (option?.defaultStr ?? '') : field.hint,
        onChanged: onChanged,
      ),
      FieldKind.boolean => BoolEntry(
        value: value == 'true',
        onChanged: (b) => onChanged('$b'),
      ),
      FieldKind.choice => SelectEntry(
        value: value,
        options: option?.examples ?? const [],
        exclusive: option?.exclusive ?? false,
        onChanged: onChanged,
      ),
      FieldKind.remote => RemoteEntry(
        value: value,
        remoteNames: remoteNames,
        onChanged: onChanged,
      ),
      FieldKind.text => TextEntry(
        initial: value,
        hint: field.hint,
        onChanged: onChanged,
      ),
    };
    return LabeledField(
      label: field.label + (field.required ? ' *' : ''),
      // Ours when we wrote one; rclone's is written for a terminal.
      help: field.help.isNotEmpty ? field.help : (option?.summary ?? ''),
      child: input,
    );
  }
}

/// A row that shows a value and copies it, for links and commands.
class CopyRow extends StatelessWidget {
  const CopyRow({
    super.key,
    required this.text,
    this.label = 'Copy',
    this.monospace = false,
    this.maxLines = 3,
  });

  final String text;
  final String label;
  final bool monospace;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.x3,
        Space.x2,
        Space.x2,
        Space.x2,
      ),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SelectableText(
              text,
              maxLines: maxLines,
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
          const SizedBox(width: Space.x2),
          IconButton(
            tooltip: label,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_outlined, size: 16),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
        ],
      ),
    );
  }
}
