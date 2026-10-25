import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/autostart.dart';
import '../state/close_to_tray.dart';
import '../state/host_platform.dart';
import 'theme/tokens.dart';

/// Settings > Tray (#54): what the close button does, and the sign-in launch.
/// Desktop only; the settings screen does not build it anywhere else.
class TraySettingsSection extends ConsumerWidget {
  const TraySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closeToTray = ref.watch(closeToTrayProvider) ?? false;
    final trayUp = ref.watch(trayAvailableProvider);
    final autostart = ref.watch(autostartProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SwitchRow(
          key: const ValueKey('tray.closeToTray'),
          title: 'Closing the window keeps Airclone running in the tray',
          help: trayUp
              ? 'Transfers, mounted drives and scheduled tasks keep going with '
                    'the window closed. Quit from the tray icon'
                    '${HostPlatform.isMacOS ? ' or with Cmd-Q' : ''}.'
              : _noTrayHelp(),
          value: trayUp && closeToTray,
          onChanged: trayUp
              ? (v) => ref.read(closeToTrayProvider.notifier).set(v)
              : null,
        ),
        const SizedBox(height: Space.x4),
        if (autostart.support.supported)
          _SwitchRow(
            key: const ValueKey('tray.autostart'),
            title: 'Start Airclone in the tray when I sign in',
            help: HostPlatform.isMacOS
                ? 'Adds Airclone to System Settings > General > Login Items. '
                      'It opens with no window; click the menu bar icon.'
                : 'Opens with no window; open it from the tray icon.',
            value: autostart.enabled,
            onChanged: autostart.busy
                ? null
                : (v) async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final ok = await ref
                        .read(autostartProvider.notifier)
                        .set(v);
                    if (!ok) {
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(
                            v
                                ? 'Could not add Airclone to your sign-in '
                                      'items.'
                                : 'Could not remove Airclone from your '
                                      'sign-in items.',
                          ),
                        ),
                      );
                    }
                  },
          )
        else if (autostart.support.reason != null)
          _Note(
            key: const ValueKey('tray.autostartUnsupported'),
            text:
                'Starting at sign-in is not offered here. '
                '${autostart.support.reason}',
          ),
      ],
    );
  }

  static String _noTrayHelp() => HostPlatform.isLinux
      ? 'Your desktop has no tray (StatusNotifier) host, so closing the window '
            'quits Airclone. On GNOME, the AppIndicator extension adds one.'
      : 'The tray icon is not available, so closing the window quits Airclone.';
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.title,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String help;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Row(
      children: [
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
              Text(help, style: TextStyle(color: c.textFaint, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: Space.x3),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Text(text, style: TextStyle(color: c.textFaint, fontSize: 11));
  }
}
