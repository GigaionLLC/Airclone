import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../rclone/librclone_ffi.dart' show defaultLibrclonePath;
import '../rclone/rclone_engine.dart';
import '../state/advanced_mode.dart';
import '../state/app_info.dart';
import '../state/biometric_unlock.dart';
import '../state/cache_crypto.dart';
import '../state/config_password_vault.dart';
import '../state/config_transfer_controller.dart';
import '../state/download_settings.dart';
import '../state/engine_controller.dart';
import '../state/engine_flags.dart';
import '../state/engine_mode.dart';
import '../state/jobs_controller.dart';
import '../state/os_integration.dart';
import '../state/remotes_provider.dart';
import '../state/settings_controller.dart';
import '../state/skin.dart';
import '../state/window_backdrop.dart';
import 'config_encryption_dialog.dart';
import 'config_export_dialog.dart';
import 'config_import_dialog.dart';
import 'offline_qr_dialog.dart';
import 'scan_from_desktop_sheet.dart';
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
            _EngineModeSection(),
            const SizedBox(height: Space.x4),
            _RclonePathSection(),
            const SizedBox(height: Space.x4),
            _EngineVersionSection(),
          ],
          if (advanced) ...[
            if (desktop) const SizedBox(height: Space.x4),
            _EngineFlagsSection(),
          ],
        ],
        // Security: OS-vault release of the encrypted-config password. The vault
        // opt-in ("Remember config password") works on every platform's keystore;
        // biometric RELEASE is phone-first — its row hides itself where the device
        // has no enrolled fingerprint/face (desktop today, until local_auth_windows
        // lands). Shown on all platforms so mobile — the whole point of biometric
        // unlock — can reach both toggles.
        const SizedBox(height: Space.x5),
        const _GroupHeader('Security'),
        _RememberPasswordSection(),
        _BiometricUnlockSection(),
        // Config: visible on every platform (mobile is read-only — the path
        // picker/switch is desktop-only, but everyone sees where their remotes
        // live, whether it's encrypted, and how many are configured).
        const SizedBox(height: Space.x5),
        const _GroupHeader('Config'),
        const _ConfigSection(),
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

/// Best-effort guess of rclone's default config location on this OS, WITHOUT
/// shelling out — just the conventional path derived from the environment, for
/// DISPLAY in the Config section. Null when the environment doesn't reveal a
/// home/appdata dir (the section then shows "rclone default"). The engine still
/// lets rclone resolve its own default at spawn time; this never drives config.
String? conventionalRcloneConfigPath() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    return '${appData.replaceAll(r'\', '/')}/rclone/rclone.conf';
  }
  // POSIX: XDG override wins, else ~/.config/rclone/rclone.conf (rclone's default).
  final xdg = Platform.environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/rclone/rclone.conf';
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return '$home/.config/rclone/rclone.conf';
  }
  return null;
}

/// The Config section: where the active rclone config lives, whether it's
/// encrypted, how many remotes it holds, and (desktop) actions to point Airclone
/// at a different config file or return to rclone's default. Mobile renders the
/// same status read-only — the app-private config there isn't user-relocatable.
///
/// Switching runs a pre-flight validation: a plaintext pick must parse via
/// `rclone config dump` before we persist + restart; an *encrypted* pick is
/// allowed through (it gates on the launch password) since a non-interactive
/// dump would fail it for the wrong reason.
class _ConfigSection extends ConsumerStatefulWidget {
  const _ConfigSection();

  @override
  ConsumerState<_ConfigSection> createState() => _ConfigSectionState();
}

class _ConfigSectionState extends ConsumerState<_ConfigSection> {
  /// The resolved path shown in the row (override / Android app-private / the
  /// conventional desktop default). Null once resolved means "rclone default"
  /// (no override and no discoverable conventional path).
  String? _activePath;
  bool _resolved = false;
  bool _switching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolvePath();
  }

  /// Resolves the display path off the same [resolveConfigPath] the engine uses,
  /// falling back to the conventional default for display only.
  Future<void> _resolvePath() async {
    final override = ref.read(settingsControllerProvider).configPathOverride;
    String? androidPath;
    if (Platform.isAndroid) {
      try {
        final support = await getApplicationSupportDirectory();
        androidPath = '${support.path}/rclone.conf';
      } catch (_) {
        /* leave null → "rclone default" */
      }
    }
    final resolved =
        resolveConfigPath(
          isAndroid: Platform.isAndroid,
          androidConfigPath: androidPath,
          override: override,
        ) ??
        conventionalRcloneConfigPath();
    if (mounted) {
      setState(() {
        _activePath = resolved;
        _resolved = true;
      });
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _switching = false;
      _error = message;
    });
  }

  /// Runs `rclone config dump --config <picked>` and reports whether it loaded.
  /// Process.run returns a result even on a non-zero exit (no throw), so the
  /// catch only fires on the short timeout or a spawn failure — both "couldn't
  /// validate" → block the switch.
  Future<bool> _validatesAsConfig(String rclone, String configPath) async {
    try {
      final res = await Process.run(
        rclone,
        configDumpArgs(configPath),
      ).timeout(const Duration(seconds: 10));
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _useDifferentConfig() async {
    // Grab the messenger before any await so the post-switch confirmation never
    // touches a possibly-unmounted context.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final file = await openFile(confirmButtonText: 'Use this config');
    if (file == null || !mounted) return;
    final picked = file.path;
    setState(() {
      _switching = true;
      _error = null;
    });
    try {
      // Locate the rclone binary exactly as bootstrap does (honouring the
      // engine-path override), so we validate against the engine we'll spawn.
      final rclone = await RcloneEngine.findExisting(
        overridePath: ref.read(settingsControllerProvider).rclonePathOverride,
      );
      if (rclone == null) {
        _fail('The rclone engine was not found — set its path above first.');
        return;
      }
      // Encrypted picks are allowed and gate on launch; detect encryption from
      // the file header (out-of-band) and skip the dump probe for them.
      final encrypted = await RcloneEngine.isConfigEncrypted(
        rclone,
        configPath: picked,
      );
      if (!encrypted && !await _validatesAsConfig(rclone, picked)) {
        _fail('Not a valid rclone config (or wrong password).');
        return;
      }
      await ref
          .read(settingsControllerProvider.notifier)
          .setConfigPathOverride(picked);
      // A config-file change re-runs the encryption gate against the NEW file
      // (switchConfigAndStart), so an encrypted pick reaches the password gate
      // instead of spawning with the previous config's password.
      await ref.read(engineControllerProvider.notifier).switchConfigAndStart();
      if (!mounted) return;
      // Report the ACTUAL outcome — the engine parks failures in a phase rather
      // than throwing, so a locked/dead engine must not read as success. On
      // needsPassword the EngineGate shows its own prompt (behind this dialog),
      // so just point the user there.
      final phase = ref.read(engineControllerProvider).phase;
      final failed =
          phase != EnginePhase.ready && phase != EnginePhase.needsPassword;
      setState(() {
        _switching = false;
        _error = failed
            ? 'The engine could not start with the selected config.'
            : null;
      });
      await _resolvePath();
      if (phase == EnginePhase.ready) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Switched to the selected config.')),
        );
      } else if (phase == EnginePhase.needsPassword) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text("Enter the config's password to finish switching."),
          ),
        );
      }
    } catch (_) {
      _fail('Not a valid rclone config (or wrong password).');
    }
  }

  Future<void> _backToDefault() async {
    setState(() {
      _switching = true;
      _error = null;
    });
    await ref
        .read(settingsControllerProvider.notifier)
        .setConfigPathOverride(null);
    // Re-gate against the (plaintext) default: switchConfigAndStart clears the
    // stale password so the cache key + "Encrypted" badge don't stay bound to
    // the just-abandoned encrypted override.
    await ref.read(engineControllerProvider.notifier).switchConfigAndStart();
    if (!mounted) return;
    setState(() => _switching = false);
    await _resolvePath();
  }

  Future<void> _openFolder() async {
    final p = _activePath;
    if (p == null) return;
    await ref.read(osIntegrationProvider).revealInFileManager(p);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    // Re-resolve the display path whenever the persisted override changes — the
    // async first load, or a switch/back-to-default from another Settings view.
    ref.listen(settingsControllerProvider.select((s) => s.configPathOverride), (
      _,
      _,
    ) {
      _resolvePath();
    });
    final hasOverride =
        ref.watch(
          settingsControllerProvider.select((s) => s.configPathOverride),
        ) !=
        null;
    // "Encrypted?" reads the live engine state: the held config password is
    // non-null only for an unlocked encrypted config (unencrypted → null).
    final encrypted = ref.watch(cachePassphraseProvider) != null;
    // Remote count is the remotes list length (includes the synthetic local peer
    // on desktop), or null while the engine hasn't answered config/dump yet.
    final count = ref.watch(remotesProvider).valueOrNull?.length;
    final countLabel = count == null
        ? 'counting remotes…'
        : (count == 1 ? '1 remote' : '$count remotes');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(
          'Config location',
          help: desktop
              ? 'Where your remotes are stored. Point Airclone at a different '
                    'rclone config file, or return to the default.'
              : 'Where your remotes are stored on this device.',
        ),
        Row(
          children: [
            Icon(Icons.description_outlined, size: 16, color: c.textMuted),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                _resolved ? (_activePath ?? 'rclone default') : 'Locating…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _activePath == null ? c.textFaint : c.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            if (hasOverride) ...[
              const SizedBox(width: Space.x2),
              _CustomBadge(),
            ],
            if (desktop && _activePath != null)
              IconButton(
                onPressed: _openFolder,
                icon: const Icon(Icons.folder_open, size: 16),
                tooltip: 'Open containing folder',
                color: c.textMuted,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: Space.x1),
        Row(
          children: [
            Icon(
              encrypted ? Icons.lock_outline : Icons.lock_open_outlined,
              size: 14,
              color: c.textFaint,
            ),
            const SizedBox(width: Space.x2),
            Text(
              '${encrypted ? 'Encrypted' : 'Not encrypted'}  ·  $countLabel',
              style: TextStyle(color: c.textFaint, fontSize: 12),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.x2),
          Text(_error!, style: TextStyle(color: c.error, fontSize: 12)),
        ],
        if (desktop) ...[
          const SizedBox(height: Space.x3),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _switching ? null : _useDifferentConfig,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Use a different config file…'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: c.primary,
                ),
              ),
              if (hasOverride) ...[
                const SizedBox(width: Space.x2),
                TextButton(
                  onPressed: _switching ? null : _backToDefault,
                  child: const Text('Back to default'),
                ),
              ],
              const Spacer(),
              if (_switching)
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          // Native rclone config encryption (encrypt / change-password / remove).
          // Desktop-only: the underlying `rclone config encryption` CLI needs a
          // binary the in-process engine doesn't have.
          const ConfigEncryptionControls(),
        ],
        // Seam for the follow-up config tools (import / export / automatic
        // backups — plan §§2-4); a later agent mounts them here.
        const _ConfigToolsHook(),
      ],
    );
  }
}

/// A small "Custom" pill shown beside the path when a config override is active,
/// so it reads distinctly from the rclone default.
class _CustomBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 1),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        'Custom',
        style: TextStyle(
          color: c.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// The config tools mounted beneath the location + status block (plan §§3-4):
/// Import… / Export… wizards, plus a "Restore a backup…" row over the always-on
/// automatic backups (plan §2). Every mutating path here snapshots the active
/// config first (via [ConfigTransferController]) so a bad import/restore is one
/// tap away from undo.
class _ConfigToolsHook extends ConsumerStatefulWidget {
  const _ConfigToolsHook();

  @override
  ConsumerState<_ConfigToolsHook> createState() => _ConfigToolsHookState();
}

class _ConfigToolsHookState extends ConsumerState<_ConfigToolsHook> {
  bool _showBackups = false;
  Future<List<File>>? _backups;
  bool _restoring = false;
  String? _message;

  void _toggleBackups() {
    setState(() {
      _showBackups = !_showBackups;
      // Load lazily the first time the row is opened (and refresh on re-open).
      if (_showBackups) {
        _backups = ref.read(configTransferControllerProvider).listBackups();
      }
    });
  }

  Future<void> _restore(File f) async {
    final c = AircloneTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        title: Text(
          'Restore this backup?',
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: SizedBox(
          width: 420,
          child: Text(
            'This overwrites your active rclone config with '
            '${_backupLabel(f.path)} and restarts the engine. Your current '
            'config is snapshotted first, so this is reversible.',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          Space.x4,
          0,
          Space.x4,
          Space.x4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: c.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.error,
              foregroundColor: c.onPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _restoring = true;
      _message = null;
    });
    try {
      await ref.read(configTransferControllerProvider).restoreBackup(f.path);
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _message = 'Restored ${_backupLabel(f.path)} and restarted the engine.';
        // The restore added a safety snapshot of the just-replaced config.
        _backups = ref.read(configTransferControllerProvider).listBackups();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _message = 'Restore failed: $e';
      });
    }
  }

  /// `rclone-YYYYMMDD-HHMMSS[-n].conf` → a readable UTC label; the raw basename
  /// if it doesn't match (a hand-dropped file in the folder).
  static String _backupLabel(String path) {
    final base = path.replaceAll('\\', '/').split('/').last;
    final m = RegExp(
      r'^rclone-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})(?:-(\d+))?\.conf$',
    ).firstMatch(base);
    if (m == null) return base;
    final dup = m.group(7);
    return '${m.group(1)}-${m.group(2)}-${m.group(3)} '
        '${m.group(4)}:${m.group(5)}:${m.group(6)} UTC'
        '${dup != null ? ' (#$dup)' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.x4),
        const _SectionLabel(
          'Import & export',
          help:
              'Move your remotes to another device, or roll back to an '
              'automatic backup.',
        ),
        // A Wrap (not a Row) so the buttons flow to a second line on a narrow
        // dialog rather than overflowing.
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            // Four config-transfer actions, the same set on desktop and mobile:
            // a specific config FILE, or the offline "data-in-the-QR" method.
            OutlinedButton.icon(
              onPressed: () => showConfigImportDialog(context),
              icon: const Icon(Icons.file_download_outlined, size: 16),
              label: const Text('Import File Config'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.borderStrong),
                visualDensity: VisualDensity.compact,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => showConfigExportDialog(context),
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Export File Config'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.borderStrong),
                visualDensity: VisualDensity.compact,
              ),
            ),
            OutlinedButton.icon(
              // QR import is phone-camera only. A phone scans the QR live; a
              // computer has no camera, so it explains that and points at the
              // file-based flows (opening a file is for Import File Config).
              onPressed: () => desktop
                  ? showQrCameraUnavailableDialog(context)
                  : showScanFromDesktopSheet(context),
              icon: const Icon(Icons.qr_code_scanner, size: 16),
              label: const Text('Import QR Config'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.borderStrong),
                visualDensity: VisualDensity.compact,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => showOfflineQrDialog(context),
              icon: const Icon(Icons.qr_code_2, size: 16),
              label: const Text('Export QR Config'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.borderStrong),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        InkWell(
          onTap: _toggleBackups,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Row(
              children: [
                Icon(
                  _showBackups ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: c.textMuted,
                ),
                const SizedBox(width: Space.x1),
                Text(
                  'Restore a backup…',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                if (_restoring) ...[
                  const SizedBox(width: Space.x2),
                  const SizedBox(
                    height: 12,
                    width: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_showBackups) _backupsList(c),
        if (_message != null) ...[
          const SizedBox(height: Space.x2),
          Text(_message!, style: TextStyle(color: c.textFaint, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _backupsList(AircloneColors c) => FutureBuilder<List<File>>(
    future: _backups,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return Padding(
          padding: const EdgeInsets.only(top: Space.x2, left: Space.x5),
          child: Text(
            'Loading…',
            style: TextStyle(color: c.textFaint, fontSize: 12),
          ),
        );
      }
      final files = snap.data ?? const <File>[];
      if (files.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: Space.x2, left: Space.x5),
          child: Text(
            'No backups yet — one is made automatically before an import, '
            'replace, or config switch.',
            style: TextStyle(color: c.textFaint, fontSize: 12),
          ),
        );
      }
      return Column(
        children: [
          for (final f in files)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1, left: Space.x5),
              child: Row(
                children: [
                  Icon(Icons.history, size: 14, color: c.textFaint),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      _backupLabel(f.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _restoring ? null : () => _restore(f),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Restore'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
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

/// Desktop engine choice: spawn `rclone rcd` (Binary), embed rclone in-process
/// via librclone (In-process), or Auto (pick per platform + availability).
/// Changing it tears down + restarts the engine ([switchEngineAndStart]). The
/// in-process engine only runs when its library was bundled in this build.
class _EngineModeSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_EngineModeSection> createState() => _EngineModeSectionState();
}

class _EngineModeSectionState extends ConsumerState<_EngineModeSection> {
  bool _switching = false;
  // Resolved once: whether this build shipped the in-process engine library.
  late final bool _libAvailable = File(defaultLibrclonePath()).existsSync();

  Future<void> _select(EngineMode mode) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      await ref.read(settingsControllerProvider.notifier).setEngineMode(mode);
      await ref.read(engineControllerProvider.notifier).switchEngineAndStart();
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final mode = ref.watch(
      settingsControllerProvider.select((s) => s.engineMode),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(
          'Engine',
          help: _libAvailable
              ? 'Binary runs rclone as a separate process; In-process embeds '
                    'rclone inside Airclone (no subprocess). Auto picks for you.'
              : 'Runs rclone as a separate process. The in-process engine was '
                    'not bundled in this build.',
        ),
        SegmentedButton<EngineMode>(
          segments: const [
            ButtonSegment(
              value: EngineMode.auto,
              icon: Icon(Icons.auto_mode_outlined, size: 16),
              label: Text('Auto'),
            ),
            ButtonSegment(
              value: EngineMode.binary,
              icon: Icon(Icons.terminal_outlined, size: 16),
              label: Text('Binary'),
            ),
            ButtonSegment(
              value: EngineMode.inProcess,
              icon: Icon(Icons.memory_outlined, size: 16),
              label: Text('In-process'),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: _switching ? null : (sel) => _select(sel.first),
        ),
        if (_switching) ...[
          const SizedBox(height: Space.x2),
          Text(
            'Restarting engine…',
            style: TextStyle(color: c.textFaint, fontSize: 11),
          ),
        ] else if (!_libAvailable && mode == EngineMode.inProcess) ...[
          const SizedBox(height: Space.x2),
          Text(
            'The in-process engine is not available in this build — Airclone '
            'will use the binary engine instead.',
            style: TextStyle(color: c.warning, fontSize: 11),
          ),
        ],
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
  bool _bundled =
      false; // engine ships beside the app (Store MSIX) — no in-app update

  @override
  void initState() {
    super.initState();
    // A build that bundles the engine (the Store MSIX) must not offer an in-app
    // download/update — it updates only when the app itself updates. Resolve the
    // signal (a binary beside the app) once and hide the update controls.
    RcloneEngine.bundledDesktopBinary().then((p) {
      if (mounted && p != null) setState(() => _bundled = true);
    });
  }

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
            if (_bundled)
              Text(
                'Bundled with the app',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              )
            else if (busy)
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

/// Opt-in to storing the encrypted-config password in the OS credential vault so
/// the config can unlock without re-typing — on desktop for scheduled/background
/// runs, and everywhere as the prerequisite for biometric release (below).
/// Default OFF and security-sensitive, so the sub-label is deliberately blunt
/// about the exposure. Toggling OFF wipes any stored password immediately;
/// toggling ON captures the currently-unlocked password now (if any) so it takes
/// effect without waiting for the next unlock.
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
                "Stored in your device's secure credential store (Windows "
                'Credential Manager / macOS Keychain / Linux Secret Service / '
                'Android Keystore / iOS Keychain) so the config can unlock '
                'without re-typing; anyone who can unlock your device can '
                'recover it. Toggling off clears the stored password immediately.',
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

/// Phone-first: RELEASE the vault-stored config password with a fingerprint/face
/// prompt at launch instead of the typing gate (plan §6). Rendered ONLY where the
/// device actually has an enrolled biometric — [BiometricUnlock.available] — so
/// it hides itself on desktop (until local_auth_windows) and on phones with no
/// biometric set up. Enabled ONLY once "Remember config password" is on, because
/// biometric gates the release of a *stored* secret; with nothing stored the
/// toggle is meaningless, so it disables and explains rather than lying.
///
/// The sub-label is deliberately honest about the threat model: this is a
/// casual-access gate on an already-unlocked device, NOT protection against
/// someone who knows the device passcode (they can reach the keystore anyway).
class _BiometricUnlockSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BiometricUnlockSection> createState() =>
      _BiometricUnlockSectionState();
}

class _BiometricUnlockSectionState
    extends ConsumerState<_BiometricUnlockSection> {
  // Null while the async capability probe is in flight; the section renders
  // nothing until it resolves so the switch never flickers in then out. The
  // probe is guarded in the seam, so a throwing platform simply resolves false.
  bool? _available;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final ok = await ref.read(biometricUnlockProvider).available();
    if (mounted) setState(() => _available = ok);
  }

  @override
  Widget build(BuildContext context) {
    // Hidden entirely until we know the device has a biometric — and hidden for
    // good where it doesn't (desktop today, or no enrolled fingerprint/face).
    // Collapsing to a zero-size box (no leading gap) keeps the Security group
    // tight where only "Remember config password" applies.
    if (_available != true) return const SizedBox.shrink();
    final c = AircloneTheme.of(context);
    final remember = ref.watch(rememberConfigPasswordProvider);
    final on = ref.watch(biometricUnlockOptInProvider);
    return Padding(
      padding: const EdgeInsets.only(top: Space.x4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unlock with fingerprint / face',
                  style: TextStyle(
                    // Dimmed while inert (no stored password to release).
                    color: remember ? c.text : c.textFaint,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remember
                      ? 'Adds a fingerprint or face prompt to unlock the config '
                            'on launch — your config password still works as a '
                            'fallback. Protects against casual access on an '
                            'unlocked device — not against someone who knows your '
                            'device passcode.'
                      : "Turn on 'Remember config password' first — "
                            'biometric unlock releases the stored password, so '
                            'with nothing stored there is nothing to unlock.',
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.x3),
          Switch(
            // Meaningless without a stored password: show off and disable until
            // "Remember config password" is on (gating a secret that isn't there
            // would just prompt for a fingerprint that releases nothing).
            value: on && remember,
            onChanged: remember
                ? (v) => ref.read(biometricUnlockOptInProvider.notifier).set(v)
                : null,
          ),
        ],
      ),
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
