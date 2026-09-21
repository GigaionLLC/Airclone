/// Signing in, and the honest list of ways to do it.
///
/// rclone finishes an OAuth sign-in by listening on `127.0.0.1:53682` and
/// waiting for the provider to redirect back to it. Everything on these screens
/// follows from that one fact: the link works wherever that port is reachable,
/// and nowhere else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:airclone_rc/airclone_rc.dart';

import '../../state/add_remote_controller.dart';
import '../theme/tokens.dart';
import 'fields.dart';

/// The screen that starts a sign-in: a name, one button, and a way out.
class SignInStart extends ConsumerWidget {
  const SignInStart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(addRemoteControllerProvider);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final label = state.providerLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(
                'Connect $label',
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.x1),
              Text(
                'You will sign in with $label. Airclone never sees your '
                'password — the sign-in happens in your browser.',
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: Space.x5),
              LabeledField(
                label: 'Name',
                help: 'What this cloud is called in Airclone.',
                child: TextEntry(
                  initial: state.name,
                  hint: 'my-cloud',
                  onChanged: ctrl.setName,
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
        // One primary button. The alternatives are real and they are one tap
        // away, but they are not a decision anybody should have to make before
        // they have seen whether the simple thing works.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('sign-in-primary'),
            onPressed: () => ctrl.signIn(SignInMethod.thisDevice),
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: Text('Sign in with $label'),
          ),
        ),
        const SizedBox(height: Space.x2),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => showOtherWays(context, ref),
            child: Text(
              'Other ways to sign in',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

/// The waiting screen: what is happening, the link, and a way to stop.
class SignInWaiting extends ConsumerWidget {
  const SignInWaiting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final state = ref.watch(addRemoteControllerProvider);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final url = state.authUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Text(
                      'Waiting for you to finish signing in…',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.x2),
              Text(
                state.signInMethod == SignInMethod.thisDevice
                    ? 'A browser window should have opened. Finish there and '
                          'this will continue on its own.'
                    : 'Open this link in a browser that can reach this device.',
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: Space.x4),
              if (url != null) ...[
                CopyRow(text: url.toString(), label: 'Copy link'),
                const SizedBox(height: Space.x2),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: ctrl.openAuthUrl,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open again'),
                    ),
                  ],
                ),
              ] else if (state.authUrlUnavailable) ...[
                _Note(
                  icon: Icons.info_outline,
                  text:
                      'A sign-in is waiting, but this engine did not report '
                      'its link. That happens with rclone older than 1.75, or '
                      'when the engine is started with -q. The other ways below '
                      'still work.',
                ),
              ],
              if (state.signInSlow) ...[
                const SizedBox(height: Space.x3),
                _Note(
                  icon: Icons.schedule,
                  text:
                      'Taking a while? Nothing has gone wrong — the sign-in is '
                      'still open. You can also try another way without '
                      'starting over.',
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
          children: [
            TextButton(
              onPressed: () => showOtherWays(context, ref),
              child: const Text('Other ways'),
            ),
            OutlinedButton(
              key: const ValueKey('sign-in-cancel'),
              onPressed: ctrl.cancelSignIn,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The `config_token` step: rclone hands over a command to run elsewhere and
/// waits for the token that comes back.
///
/// This is how somebody with no browser on this machine — a headless box, a
/// TV — still finishes a sign-in, and it is rclone's own mechanism rather than
/// anything of ours.
class AuthorizeHandoff extends ConsumerStatefulWidget {
  const AuthorizeHandoff({super.key, required this.question});

  final ProviderOption question;

  @override
  ConsumerState<AuthorizeHandoff> createState() => _AuthorizeHandoffState();
}

class _AuthorizeHandoffState extends ConsumerState<AuthorizeHandoff> {
  String _token = '';

  /// The `rclone authorize "drive"` line out of rclone's help text.
  ///
  /// Shown as its own copyable block when we can find it, because it is the
  /// only part of a long help message anybody needs to act on.
  String? get _command {
    for (final line in widget.question.help.split('\n')) {
      final t = line.trim();
      if (t.startsWith('rclone authorize')) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final command = _command;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(
                'Finish on another device',
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.x2),
              Text(
                'Run this on a computer that has rclone and a browser, then '
                'paste back what it prints.',
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: Space.x3),
              if (command != null) ...[
                CopyRow(
                  text: command,
                  label: 'Copy command',
                  monospace: true,
                  maxLines: 4,
                ),
                const SizedBox(height: Space.x3),
                // A phone can read this off the screen rather than retyping a
                // long quoted command.
                Center(
                  child: QrImageView(
                    data: command,
                    version: QrVersions.auto,
                    size: 148,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ] else
                Text(
                  widget.question.help,
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              const SizedBox(height: Space.x4),
              LabeledField(
                label: 'Result',
                help: 'Paste the whole config token here.',
                child: TextEntry(
                  initial: '',
                  obscure: true,
                  hint: '{"access_token":…}',
                  onChanged: (v) => setState(() => _token = v),
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
              onPressed: _token.trim().isEmpty
                  ? null
                  : () => ctrl.answer(_token.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The alternatives, each shown only when it can actually work.
///
/// **Availability is detected, not assumed.** "Paste a code" only appears for
/// the one backend that still uses the old paste-a-code redirect, and the
/// hand-off only when rclone actually offers it — the flow asks rclone what it
/// wants next rather than guessing from the provider name.
Future<void> showOtherWays(BuildContext context, WidgetRef ref) async {
  final c = AircloneTheme.of(context);
  final ctrl = ref.read(addRemoteControllerProvider.notifier);
  final state = ref.read(addRemoteControllerProvider);
  final url = state.authUrl;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surfaceRaised,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Other ways to sign in',
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.x4),
            _Way(
              icon: Icons.link,
              title: 'Show me the link',
              body:
                  'Sign in from another browser. The link only works where '
                  'port $kOAuthPort on THIS device is reachable — another '
                  'window here, or an SSH tunnel.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (url == null) ctrl.signIn(SignInMethod.showLink);
              },
            ),
            if (url != null) ...[
              const SizedBox(height: Space.x3),
              CopyRow(text: url.toString(), label: 'Copy link'),
              const SizedBox(height: Space.x2),
              Center(
                child: QrImageView(
                  data: url.toString(),
                  version: QrVersions.auto,
                  size: 132,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: Space.x2),
              CopyRow(
                text:
                    'ssh -L localhost:$kOAuthPort:localhost:$kOAuthPort '
                    'you@this-machine',
                label: 'Copy tunnel command',
                monospace: true,
              ),
            ],
            const SizedBox(height: Space.x4),
            _Way(
              icon: Icons.devices_other,
              title: 'Authorize on another device',
              body:
                  'Run a one-line rclone command on a computer that has a '
                  'browser, then paste the token back here. Nothing needs to '
                  'reach this device.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                ctrl.signIn(SignInMethod.otherDevice);
              },
            ),
            const SizedBox(height: Space.x4),
            _Way(
              icon: Icons.settings_outlined,
              title: 'Enter the details myself',
              body:
                  'Skip the guide and fill in every option by hand, the way '
                  'rclone config does.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                ctrl.switchToAdvanced();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _Way extends StatelessWidget {
  const _Way({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.all(Space.x2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: c.primary),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c.textMuted),
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
