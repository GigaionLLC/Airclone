/// Google's retiring shared sign-in, put to the user honestly.
///
/// rclone 1.75 stopped opening Google Drive and Google Photos straight into
/// OAuth. It now asks first, because the shared client_id it has always used is
/// being retired and, in rclone's own words, "will stop working during 2026".
/// rclone's own default answer is to decline it.
///
/// A one-click "Sign in with Google" that quietly answered yes would sign
/// people up to something with a stated expiry and tell them nothing. So this
/// is a real screen with two honest choices — and it is driven by the question
/// rclone asks, not by a hard-coded list of providers, so if rclone adds the
/// warning elsewhere or drops it, the flow follows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:airclone_rc/airclone_rc.dart';

import '../../state/add_remote_controller.dart';
import '../theme/tokens.dart';
import 'fields.dart';

/// rclone's own guide. Linked rather than copied: it is maintained, and it
/// changes when Google's console changes.
const String kOwnClientIdGuide =
    'https://rclone.org/drive/#making-your-own-client-id';

/// The question rclone asks before a Google sign-in.
const String kSharedClientIdQuestion = 'config_shared_client_id';

/// True when [question] is the shared-client_id warning.
bool isSharedClientIdQuestion(ProviderOption? question) =>
    question?.name == kSharedClientIdQuestion;

/// True when [question] is one of the two fields that follow declining it.
bool isOwnClientIdQuestion(ProviderOption? question) =>
    question?.name == 'client_id' || question?.name == 'client_secret';

/// The choice: set up your own sign-in, or use the shared one for now.
class SharedClientIdChoice extends ConsumerWidget {
  const SharedClientIdChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final label = ref.watch(addRemoteControllerProvider).providerLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(
                'How should Airclone sign in to $label?',
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.x2),
              Text(
                'Google is retiring the shared sign-in that rclone has always '
                'used. rclone says it will stop working during 2026 — and it '
                'is already 2026.',
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: Space.x5),
              _Choice(
                key: const ValueKey('own-client-id'),
                title: 'Set up my own sign-in',
                recommended: true,
                body:
                    'Ten minutes in the Google Cloud console, once. It keeps '
                    'working, and it is yours rather than shared with every '
                    'other rclone user.',
                // FALSE declines the shared id, which is rclone's own default.
                onTap: () => ctrl.answer('false'),
              ),
              const SizedBox(height: Space.x3),
              _Choice(
                key: const ValueKey('shared-client-id'),
                title: 'Use the shared one for now',
                body:
                    'Works today and stops working when Google switches it '
                    'off. You can change it later under Advanced without '
                    'adding the cloud again.',
                onTap: () => ctrl.answer('true'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The walkthrough plus the paste boxes, for `client_id` and `client_secret`.
class OwnClientIdStep extends ConsumerStatefulWidget {
  const OwnClientIdStep({super.key, required this.question});

  final ProviderOption question;

  @override
  ConsumerState<OwnClientIdStep> createState() => _OwnClientIdStepState();
}

class _OwnClientIdStepState extends ConsumerState<OwnClientIdStep> {
  String _value = '';

  bool get _isId => widget.question.name == 'client_id';

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(
                _isId ? 'Your own Google sign-in' : 'And the secret',
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.x2),
              if (_isId) ...[
                Text(
                  'In the Google Cloud console:',
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
                const SizedBox(height: Space.x2),
                const _Step(1, 'Create a project (any name).'),
                const _Step(2, 'Enable the Google Drive API for it.'),
                const _Step(
                  3,
                  'Configure the consent screen, and add your own Google '
                  'account as a test user.',
                ),
                const _Step(
                  4,
                  'Create an OAuth client ID of type Desktop app.',
                ),
                const SizedBox(height: Space.x2),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(kOwnClientIdGuide),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Full instructions'),
                ),
                const SizedBox(height: Space.x3),
              ],
              LabeledField(
                label: _isId ? 'Client ID' : 'Client secret',
                help: _isId
                    ? 'Ends in .apps.googleusercontent.com'
                    : 'From the same screen as the client ID.',
                child: TextEntry(
                  key: ValueKey('own-${widget.question.name}'),
                  initial: '',
                  // BOTH obscured, on purpose. rclone does not flag
                  // client_secret as a password or even as sensitive (plan
                  // §2.2), so trusting its flags would print a live secret on
                  // screen — and a screenshot is a publishing channel.
                  obscure: true,
                  onChanged: (v) => setState(() => _value = v),
                  onSubmitted: _value.trim().isEmpty
                      ? null
                      : () => ctrl.answer(_value.trim()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.x3),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: _value.trim().isEmpty
                  ? null
                  : () => ctrl.answer(_value.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.title,
    required this.body,
    required this.onTap,
    this.recommended = false,
  });

  final String title;
  final String body;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.all(Space.x4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: recommended ? c.primary : c.border,
            width: recommended ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (recommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.successBg,
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                    child: Text(
                      'Recommended',
                      style: TextStyle(color: c.success, fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.x2),
            Text(body, style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$n.',
            style: TextStyle(
              color: c.textFaint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
