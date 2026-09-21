/// The manual path: every option rclone has, exactly as before.
///
/// This is deliberately almost unchanged. People who came here chose it over
/// the guide, and the one real complaint about it was finding anything at all —
/// s3 has 78 options and `endpoint` is somewhere in the middle of them. So it
/// gains a filter box and nothing else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:airclone_rc/airclone_rc.dart';

import '../../state/add_remote_controller.dart';
import '../disclosure.dart';
import '../theme/tokens.dart';
import 'fields.dart';

class AdvancedForm extends ConsumerWidget {
  const AdvancedForm({super.key, required this.onSubmit});

  /// Save/create. Lives outside this widget because editing a `crypt` password
  /// has to be confirmed first, and that is the dialog's business.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(addRemoteControllerProvider);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final p = state.provider;
    if (p == null) return const SizedBox.shrink();

    final filter = state.optionFilter.toLowerCase();
    bool visible(ProviderOption o) =>
        filter.isEmpty ||
        o.name.toLowerCase().contains(filter) ||
        o.help.toLowerCase().contains(filter);

    final standard = p.standardOptions.where(visible).toList();
    final advanced = p.advancedOptions.where(visible).toList();

    return Column(
      children: [
        TextEntry(
          key: const ValueKey('option-filter'),
          initial: state.optionFilter,
          hint: 'Filter options…',
          onChanged: ctrl.setOptionFilter,
        ),
        const SizedBox(height: Space.x3),
        Expanded(
          child: ListView(
            children: [
              // The name is not an rclone option, so the filter leaves it
              // alone: hiding the one field a new remote cannot be created
              // without would be a bug, not a filter.
              LabeledField(
                label: 'Name',
                help: state.isEdit
                    ? 'The remote name (fixed while editing).'
                    : 'A short name for this remote (e.g. my-drive).',
                child: state.isEdit
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          state.name,
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : TextEntry(
                        initial: state.name,
                        hint: 'my-remote',
                        onChanged: ctrl.setName,
                      ),
              ),
              for (final o in standard)
                _OptionField(key: ValueKey('option-row-${o.name}'), option: o),
              if (advanced.isNotEmpty)
                Disclosure(
                  label: 'Advanced',
                  // A filter that matches only advanced options opens the
                  // section, so the results are not hidden behind a collapsed
                  // header that looks like "no matches".
                  expanded: state.showAdvanced || filter.isNotEmpty,
                  onToggle: ctrl.toggleAdvanced,
                  children: [for (final o in advanced) _OptionField(option: o)],
                ),
              if (standard.isEmpty && advanced.isEmpty && filter.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x4),
                  child: Text(
                    'No option matches "${state.optionFilter}".',
                    style: TextStyle(color: c.textFaint, fontSize: 12),
                  ),
                ),
              if (state.error != null) ...[
                const SizedBox(height: Space.x2),
                Text(
                  state.error!,
                  style: TextStyle(color: c.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.x3),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: onSubmit,
              child: Text(state.isEdit ? 'Save changes' : 'Create remote'),
            ),
          ],
        ),
      ],
    );
  }
}

class _OptionField extends ConsumerWidget {
  const _OptionField({super.key, required this.option});

  final ProviderOption option;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addRemoteControllerProvider);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final o = option;
    final value = state.values[o.name] ?? '';

    final Widget input;
    final key = ValueKey('option-${o.name}');
    if (o.isBool) {
      input = BoolEntry(
        key: key,
        value: value == 'true',
        onChanged: (b) => ctrl.setValue(o.name, '$b'),
      );
    } else if (o.isSelect) {
      input = SelectEntry(
        key: key,
        value: value,
        options: o.examples,
        exclusive: o.exclusive,
        onChanged: (v) => ctrl.setValue(o.name, v),
      );
    } else {
      input = TextEntry(
        key: key,
        initial: value,
        obscure: o.isPassword,
        keyboardNumber: o.isInt,
        hint: o.defaultStr,
        onChanged: (v) => ctrl.setValue(o.name, v),
      );
    }
    return LabeledField(
      label: o.name + (o.required ? ' *' : ''),
      help: (state.isEdit && o.isPassword)
          ? (o.summary.isEmpty
                ? 'Leave blank to keep the current password.'
                : '${o.summary} Leave blank to keep current.')
          : o.summary,
      child: input,
    );
  }
}
