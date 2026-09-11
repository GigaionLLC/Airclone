/// Settings → Web UI: start and stop the browser-served interface.
///
/// The GUI counterpart to `airclone --webui`. Same server, same credentials
/// file, same rules; this one just has someone watching, so it can show the URL
/// and the password instead of printing them once and hoping.
///
/// The panel is built around the one thing an operator can get wrong here:
/// **who can reach it**. The bind control is not buried behind "advanced", the
/// current exposure is stated in words rather than implied by an IP address,
/// and choosing anything but this machine puts a warning on screen that does
/// not go away while it is running.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../webui/webui_controller.dart';
import '../webui/webui_credentials.dart';
import '../webui/webui_options.dart';
import 'theme/tokens.dart';

/// Renders nothing where the Web UI cannot be hosted, so callers need no guard.
class WebUiSection extends ConsumerStatefulWidget {
  const WebUiSection({super.key});

  @override
  ConsumerState<WebUiSection> createState() => _WebUiSectionState();
}

class _WebUiSectionState extends ConsumerState<WebUiSection> {
  final _addressController = TextEditingController();
  final _portController = TextEditingController();
  bool _revealPassword = false;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    if (webUiHostingSupported) {
      Future.microtask(() async {
        await ref.read(webUiControllerProvider.notifier).ensureLoaded();
        if (!mounted) return;
        final o = ref.read(webUiControllerProvider).options;
        _addressController.text = o.bindAddress;
        _portController.text = '${o.port}';
      });
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!webUiHostingSupported) return const SizedBox.shrink();
    final c = AircloneTheme.of(context);
    final state = ref.watch(webUiControllerProvider);
    final ctrl = ref.read(webUiControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Text(
                'Web UI',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: state.running,
              onChanged: state.busy
                  ? null
                  : (on) => on ? ctrl.start() : ctrl.stop(),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Open Airclone in a browser on another device. Everything still '
          'happens on this computer: a drive mounted from the Web UI mounts '
          'here, and the files you browse are these files.',
          style: TextStyle(color: c.textFaint, fontSize: 11),
        ),
        const SizedBox(height: Space.x3),

        if (state.running) ...[
          _RunningPanel(
            state: state,
            reveal: _revealPassword,
            onToggleReveal: () =>
                setState(() => _revealPassword = !_revealPassword),
            onRegenerate: ctrl.regenerateCredentials,
          ),
          const SizedBox(height: Space.x3),
        ],

        // Editable only while stopped: changing where a running server listens
        // would mean silently rebinding it, and an operator who thinks they are
        // on loopback while they are not is the failure this feature must not
        // have.
        Opacity(
          opacity: state.running ? 0.5 : 1,
          child: IgnorePointer(
            ignoring: state.running,
            child: _BindControls(
              addressController: _addressController,
              portController: _portController,
              options: state.options,
              error: _fieldError,
              onChanged: () async {
                final error = await ctrl.configure(
                  bindAddress: _addressController.text,
                  port: int.tryParse(_portController.text),
                );
                if (mounted) setState(() => _fieldError = error);
              },
              onPreset: (address) async {
                _addressController.text = address;
                final error = await ctrl.configure(bindAddress: address);
                if (mounted) setState(() => _fieldError = error);
              },
            ),
          ),
        ),

        if (state.message != null) ...[
          const SizedBox(height: Space.x3),
          _Banner(
            text: state.message!,
            background: c.warningBg,
            foreground: c.warning,
            icon: Icons.info_outline,
          ),
        ],
        if (state.bundleMissing) ...[
          const SizedBox(height: Space.x3),
          _Banner(
            text:
                'This build does not include the web interface files, so the '
                'sign-in page will load but the app will not. Reinstall from a '
                'release build.',
            background: c.errorBg,
            foreground: c.error,
            icon: Icons.error_outline,
          ),
        ],
      ],
    );
  }
}

/// URL, credentials and the exposure warning, shown only while serving.
class _RunningPanel extends StatelessWidget {
  const _RunningPanel({
    required this.state,
    required this.reveal,
    required this.onToggleReveal,
    required this.onRegenerate,
  });

  final WebUiUi state;
  final bool reveal;
  final VoidCallback onToggleReveal;
  final Future<void> Function() onRegenerate;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.exposed) ...[
            _Banner(
              text: state.options.isAllInterfaces
                  ? 'Reachable from every network this computer is on, over '
                        'plain HTTP. Only the password below stands in front '
                        'of your remotes.'
                  : 'Reachable from the network at '
                        '${state.options.bindAddress}, over plain HTTP.',
              background: c.warningBg,
              foreground: c.warning,
              icon: Icons.public,
            ),
            const SizedBox(height: Space.x3),
          ],
          _CopyRow(label: 'Address', value: state.url ?? '', mono: true),
          const SizedBox(height: Space.x2),
          _CopyRow(label: 'Username', value: state.username ?? '', mono: true),
          const SizedBox(height: Space.x2),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  'Password',
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                ),
              ),
              Expanded(
                child: SelectableText(
                  reveal ? (state.password ?? '') : '••••••••••••',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggleReveal,
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                tooltip: reveal ? 'Hide' : 'Show',
                icon: Icon(
                  reveal
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              IconButton(
                onPressed: state.password == null
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: state.password!),
                      ),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy password',
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          Text(switch (state.credentialSource) {
            WebUiCredentialSource.environment =>
              'From $kWebUiPasswordEnv in this computer\'s environment.',
            _ =>
              'Saved in $kWebUiEnvFileName beside your rclone config. '
                  'Deleting that file generates a new password.',
          }, style: TextStyle(color: c.textFaint, fontSize: 11)),
          if (state.credentialSource != WebUiCredentialSource.environment) ...[
            const SizedBox(height: Space.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('New password'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Address + port, with the two presets that cover almost every case.
class _BindControls extends StatelessWidget {
  const _BindControls({
    required this.addressController,
    required this.portController,
    required this.options,
    required this.error,
    required this.onChanged,
    required this.onPreset,
  });

  final TextEditingController addressController;
  final TextEditingController portController;
  final WebUiOptions options;
  final String? error;
  final VoidCallback onChanged;
  final void Function(String address) onPreset;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who can reach it', style: TextStyle(color: c.text, fontSize: 12)),
        const SizedBox(height: Space.x2),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              icon: Icon(Icons.lock_outline, size: 15),
              label: Text('This computer'),
            ),
            ButtonSegment(
              value: false,
              icon: Icon(Icons.public, size: 15),
              label: Text('Any network'),
            ),
          ],
          selected: {options.isLoopback},
          showSelectedIcon: false,
          onSelectionChanged: (sel) =>
              onPreset(sel.first ? kDefaultWebUiBind : '0.0.0.0'),
        ),
        const SizedBox(height: Space.x3),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: addressController,
                onChanged: (_) => onChanged(),
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Address',
                  helperText: 'An IP address of this computer',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: TextField(
                controller: portController,
                onChanged: (_) => onChanged(),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Port',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: Space.x2),
          Text(error!, style: TextStyle(color: c.error, fontSize: 11)),
        ],
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: c.textFaint, fontSize: 11),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              color: c.text,
              fontSize: 12,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
        IconButton(
          onPressed: value.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: value)),
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x3,
        vertical: Space.x2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foreground, fontSize: 11, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
