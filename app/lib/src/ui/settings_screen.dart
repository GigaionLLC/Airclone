import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/advanced_mode.dart';
import '../state/app_info.dart';
import '../state/cache_crypto.dart';
import '../state/download_settings.dart';
import '../state/engine_controller.dart';
import '../state/engine_flags.dart';
import '../state/jobs_controller.dart';
import '../state/settings_controller.dart';
import '../state/window_backdrop.dart';
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
    final advanced = ref.watch(advancedModeProvider);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
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
                _BackdropSection(),
                const SizedBox(height: Space.x5),
                _ModeSection(),
                const SizedBox(height: Space.x5),
                _RclonePathSection(),
                if (advanced) ...[
                  const SizedBox(height: Space.x5),
                  _ConcurrencySection(),
                  const SizedBox(height: Space.x5),
                  _EngineFlagsSection(),
                ],
                const SizedBox(height: Space.x5),
                _DownloadsSection(),
                const SizedBox(height: Space.x5),
                _CacheSection(),
                const SizedBox(height: Space.x5),
                _UpdatesSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Easy vs advanced mode toggle.
class _ModeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final advanced = ref.watch(advancedModeProvider);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Advanced mode',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Show power-user features: Sync, include/exclude/filter, '
                'dry-run, and saved tasks.',
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
        Switch(
          value: advanced,
          onChanged: ref.read(advancedModeProvider.notifier).set,
        ),
      ],
    );
  }
}

/// Where downloads go: a remembered default folder + an "always ask" toggle.
class _DownloadsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final dir = ref.watch(downloadDirProvider);
    final always = ref.watch(downloadAlwaysPromptProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(
          'Downloads',
          help: 'Where downloaded files are saved.',
        ),
        Row(
          children: [
            Icon(Icons.folder_outlined, size: 16, color: c.textMuted),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                dir ?? 'Ask each time (no default set)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: dir == null ? c.textFaint : c.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final p = await getDirectoryPath(initialDirectory: dir);
                if (p != null) {
                  await ref
                      .read(downloadDirProvider.notifier)
                      .set(p.replaceAll(r'\', '/'));
                }
              },
              child: const Text('Change'),
            ),
            if (dir != null)
              IconButton(
                onPressed: () =>
                    ref.read(downloadDirProvider.notifier).set(null),
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Clear default',
                color: c.textFaint,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: Space.x1),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Always ask where to save',
                    style: TextStyle(color: c.text, fontSize: 13),
                  ),
                  Text(
                    'Prompt for a folder on every download.',
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            Switch(
              value: always,
              onChanged: ref.read(downloadAlwaysPromptProvider.notifier).set,
            ),
          ],
        ),
      ],
    );
  }
}

/// Preview-cache controls: size, clear, and a memory-only privacy toggle.
class _CacheSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends ConsumerState<_CacheSection> {
  int? _size;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    final s = await diskCacheSize();
    if (mounted) setState(() => _size = s);
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    await clearDiskCaches();
    if (!mounted) return;
    setState(() => _clearing = false);
    _refreshSize();
  }

  static String _human(int b) {
    if (b < 1024) return '$b B';
    const u = ['KB', 'MB', 'GB'];
    var v = b / 1024;
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${u[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final memoryOnly = ref.watch(cacheMemoryOnlyProvider);
    final ctrl = ref.read(cacheMemoryOnlyProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(
          'Preview cache',
          help:
              'Thumbnails are encrypted at rest — bound to your rclone config '
              'password when the config is encrypted.',
        ),
        Row(
          children: [
            Icon(Icons.image_outlined, size: 16, color: c.textMuted),
            const SizedBox(width: Space.x2),
            Text(
              _size == null ? 'Calculating…' : 'On disk: ${_human(_size!)}',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const Spacer(),
            TextButton(
              onPressed: _clearing ? null : _clear,
              child: Text(_clearing ? 'Clearing…' : 'Clear cache'),
            ),
          ],
        ),
        const SizedBox(height: Space.x1),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Keep cache in memory only',
                    style: TextStyle(color: c.text, fontSize: 13),
                  ),
                  Text(
                    'Never write previews to disk (highest privacy).',
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            Switch(value: memoryOnly, onChanged: ctrl.set),
          ],
        ),
      ],
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

/// Desktop window background material (Mica/Acrylic on Windows 11).
class _BackdropSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final backdrop = ref.watch(windowBackdropProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(
          'Window background',
          help:
              'Translucent materials need OS support (Mica is Windows 11). '
              'Falls back to a normal window where unavailable.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: DropdownButton<WindowBackdrop>(
            value: backdrop,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(Radii.md),
            items: [
              for (final b in WindowBackdrop.values)
                DropdownMenuItem(value: b, child: Text(b.label)),
            ],
            onChanged: (v) {
              if (v != null) {
                ref.read(windowBackdropProvider.notifier).set(v);
              }
            },
          ),
        ),
        if (backdrop == WindowBackdrop.mica ||
            backdrop == WindowBackdrop.acrylic) ...[
          const SizedBox(height: 2),
          Text(
            'Tip: the effect shows behind the app. Some surfaces stay solid for '
            'readability.',
            style: TextStyle(color: c.textFaint, fontSize: 11),
          ),
        ],
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

/// Advanced: how many transfers may run at once (0 = unlimited).
class _ConcurrencySection extends ConsumerWidget {
  static const _options = [0, 1, 2, 3, 4, 6, 8];

  String _label(int v) => v == 0 ? 'Unlimited' : '$v at a time';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final value = ref.watch(transferConcurrencyProvider);
    // Guard against a persisted value that isn't in the preset list.
    final current = _options.contains(value) ? value : 0;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Concurrent transfers',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Run a limited number of transfers at once; the rest wait in '
                'the queue.',
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.x3),
        DropdownButton<int>(
          value: current,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(Radii.md),
          items: [
            for (final v in _options)
              DropdownMenuItem(value: v, child: Text(_label(v))),
          ],
          onChanged: (v) {
            if (v != null) {
              ref.read(transferConcurrencyProvider.notifier).set(v);
            }
          },
        ),
      ],
    );
  }
}

/// Advanced: extra flags appended to the rclone engine command line.
class _EngineFlagsSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_EngineFlagsSection> createState() =>
      _EngineFlagsSectionState();
}

class _EngineFlagsSectionState extends ConsumerState<_EngineFlagsSection> {
  late final TextEditingController _c = TextEditingController(
    text: ref.read(engineFlagsProvider),
  );
  bool _dirty = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    await ref.read(engineFlagsProvider.notifier).set(_c.text.trim());
    setState(() => _dirty = false);
    await ref.read(engineControllerProvider.notifier).restartEngine();
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    // Reflect the async-loaded value until the user starts editing.
    ref.listen(engineFlagsProvider, (prev, next) {
      if (!_dirty && next != _c.text) _c.text = next;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(
          'Engine flags',
          help:
              'Optional global flags added to the rclone engine, e.g. '
              '--transfers 8 --fast-list. Applied when the engine restarts.',
        ),
        TextField(
          controller: _c,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: r'--transfers 8 --checkers 16',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          onSubmitted: (_) => _apply(),
        ),
        const SizedBox(height: Space.x2),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _dirty ? _apply : null,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('Apply & restart engine'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: c.primary,
            ),
          ),
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
