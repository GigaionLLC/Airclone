import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/provider.dart';
import '../state/add_remote_controller.dart';
import '../state/providers_provider.dart';
import 'theme/tokens.dart';

Future<void> showAddRemoteDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const AddRemoteDialog());

class AddRemoteDialog extends ConsumerStatefulWidget {
  const AddRemoteDialog({super.key});

  @override
  ConsumerState<AddRemoteDialog> createState() => _AddRemoteDialogState();
}

class _AddRemoteDialogState extends ConsumerState<AddRemoteDialog> {
  String _filter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(addRemoteControllerProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(addRemoteControllerProvider);

    ref.listen(addRemoteControllerProvider, (prev, next) {
      if (next.phase == AddPhase.done && mounted) Navigator.of(context).pop();
    });

    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: 520,
        height: 560,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: switch (state.phase) {
            AddPhase.pickProvider => _buildPicker(c),
            AddPhase.creating => const Center(
              child: CircularProgressIndicator(),
            ),
            AddPhase.error => _buildError(c, state),
            _ => _buildForm(c, state),
          },
        ),
      ),
    );
  }

  Widget _header(AircloneColors c, String title, {String? subtitle}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: c.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: Space.x1),
        Text(subtitle, style: TextStyle(color: c.textMuted, fontSize: 13)),
      ],
      const SizedBox(height: Space.x4),
    ],
  );

  Widget _buildPicker(AircloneColors c) {
    final providers = ref.watch(providersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          c,
          'Add a remote',
          subtitle: 'Choose a storage type to connect.',
        ),
        TextField(
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: 'Search storage types…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          onChanged: (v) => setState(() => _filter = v.toLowerCase()),
        ),
        const SizedBox(height: Space.x3),
        Expanded(
          child: providers.when(
            data: (list) {
              final filtered = list
                  .where(
                    (p) =>
                        _filter.isEmpty ||
                        p.name.toLowerCase().contains(_filter) ||
                        p.description.toLowerCase().contains(_filter),
                  )
                  .toList();
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => _providerTile(c, filtered[i]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('$e', style: TextStyle(color: c.error)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _providerTile(AircloneColors c, RcloneProvider p) => InkWell(
    onTap: () => ref.read(addRemoteControllerProvider.notifier).pickProvider(p),
    borderRadius: BorderRadius.circular(Radii.md),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x2,
        vertical: Space.x3,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_outlined, size: 20, color: c.primary),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  p.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: c.textFaint),
        ],
      ),
    ),
  );

  Widget _buildForm(AircloneColors c, AddRemoteState state) {
    final p = state.provider;
    final question = state.phase == AddPhase.question ? state.question : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => ref
                  .read(addRemoteControllerProvider.notifier)
                  .backToProviders(),
              icon: const Icon(Icons.arrow_back, size: 18),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: Space.x1),
            Expanded(
              child: Text(
                question != null
                    ? 'Configure ${p?.name ?? ''}'
                    : 'Set up ${p?.name ?? ''}',
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        Expanded(
          child: question != null
              ? _buildQuestion(c, state, question)
              : _buildFields(c, state, p!),
        ),
      ],
    );
  }

  Widget _buildFields(
    AircloneColors c,
    AddRemoteState state,
    RcloneProvider p,
  ) {
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              _LabeledField(
                label: 'Name',
                help: 'A short name for this remote (e.g. my-drive).',
                child: _TextEntry(
                  initial: state.name,
                  hint: 'my-remote',
                  onChanged: ctrl.setName,
                ),
              ),
              for (final o in p.standardOptions)
                _optionField(c, state, o, ctrl),
              if (p.advancedOptions.isNotEmpty)
                _AdvancedSection(
                  expanded: state.showAdvanced,
                  onToggle: ctrl.toggleAdvanced,
                  children: [
                    for (final o in p.advancedOptions)
                      _optionField(c, state, o, ctrl),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.x3),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: ctrl.submit,
              child: const Text('Create remote'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _optionField(
    AircloneColors c,
    AddRemoteState state,
    ProviderOption o,
    AddRemoteController ctrl,
  ) {
    final value = state.values[o.name] ?? '';
    final Widget input;
    if (o.isBool) {
      input = _BoolEntry(
        value: value == 'true',
        onChanged: (b) => ctrl.setValue(o.name, '$b'),
      );
    } else if (o.isSelect) {
      input = _SelectEntry(
        value: value,
        options: o.examples,
        exclusive: o.exclusive,
        onChanged: (v) => ctrl.setValue(o.name, v),
      );
    } else {
      input = _TextEntry(
        initial: value,
        obscure: o.isPassword,
        keyboardNumber: o.isInt,
        hint: o.defaultStr,
        onChanged: (v) => ctrl.setValue(o.name, v),
      );
    }
    return _LabeledField(
      label: o.name + (o.required ? ' *' : ''),
      help: o.summary,
      child: input,
    );
  }

  Widget _buildQuestion(
    AircloneColors c,
    AddRemoteState state,
    ProviderOption q,
  ) {
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q.summary.isEmpty ? q.name : q.summary,
          style: TextStyle(
            color: c.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (q.help.contains('\n')) ...[
          const SizedBox(height: Space.x2),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                q.help,
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
          ),
        ] else
          const Spacer(),
        const SizedBox(height: Space.x3),
        if (q.isBool)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => ctrl.answer('false'),
                child: const Text('No'),
              ),
              const SizedBox(width: Space.x2),
              FilledButton(
                onPressed: () => ctrl.answer('true'),
                child: const Text('Yes'),
              ),
            ],
          )
        else
          _QuestionTextAnswer(option: q, onSubmit: ctrl.answer),
      ],
    );
  }

  Widget _buildError(AircloneColors c, AddRemoteState state) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.error_outline, size: 40, color: c.error),
      const SizedBox(height: Space.x3),
      Text(
        "Couldn't create the remote",
        style: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: Space.x2),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        child: Text(
          state.error ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
      ),
      const SizedBox(height: Space.x4),
      FilledButton(
        onPressed: () =>
            ref.read(addRemoteControllerProvider.notifier).backToProviders(),
        child: const Text('Start over'),
      ),
    ],
  );
}

// ── small field widgets ───────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  const _LabeledField({
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

class _TextEntry extends StatefulWidget {
  const _TextEntry({
    required this.initial,
    required this.onChanged,
    this.hint = '',
    this.obscure = false,
    this.keyboardNumber = false,
  });
  final String initial;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool obscure;
  final bool keyboardNumber;

  @override
  State<_TextEntry> createState() => _TextEntryState();
}

class _TextEntryState extends State<_TextEntry> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      obscureText: widget.obscure,
      keyboardType: widget.keyboardNumber ? TextInputType.number : null,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _BoolEntry extends StatelessWidget {
  const _BoolEntry({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Switch(value: value, onChanged: onChanged),
  );
}

class _SelectEntry extends StatelessWidget {
  const _SelectEntry({
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
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final items = options
        .map(
          (e) => DropdownMenuItem(
            value: e.value,
            child: Text(
              e.value.isEmpty ? '(default)' : e.value,
              style: TextStyle(color: c.text, fontSize: 13),
            ),
          ),
        )
        .toList();
    final current = options.any((e) => e.value == value) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      items: items,
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _QuestionTextAnswer extends StatefulWidget {
  const _QuestionTextAnswer({required this.option, required this.onSubmit});
  final ProviderOption option;
  final ValueChanged<String> onSubmit;

  @override
  State<_QuestionTextAnswer> createState() => _QuestionTextAnswerState();
}

class _QuestionTextAnswerState extends State<_QuestionTextAnswer> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _c,
            obscureText: widget.option.isPassword,
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.option.defaultStr,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.x2),
        FilledButton(
          onPressed: () => widget.onSubmit(_c.text),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.expanded,
    required this.onToggle,
    required this.children,
  });
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x2),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: c.textMuted,
                ),
                const SizedBox(width: Space.x1),
                Text(
                  'Advanced',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...children,
      ],
    );
  }
}
