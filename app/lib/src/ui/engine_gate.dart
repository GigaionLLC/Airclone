import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/android_native.dart';
import '../state/engine_controller.dart';
import 'theme/tokens.dart';

/// Shown until the engine is ready (locating / not-installed / provisioning /
/// error). Shared by the desktop work area and the phone shell's Files tab.
class EngineGate extends ConsumerWidget {
  const EngineGate({super.key, required this.engine});
  final EngineUi engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    if (engine.phase == EnginePhase.needsPassword) {
      return _PasswordGate(message: engine.message);
    }
    final notInstalled = engine.phase == EnginePhase.notInstalled;
    final error = engine.phase == EnginePhase.error;
    final busy =
        engine.phase == EnginePhase.locating ||
        engine.phase == EnginePhase.provisioning ||
        engine.phase == EnginePhase.starting;

    // On Android the engine is bundled in the APK: there is nothing to
    // download, so the gate only ever offers a re-check.
    final canDownload = !Platform.isAndroid;
    // Scroll view inside the Center: centered when it fits, scrollable when a
    // phone's soft keyboard (or a tiny window) squeezes the viewport.
    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(Space.x4),
          padding: const EdgeInsets.all(Space.x6),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                error ? Icons.error_outline : Icons.cloud_sync_outlined,
                size: 40,
                color: error ? c.error : c.primary,
              ),
              const SizedBox(height: Space.x4),
              Text(
                error
                    ? 'Engine error'
                    : notInstalled
                    ? 'Set up the rclone engine'
                    : 'Starting Airclone',
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.x2),
              Text(
                engine.message ??
                    (notInstalled
                        ? 'Airclone uses the rclone engine. Download it now — nothing else to install.'
                        : 'Please wait…'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: Space.x5),
              if (busy)
                const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if ((notInstalled || error) && canDownload)
                FilledButton.icon(
                  onPressed: () => ref
                      .read(engineControllerProvider.notifier)
                      .installAndStart(),
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(
                    error ? 'Retry download' : 'Download rclone engine',
                  ),
                ),
              if (error) ...[
                const SizedBox(height: Space.x2),
                TextButton(
                  onPressed: () =>
                      ref.read(engineControllerProvider.notifier).bootstrap(),
                  child: Text(
                    canDownload ? 'Re-check for a local rclone' : 'Try again',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Password prompt for an encrypted rclone config. The password is sent to the
/// controller (→ RCLONE_CONFIG_PASS) and never persisted.
class _PasswordGate extends ConsumerStatefulWidget {
  const _PasswordGate({this.message});
  final String? message;

  @override
  ConsumerState<_PasswordGate> createState() => _PasswordGateState();
}

class _PasswordGateState extends ConsumerState<_PasswordGate> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    if (_c.text.isEmpty) return;
    ref.read(engineControllerProvider.notifier).unlockAndStart(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    // Scroll view inside the Center: the soft keyboard shrinks the viewport
    // right when this card's password field needs to stay reachable.
    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(Space.x4),
          padding: const EdgeInsets.all(Space.x6),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: c.primary),
              const SizedBox(height: Space.x4),
              Text(
                'Unlock your config',
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.x2),
              Text(
                widget.message ?? 'Your rclone config is encrypted.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: Space.x5),
              TextField(
                controller: _c,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Config password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: Space.x4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Android: a tappable prompt to grant All Files Access, shown until granted.
/// Watches the app lifecycle so returning from the settings screen re-checks
/// the permission and dismisses the banner without a restart.
class StorageAccessBanner extends ConsumerStatefulWidget {
  const StorageAccessBanner({super.key});

  @override
  ConsumerState<StorageAccessBanner> createState() =>
      _StorageAccessBannerState();
}

class _StorageAccessBannerState extends ConsumerState<StorageAccessBanner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(allFilesAccessProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.x3),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: requestAllFilesAccess,
        child: Container(
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_off_outlined, size: 18, color: c.primary),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  'Allow file access to browse this phone\'s storage',
                  style: TextStyle(color: c.text, fontSize: 12),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
