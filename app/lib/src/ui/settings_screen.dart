import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../rclone/rclone_engine.dart';
import '../state/advanced_mode.dart';
import '../state/app_info.dart';
import '../state/cache_crypto.dart';
import '../state/config_password_vault.dart';
import '../state/download_settings.dart';
import '../state/engine_controller.dart';
import '../state/engine_flags.dart';
import '../state/jobs_controller.dart';
import '../state/settings_controller.dart';
import '../state/skin.dart';
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
        child: const SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(Space.x5),
            child: SettingsContent(),
          ),
        ),
      ),
    );
  }
}

/// The settings sections themselves — shared between the desktop dialog and
/// the phone shell's full-screen Settings tab. Sections that only make sense
/// with a desktop window/engine (backdrop, rclone path override) hide
/// themselves on mobile.
class SettingsContent extends ConsumerWidget {
  const SettingsContent({super.key, this.embedded = false});

  /// True when shown as a plain screen (phone Settings tab) rather than a
  /// dismissable dialog.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advanced = ref.watch(advancedModeProvider);
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(showClose: !embedded),
        const SizedBox(height: Space.x4),
        // Advanced mode pinned at the top so it's easy to find/toggle.
        _ModeSection(),
        const SizedBox(height: Space.x5),
        const _GroupHeader('Appearance'),
        _ThemeSection(),
        const SizedBox(height: Space.x4),
        _SkinSection(),
        if (desktop) ...[const SizedBox(height: Space.x4), _BackdropSection()],
        if (desktop || advanced) ...[
          const SizedBox(height: Space.x5),
          const _GroupHeader('Transfers'),
          // Desktop only: Android's directory picker returns SAF content://
          // URIs, which can't be a default download folder for the engine.
          if (desktop) _DownloadsSection(),
          if (advanced) ...[
            if (desktop) const SizedBox(height: Space.x4),
            _ConcurrencySection(),
          ],
        ],
        if (desktop || advanced) ...[
          const SizedBox(height: Space.x5),
          const _GroupHeader('Engine'),
          if (desktop) ...[
            _RclonePathSection(),
            const SizedBox(height: Space.x4),
            _EngineVersionSection(),
            const SizedBox(height: Space.x4),
            _RememberPasswordSection(),
          ],
          if (advanced) ...[
            if (desktop) const SizedBox(height: Space.x4),
            _EngineFlagsSection(),
          ],
        ],
        const SizedBox(height: Space.x5),
        const _GroupHeader('Storage & updates'),
        _CacheSection(),
        const SizedBox(height: Space.x4),
        _UpdatesSection(),
      ],
    );
  }
}

/// A small all-caps label that groups the settings sections below it.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Easy vs advanced mode toggle — pinned at the top of Settings as a prominent
/// card so power-user features (Sync, filters, dry-run, saved + scheduled
/// tasks) are easy to discover and switch on.
class _ModeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final advanced = ref.watch(advancedModeProvider);
    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: advanced ? c.primary.withValues(alpha: 0.08) : c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: advanced ? c.primary.withValues(alpha: 0.40) : c.border,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 20, color: advanced ? c.primary : c.textMuted),
          const SizedBox(width: Space.x3),
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
                const SizedBox(height: 2),
                Text(
                  'Power-user features: Sync, include/exclude/filter, dry-run, '
                  'and saved + scheduled tasks.',
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          Switch(
            value: advanced,
            onChanged: ref.read(advancedModeProvider.notifier).set,
          ),
        ],
      ),
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
  const _Header({this.showClose = true});

  /// False when the content is embedded in the phone shell's Settings tab —
  /// there is no dialog route to pop there.
  final bool showClose;

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
        if (showClose)
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
/// Optional visual skin: Airclone (default brand look) + native-feel OS skins.
class _SkinSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final skin = ref.watch(skinProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(
          'Skin',
          help:
              'Airclone is the default look; the others approximate each '
              "OS's native file manager (optional).",
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: DropdownButton<Skin>(
            value: skin,
            dropdownColor: c.surfaceRaised,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(Radii.md),
            items: [
              for (final s in Skin.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) {
              if (v != null) ref.read(skinProvider.notifier).set(v);
            },
          ),
        ),
      ],
    );
  }
}

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
            dropdownColor: c.surfaceRaised,
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

/// Desktop: shows the running rclone engine version with a "check for updates"
/// affordance that can download + hot-swap a newer verified engine build.
/// Mirrors the app-updates section's visual pattern but drives the engine via
/// [EngineController.updateEngine] (Android bundles its engine — desktop-gated).
class _EngineVersionSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_EngineVersionSection> createState() =>
      _EngineVersionSectionState();
}

class _EngineVersionSectionState extends ConsumerState<_EngineVersionSection> {
  // Idle when all flags are false and both strings are null. The check/update
  // lifecycle is tracked with these so feedback renders inline, matching the
  // Engine-flags "Apply & restart" and app "Check for updates" patterns.
  bool _checking = false;
  bool _updating = false;
  String? _latest; // latest tag resolved by the last successful check
  String? _error; // friendly message when a check/update failed
  bool _updated = false; // success confirmation after a hot-swap

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
      _latest = null;
      _updated = false;
    });
    try {
      final latest = await RcloneEngine.latestAvailableVersion();
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't reach the rclone download server. Try again.";
        _checking = false;
      });
    }
  }

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      await ref.read(engineControllerProvider.notifier).updateEngine();
      if (!mounted) return;
      setState(() {
        _updating = false;
        _updated = true;
        _latest = null; // now running the latest — clear the update CTA
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _updating = false;
        _error = 'Update failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final running = ref.watch(
      engineControllerProvider.select((e) => e.version),
    );
    // Only offer an update when the resolved latest is strictly newer than the
    // engine we're actually running.
    final newer =
        running != null &&
        _latest != null &&
        RcloneEngine.compareRcloneVersions(_latest!, running) > 0;
    final busy = _checking || _updating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(
          'rclone engine version',
          help: 'The engine that powers transfers, mounts, and serve.',
        ),
        Row(
          children: [
            Icon(Icons.memory_outlined, size: 16, color: c.textMuted),
            const SizedBox(width: Space.x2),
            Text(
              running != null ? 'rclone $running' : 'rclone (not running)',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const Spacer(),
            if (busy)
              const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (newer)
              FilledButton.icon(
                onPressed: _update,
                icon: const Icon(Icons.upgrade, size: 16),
                label: Text('Update to $_latest'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: c.primary,
                ),
              )
            else
              TextButton(
                onPressed: running == null ? null : _check,
                child: const Text('Check for updates'),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.x1),
          Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
        ] else if (_updating) ...[
          const SizedBox(height: Space.x1),
          Text(
            'Downloading and restarting the engine…',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
        ] else if (_updated || (_latest != null && !newer)) ...[
          const SizedBox(height: Space.x1),
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 14, color: c.success),
              const SizedBox(width: Space.x2),
              Text(
                _updated ? 'Engine updated.' : 'Up to date.',
                style: TextStyle(color: c.success, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Desktop: opt-in to storing the encrypted-config password in the OS credential
/// vault so scheduled/background runs can unlock the config unattended. Default
/// OFF and security-sensitive, so the sub-label is deliberately blunt about the
/// exposure. Toggling OFF wipes any stored password immediately; toggling ON
/// captures the currently-unlocked password now (if any) so it takes effect
/// without waiting for the next unlock.
class _RememberPasswordSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final remember = ref.watch(rememberConfigPasswordProvider);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remember config password',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Stored in the operating system's credential vault (Windows "
                'Credential Manager / macOS Keychain / Linux Secret Service) so '
                'scheduled and background runs can unlock the config without '
                'you; anyone with access to your OS user account can recover it. '
                'Toggling off clears the stored password immediately.',
                style: TextStyle(color: c.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.x3),
        Switch(
          value: remember,
          onChanged: (v) async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            await ref.read(rememberConfigPasswordProvider.notifier).set(v);
            final vault = ref.read(configPasswordVaultProvider);
            if (v) {
              // If the config is already unlocked this session, capture that
              // password now so the setting takes effect without a restart.
              final held = ref.read(cachePassphraseProvider);
              if (held != null && held.isNotEmpty) await vault.save(held);
            } else {
              // Opted out — remove any stored password from the OS vault now.
              // The sub-label promises immediate removal, so a failed delete
              // (locked keyring, Secret Service down) must be surfaced rather
              // than silently leaving the recoverable secret behind.
              final removed = await vault.clear();
              if (!removed) {
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not remove the stored password from the OS '
                      'credential vault — it may still be present.',
                    ),
                  ),
                );
              }
            }
          },
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
          dropdownColor: c.surfaceRaised,
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
        // One-tap presets for common flags; they compose into the text below
        // (which stays the source of truth).
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x1,
          children: [
            for (final f in const [
              '--fast-list',
              '--transfers 8',
              '--checkers 16',
              '--no-traverse',
            ])
              FilterChip(
                label: Text(
                  f,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                visualDensity: VisualDensity.compact,
                selected: hasEngineFlag(_c.text, f),
                onSelected: (_) => setState(() {
                  _c.text = toggleEngineFlag(_c.text, f);
                  _dirty = true;
                }),
              ),
          ],
        ),
        const SizedBox(height: Space.x2),
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
