/// "Add a cloud" — a thin router over the guided and advanced front ends.
///
/// The screens live in `add_remote/`; this file decides which one is showing,
/// how big the dialog should be for it, and what happens when it closes. It
/// used to be all of them at once, at a fixed 520x560, which is why the option
/// list and the sign-in step were the same shape as a two-line question.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:airclone_rc/airclone_rc.dart';

import '../rclone/models/remote.dart';
import '../state/add_remote_controller.dart';
import '../state/browser_controller.dart';
import '../state/remotes_provider.dart';
import 'add_remote/advanced_form.dart';
import 'add_remote/guided_steps.dart';
import 'add_remote/own_client_id_step.dart';
import 'add_remote/provider_picker.dart';
import 'add_remote/sign_in_step.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

Future<void> showAddRemoteDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const AddRemoteDialog());

/// Opens the same dialog pre-filled to EDIT an existing remote (config/update).
Future<void> showEditRemoteDialog(BuildContext context, Remote remote) =>
    showDialog(
      context: context,
      builder: (_) => AddRemoteDialog(editRemote: remote),
    );

class AddRemoteDialog extends ConsumerStatefulWidget {
  const AddRemoteDialog({super.key, this.editRemote});

  /// When set, the dialog edits this remote instead of creating a new one.
  final Remote? editRemote;

  @override
  ConsumerState<AddRemoteDialog> createState() => _AddRemoteDialogState();
}

class _AddRemoteDialogState extends ConsumerState<AddRemoteDialog> {
  late final AddRemoteController _ctrl = ref.read(
    addRemoteControllerProvider.notifier,
  );

  /// Tracked so [dispose] knows whether this flow left something behind,
  /// without reading a provider at a point where that is not allowed.
  bool _needsCleanup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.editRemote != null) {
        _ctrl.startEdit(widget.editRemote!);
      } else {
        _ctrl.reset();
      }
    });
  }

  @override
  void dispose() {
    // Closing an unfinished create has to clean up after it, whichever way the
    // dialog was closed — button, Escape, or a tap on the barrier.
    //
    // Keyed on "is there a section this flow wrote and did not finish", NOT on
    // being mid-sign-in. rclone writes `[name] type = …` as soon as a call
    // returns at a QUESTION, so walking away from the shared-client_id screen
    // leaves exactly the same unusable remote behind as abandoning the sign-in
    // does. A successful create clears the marker, so this can never delete a
    // remote that worked.
    if (_needsCleanup) {
      _ctrl.cancelSignIn();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(addRemoteControllerProvider);
    _needsCleanup = !state.isEdit && state.createdName != null;

    // An edit finishes silently, the way it always has. A create earns its
    // success screen.
    ref.listen(addRemoteControllerProvider, (prev, next) {
      if (next.phase == AddPhase.done && next.isEdit && mounted) {
        Navigator.of(context).pop();
      }
    });

    final (width, height) = _sizeFor(state);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: DialogBody(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.phase != AddPhase.pickProvider) _header(c, state),
              Expanded(child: _body(state)),
            ],
          ),
        ),
      ),
    );
  }

  /// The dialog is sized for the step it is showing. A 78-option form and a
  /// yes/no question do not want the same box.
  (double, double) _sizeFor(AddRemoteState state) => switch (state.phase) {
    AddPhase.pickProvider => (560, 600),
    AddPhase.busy || AddPhase.verifying => (420, 260),
    AddPhase.done => (480, 380),
    AddPhase.signingIn => (520, 480),
    AddPhase.question =>
      isSharedClientIdQuestion(state.question) ||
              isOwnClientIdQuestion(state.question)
          ? (520, 600)
          : (520, 460),
    AddPhase.setup ||
    AddPhase.error => state.mode == AddMode.advanced ? (560, 620) : (520, 540),
  };

  Widget _header(AircloneColors c, AddRemoteState state) {
    final showAdvancedLink =
        !state.isEdit &&
        state.mode == AddMode.guided &&
        (state.phase == AddPhase.setup || state.phase == AddPhase.question);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Row(
        children: [
          IconButton(
            onPressed: () => state.isEdit
                ? Navigator.of(context).pop()
                : _ctrl.backToProviders(),
            icon: Icon(state.isEdit ? Icons.close : Icons.arrow_back, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: Space.x1),
          Expanded(
            child: Text(
              state.isEdit
                  ? 'Edit ${state.providerLabel}'
                  : state.providerLabel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // The guided flow never hides the manual one. This is the second of
          // its three entrances; the others are on each tile in the picker and
          // on the failure screen.
          if (showAdvancedLink)
            TextButton(
              onPressed: _ctrl.switchToAdvanced,
              child: Text(
                'Advanced',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(AddRemoteState state) {
    switch (state.phase) {
      case AddPhase.pickProvider:
        return const ProviderPicker();

      case AddPhase.busy:
        return const Center(child: CircularProgressIndicator());

      case AddPhase.verifying:
        return const VerifyingStep();

      case AddPhase.signingIn:
        return const SignInWaiting();

      case AddPhase.question:
        final q = state.question;
        if (isSharedClientIdQuestion(q)) return const SharedClientIdChoice();
        if (isOwnClientIdQuestion(q)) return OwnClientIdStep(question: q!);
        // rclone asks for a config token when the sign-in is being done
        // somewhere else. That is a screen, not a text box.
        if (q?.name == 'config_token') return AuthorizeHandoff(question: q!);
        if (q == null) return const Center(child: CircularProgressIndicator());
        return GuidedQuestion(key: ValueKey(state.questionState), question: q);

      case AddPhase.setup:
        if (state.mode == AddMode.advanced) {
          return AdvancedForm(onSubmit: () => _onSubmit(state));
        }
        // An OAuth backend has nothing useful to ask before sign-in: its
        // standard options are a client_id and a scope, which belong in
        // Advanced. Everything else gets the essentials screen.
        if (recipeIsAbsentAndOAuth(state)) return const SignInStart();
        return const GuidedSetup();

      case AddPhase.done:
        return SuccessStep(
          onOpen: _openRemote,
          onAddAnother: _ctrl.reset,
          onDone: () => Navigator.of(context).pop(),
        );

      case AddPhase.error:
        return _buildError(state);
    }
  }

  /// True when rclone drives this backend itself through an OAuth sign-in, so
  /// the guided path is one button rather than a form.
  bool recipeIsAbsentAndOAuth(AddRemoteState state) =>
      state.recipeFields.isEmpty && usesOAuth(state.provider);

  Future<void> _onSubmit(AddRemoteState state) async {
    if (state.isEdit) {
      await _onSaveEdit(state);
    } else {
      await _ctrl.submit();
    }
  }

  Future<void> _openRemote(String name) async {
    final navigator = Navigator.of(context);
    final remotes = await ref.read(remotesProvider.future);
    Remote? found;
    for (final r in remotes) {
      if (r.name == name) {
        found = r;
        break;
      }
    }
    if (found != null) {
      await ref.read(paneProvider(0).notifier).open(found);
    }
    if (mounted) navigator.pop();
  }

  Widget _buildError(AddRemoteState state) {
    final c = AircloneTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 36, color: c.error),
        const SizedBox(height: Space.x3),
        Text(
          "That didn't work",
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
        const SizedBox(height: Space.x5),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            TextButton(
              onPressed: _ctrl.backToProviders,
              child: const Text('Start over'),
            ),
            // Carries the values across, so nothing is retyped — the third
            // entrance to the manual path, offered exactly when the guided one
            // has just failed somebody.
            if (state.provider != null)
              TextButton(
                onPressed: _ctrl.switchToAdvanced,
                child: const Text('Enter details myself'),
              ),
            // Port 53682 held by an abandoned attempt is the commonest
            // recoverable failure here, and it has a one-press fix.
            if ((state.error ?? '').contains('$kOAuthPort'))
              FilledButton(
                onPressed: _ctrl.retryAfterCancel,
                child: const Text('Try again'),
              ),
          ],
        ),
      ],
    );
  }

  /// Edit-save entry point. Editing a `crypt` remote's password rewrites the key
  /// rclone derives from it, so everything already uploaded with the OLD password
  /// silently becomes permanently undecryptable. When that's what a save would do,
  /// make the user confirm it first; otherwise save straight through.
  Future<void> _onSaveEdit(AddRemoteState state) async {
    if (_cryptPasswordChanged(state)) {
      final confirmed = await _confirmCryptPasswordChange();
      if (!mounted || confirmed != true) return;
    }
    await _ctrl.submitEdit();
  }

  /// True when a `crypt` remote is being edited and a new, non-blank value has
  /// been typed into any of its password fields (`password` / `password2`) — the
  /// exact situation that would re-key it. (Blank means "keep current", so safe.)
  bool _cryptPasswordChanged(AddRemoteState state) {
    final p = state.provider;
    if (p == null || p.name != 'crypt') return false;
    for (final o in p.options) {
      if (o.isPassword && (state.values[o.name]?.isNotEmpty ?? false)) {
        return true;
      }
    }
    return false;
  }

  /// Destructive confirm shown before re-keying a crypt remote. Cancel is the
  /// autofocused default so an accidental Enter never rewrites the key.
  Future<bool?> _confirmCryptPasswordChange() {
    final c = AircloneTheme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        title: Text(
          'Change encryption password?',
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Files already uploaded with the current password will become '
          'permanently unreadable — the new password cannot decrypt them, and '
          'there is no way to reset it. This cannot be undone.',
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
            autofocus: true,
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: c.textMuted)),
          ),
          const SizedBox(width: Space.x1),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.error,
              foregroundColor: c.onPrimary,
            ),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Change password'),
          ),
        ],
      ),
    );
  }
}
