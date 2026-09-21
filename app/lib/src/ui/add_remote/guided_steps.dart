/// The guided path: one screen of essentials, rclone's own questions rendered
/// as real controls, and an honest ending.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:airclone_rc/airclone_rc.dart';

import '../../rclone/models/remote.dart';
import '../../state/add_remote_controller.dart';
import '../../state/remote_setup_recipes.dart';
import '../../state/remotes_provider.dart';
import '../theme/tokens.dart';
import 'fields.dart';

/// Whether rclone will run an OAuth sign-in for this backend.
///
/// Detected from the backend's own options — every OAuth backend carries a
/// `token` — rather than from a list of provider names we would have to keep
/// in step with rclone.
bool usesOAuth(RcloneProvider? p) =>
    p != null && p.options.any((o) => o.name == 'token');

/// The fields the guided screen shows for [state], paired with rclone's own
/// description of each.
///
/// A hand-written recipe when there is one — those are the backends rclone asks
/// nothing about, where a generic form would be a wall of 78 options. Otherwise
/// the backend's standard options, narrowed by `provider` the way rclone
/// narrows them, which turns s3's union-of-everything back into the handful
/// that applies to the service actually chosen.
List<(RecipeField, ProviderOption?)> guidedFields(AddRemoteState state) {
  final p = state.provider;
  if (p == null) return const [];
  final byName = {for (final o in p.options) o.name: o};
  final recipe = recipeFor(p.name);
  if (recipe != null) {
    return [
      for (final f in recipe.fields)
        // An option the recipe names but this build of rclone does not have is
        // skipped rather than rendered into nothing.
        if (byName.containsKey(f.option)) (f, byName[f.option]),
    ];
  }
  return [
    for (final o in p.optionsFor(state.providerValue))
      if (!o.advanced && !o.hide) (_fieldFromOption(o), o),
  ];
}

/// Turns an rclone option into a field, choosing how it is shown.
///
/// `Sensitive` counts as a secret here even though rclone keeps it separate
/// from `IsPassword`: it marks the things rclone refuses to write to its own
/// logs, which is a good enough reason not to paint them on a screen either.
RecipeField _fieldFromOption(ProviderOption o) => RecipeField(
  o.name,
  o.name,
  kind: o.isBool
      ? FieldKind.boolean
      : o.isSelect
      ? FieldKind.choice
      : (o.isPassword || o.sensitive)
      ? FieldKind.secret
      : o.isInt
      ? FieldKind.number
      : FieldKind.text,
  required: o.required,
);

/// Whether a question's answer should be hidden as it is typed.
///
/// rclone's flags are necessary and not sufficient: it marks `client_secret` as
/// neither `IsPassword` nor `Sensitive`, and `access_key_id` as `Sensitive`
/// rather than `IsPassword` (plan §2.2). The routed screens obscure the fields
/// they own, but a question that falls through to the generic renderer must not
/// be shown in the clear just because rclone forgot to say so — so the NAME is
/// read as well as the flags.
bool looksSecret(ProviderOption q) {
  if (q.isPassword || q.sensitive) return true;
  final n = q.name.toLowerCase();
  return n.contains('secret') ||
      n.contains('password') ||
      n.contains('token') ||
      n.contains('_key') ||
      n.endsWith('key') ||
      n.contains('credential');
}

/// The one screen before anything is created: a name, and whatever this
/// backend actually needs.
class GuidedSetup extends ConsumerWidget {
  const GuidedSetup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(addRemoteControllerProvider);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final recipe = recipeFor(state.provider?.name ?? '');
    final fields = guidedFields(state);
    final remoteNames = [
      for (final r
          in ref.watch(remotesProvider).valueOrNull ?? const <Remote>[])
        if (!r.isLocal) r.name,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('guided-list'),
            children: [
              Text(
                recipe?.title ?? 'Connect ${state.providerLabel}',
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((recipe?.intro ?? '').isNotEmpty) ...[
                const SizedBox(height: Space.x1),
                Text(
                  recipe!.intro,
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
              ],
              const SizedBox(height: Space.x4),
              LabeledField(
                label: 'Name',
                help: 'What this cloud is called in Airclone.',
                child: TextEntry(
                  initial: state.name,
                  hint: 'my-cloud',
                  onChanged: ctrl.setName,
                ),
              ),
              for (final (field, option) in fields)
                RecipeFieldEntry(
                  key: ValueKey('guided-${field.option}'),
                  field: field,
                  option: option,
                  value: state.values[field.option] ?? '',
                  remoteNames: remoteNames,
                  onChanged: (v) => ctrl.setValue(field.option, v),
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
              key: const ValueKey('guided-continue'),
              onPressed: ctrl.submit,
              child: const Text('Connect'),
            ),
          ],
        ),
      ],
    );
  }
}

/// One of rclone's own questions, rendered as a real control.
///
/// The previous flow put every non-boolean question behind a bare text field,
/// which is why choosing a Shared Drive meant typing a drive ID by hand. When
/// rclone supplies `Examples` there is a list to pick from, so show the list.
class GuidedQuestion extends ConsumerStatefulWidget {
  const GuidedQuestion({super.key, required this.question});

  final ProviderOption question;

  @override
  ConsumerState<GuidedQuestion> createState() => _GuidedQuestionState();
}

class _GuidedQuestionState extends ConsumerState<GuidedQuestion> {
  late String _value = widget.question.defaultStr;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final q = widget.question;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(
                q.summary.isEmpty ? q.name : q.summary,
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (q.help.contains('\n')) ...[
                const SizedBox(height: Space.x2),
                Text(
                  q.help,
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ],
              const SizedBox(height: Space.x4),
              if (!q.isBool)
                LabeledField(
                  label: q.name,
                  help: '',
                  child: q.isSelect
                      ? SelectEntry(
                          value: _value,
                          options: q.examples,
                          exclusive: q.exclusive,
                          onChanged: (v) => setState(() => _value = v),
                        )
                      : TextEntry(
                          initial: _value,
                          obscure: looksSecret(q),
                          keyboardNumber: q.isInt,
                          hint: q.defaultStr,
                          onChanged: (v) => setState(() => _value = v),
                          onSubmitted: () => ctrl.answer(_value),
                        ),
                ),
            ],
          ),
        ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: () => ctrl.answer(_value),
                child: const Text('Continue'),
              ),
            ],
          ),
      ],
    );
  }
}

/// Checking the new remote answers, before calling it a success.
class VerifyingStep extends StatelessWidget {
  const VerifyingStep({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: Space.x4),
        Text(
          'Checking the connection…',
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
      ],
    );
  }
}

/// The end of the flow: what was reached, or what went wrong with it.
class SuccessStep extends ConsumerWidget {
  const SuccessStep({
    super.key,
    required this.onOpen,
    required this.onAddAnother,
    required this.onDone,
  });

  final void Function(String remoteName) onOpen;
  final VoidCallback onAddAnother;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(addRemoteControllerProvider);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final name = state.isEdit ? (state.editName ?? '') : state.name.trim();
    final failed = state.verifyFailed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              Row(
                children: [
                  Icon(
                    failed ? Icons.error_outline : Icons.check_circle_outline,
                    size: 28,
                    color: failed ? c.error : c.success,
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Text(
                      failed
                          ? 'Added, but it did not answer'
                          : '$name is ready',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.x3),
              Text(
                state.successSummary ?? '',
                style: TextStyle(
                  color: failed ? c.error : c.textMuted,
                  fontSize: 13,
                ),
              ),
              if (failed) ...[
                const SizedBox(height: Space.x3),
                Text(
                  'The settings were saved. You can correct them now, or keep '
                  'it as it is if you know the server is simply down.',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.x3),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: failed
              ? [
                  TextButton(
                    onPressed: ctrl.switchToAdvanced,
                    child: const Text('Fix settings'),
                  ),
                  FilledButton(
                    onPressed: ctrl.keepUnverified,
                    child: const Text('Keep anyway'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: onAddAnother,
                    child: const Text('Add another'),
                  ),
                  TextButton(onPressed: onDone, child: const Text('Done')),
                  FilledButton(
                    onPressed: () => onOpen(name),
                    child: const Text('Open it'),
                  ),
                ],
        ),
      ],
    );
  }
}
