import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_info.dart';
import '../state/settings_controller.dart';
import 'theme/tokens.dart';

/// Opens the app settings dialog (theme, engine path override, update check).
Future<void> showSettingsDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const SettingsDialog());

/// Settings panel shown as a centered desktop dialog. Lives entirely off
/// [settingsControllerProvider] plus the app-info providers.
class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(),
              const SizedBox(height: Space.x5),
              _ThemeSection(),
              const SizedBox(height: Space.x5),
              _RclonePathSection(),
              const SizedBox(height: Space.x5),
              _UpdatesSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Row(
      children: [
        Icon(Icons.settings_outlined, size: 20, color: c.primary),
        const SizedBox(width: Space.x2),
        Text(
          'Settings',
          style: TextStyle(
            color: c.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Close',
          color: c.textMuted,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// Section title + spacing helper shared by the panels below.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.help});
  final String label;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
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
        if (help != null) ...[
          const SizedBox(height: 2),
          Text(help!, style: TextStyle(color: c.textFaint, fontSize: 11)),
        ],
        const SizedBox(height: Space.x2),
      ],
    );
  }
}

class _ThemeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      settingsControllerProvider.select((s) => s.themeMode),
    );
    final ctrl = ref.read(settingsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Theme', help: 'How Airclone looks.'),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined, size: 16),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined, size: 16),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined, size: 16),
              label: Text('Dark'),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (sel) => ctrl.setThemeMode(sel.first),
        ),
      ],
    );
  }
}

class _RclonePathSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RclonePathSection> createState() => _RclonePathSectionState();
}

class _RclonePathSectionState extends ConsumerState<_RclonePathSection> {
  late final TextEditingController _c = TextEditingController(
    text: ref.read(settingsControllerProvider).rclonePathOverride,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reflect an async-loaded value if the field hasn't been edited yet.
    ref.listen(settingsControllerProvider.select((s) => s.rclonePathOverride), (
      prev,
      next,
    ) {
      if (next != _c.text) _c.text = next;
    });
    final ctrl = ref.read(settingsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(
          'rclone engine path',
          help: 'Optional. Leave blank to let Airclone locate rclone for you.',
        ),
        TextField(
          controller: _c,
          decoration: InputDecoration(
            isDense: true,
            hintText: r'e.g. C:\Tools\rclone.exe',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          onChanged: ctrl.setRclonePath,
        ),
      ],
    );
  }
}

class _UpdatesSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<_UpdatesSection> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final version = ref.watch(appVersionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Updates'),
        Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: c.textMuted),
            const SizedBox(width: Space.x2),
            Text(
              'Airclone ${version.valueOrNull ?? '…'}',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _checking = true),
              child: const Text('Check for updates'),
            ),
          ],
        ),
        if (_checking) ...[const SizedBox(height: Space.x2), _UpdateResult()],
      ],
    );
  }
}

class _UpdateResult extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final update = ref.watch(updateCheckProvider);
    return update.when(
      loading: () => Row(
        children: [
          const SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Space.x2),
          Text('Checking…', style: TextStyle(color: c.textMuted, fontSize: 13)),
        ],
      ),
      error: (e, _) => Text(
        "Couldn't check for updates.",
        style: TextStyle(color: c.error, fontSize: 13),
      ),
      data: (info) => info.hasUpdate
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x3,
                vertical: Space.x2,
              ),
              decoration: BoxDecoration(
                // The palette has no dedicated `infoBg`; derive a soft tint.
                color: c.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.upgrade, size: 16, color: c.info),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      '${info.latestTag} available',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (info.url.isNotEmpty)
                    FilledButton(
                      onPressed: () => launchUrl(
                        Uri.parse(info.url),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Open release'),
                    ),
                ],
              ),
            )
          : Row(
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: c.success),
                const SizedBox(width: Space.x2),
                Text(
                  "You're up to date",
                  style: TextStyle(color: c.success, fontSize: 13),
                ),
              ],
            ),
    );
  }
}
