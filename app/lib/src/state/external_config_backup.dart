/// An opt-in copy of the rclone config kept OUTSIDE the app sandbox, so a
/// reinstall — or a new phone — does not cost the user every remote they own.
///
/// ## Why this exists, and why it is off by default
///
/// On a phone `rclone.conf` lives in the app's private storage and the manifest
/// sets `allowBackup="false"`, both deliberately: cloud credentials must not ride
/// along in an ADB or cloud backup where they could be read off-device. Verified
/// on Android 15 — uninstall then reinstall leaves no app data at all. The cost is
/// that a reinstall is total data loss, which is a genuinely bad surprise.
///
/// This feature is the escape hatch, and the shape of it is the whole point:
///
///  * **Off by default.** No file exists outside the sandbox unless asked for.
///  * **Encrypted is the real answer.** With a passphrase the backup is an ACFG2
///    envelope (AES-256-GCM over Argon2id, the same format as the encrypted
///    export — see config_io.dart). Shared storage is world-readable to any app
///    holding storage permission, so a passphrase is what makes putting the file
///    there defensible at all.
///  * **Unencrypted is available but never the default and never quiet.** Some
///    users genuinely want a plain `rclone.conf` they can copy to a desktop. They
///    may have it, behind an explicit second confirmation that says plainly what
///    it means. See [ExternalBackupMode.plaintext].
///
/// ## Where the file goes
///
/// `<shared storage>/Airclone/`. Files there survive uninstall, unlike
/// `Android/data/<pkg>/` (which the OS deletes with the app). Writing there needs
/// All Files Access, which Airclone already requests for its `local` backend.
///
/// Android-only today. Desktop needs none of this (its config lives outside the
/// app already) and iOS has no equivalent shared location — see [backupSupported].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_native.dart';
import 'config_io.dart';
import 'config_transfer_controller.dart';
import 'diagnostics.dart';
import 'local_locations.dart';
import 'remotes_provider.dart';

/// How (and whether) the config is mirrored outside the sandbox.
enum ExternalBackupMode {
  /// No copy exists outside the app. Uninstalling loses the config. The default.
  off,

  /// An ACFG2 envelope under a user passphrase. The recommended setting.
  encrypted,

  /// A plain `rclone.conf`. Readable by anything on the device that can read
  /// shared storage. Only reachable through an explicit danger confirmation.
  plaintext,
}

/// The directory the backup lives in, under [storageRoot]. Pure for testing.
String externalBackupDir(String storageRoot) => '$storageRoot/Airclone';

/// Filenames, one per mode, so both can be probed on a fresh install without
/// knowing which mode the user had chosen before the uninstall.
///
/// The plaintext copy is deliberately called `rclone.conf`: if Airclone is gone,
/// it is still a file rclone itself — or a desktop Airclone — opens directly.
const String kEncryptedBackupName = 'airclone-config.acfg';
const String kPlaintextBackupName = 'rclone.conf';

/// The file path for [mode] within [dir]. Returns null for [ExternalBackupMode.off].
String? externalBackupPath(String dir, ExternalBackupMode mode) =>
    switch (mode) {
      ExternalBackupMode.off => null,
      ExternalBackupMode.encrypted => '$dir/$kEncryptedBackupName',
      ExternalBackupMode.plaintext => '$dir/$kPlaintextBackupName',
    };

/// Whether this platform can keep a copy outside the sandbox at all.
///
/// Android only. Desktop configs already live outside the app and survive a
/// reinstall untouched, so the feature would be noise; iOS has no shared
/// location a file can outlive the app in (a future iOS build would want an
/// iCloud/Files-app export instead, which is a different design).
bool get backupSupported => Platform.isAndroid;

/// A backup found on disk, ready to hand to the import wizard.
@immutable
class FoundBackup {
  const FoundBackup({
    required this.path,
    required this.encrypted,
    required this.modified,
    required this.bytes,
  });

  final String path;

  /// True for an ACFG2 envelope (the import wizard will ask for its passphrase).
  final bool encrypted;
  final DateTime modified;
  final List<int> bytes;

  String get name => path.split('/').last;
}

/// Everything the settings UI needs to render, in one immutable snapshot.
@immutable
class ExternalBackupState {
  const ExternalBackupState({
    this.mode = ExternalBackupMode.off,
    this.lastWrittenAt,
    this.error,
    this.busy = false,
  });

  final ExternalBackupMode mode;

  /// When the file was last written, for an honest "updated …" line. Null when
  /// off, or when the mode was restored from prefs but nothing has been written
  /// this run.
  final DateTime? lastWrittenAt;

  /// The last failure, surfaced inline. A backup that silently stopped working
  /// is worse than no backup, because the user believes they are covered.
  final String? error;

  final bool busy;

  bool get enabled => mode != ExternalBackupMode.off;

  ExternalBackupState copyWith({
    ExternalBackupMode? mode,
    DateTime? lastWrittenAt,
    String? error,
    bool? busy,
    bool clearError = false,
    bool clearWritten = false,
  }) => ExternalBackupState(
    mode: mode ?? this.mode,
    lastWrittenAt: clearWritten ? null : (lastWrittenAt ?? this.lastWrittenAt),
    error: clearError ? null : (error ?? this.error),
    busy: busy ?? this.busy,
  );
}

/// The passphrase slot in the OS credential vault.
///
/// Needed so the backup can refresh itself when remotes change without asking
/// the user to retype anything. The vault is app-private and is destroyed with
/// the app on uninstall — which is correct and not a limitation: after a
/// reinstall the user types the passphrase once to restore, exactly as they
/// should have to.
class ExternalBackupPassphraseVault {
  ExternalBackupPassphraseVault(this._storage);

  static const String key = 'airclone.externalBackupPassphrase';

  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null; // vault unavailable — caller reports "re-enter passphrase"
    }
  }

  Future<bool> save(String passphrase) async {
    try {
      await _storage.write(key: key, value: passphrase);
      return true;
    } catch (e) {
      debugPrint('ExternalBackupPassphraseVault.save failed: $e');
      return false;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('ExternalBackupPassphraseVault.clear failed: $e');
    }
  }
}

final externalBackupVaultProvider = Provider<ExternalBackupPassphraseVault>(
  (ref) => ExternalBackupPassphraseVault(const FlutterSecureStorage()),
);

/// Seals `(plaintext, passphrase)` — a top-level function so it can be handed to
/// [compute] and run the memory-hard KDF off the UI isolate. Both fields of the
/// record are Strings, so the payload is sendable as-is.
Future<Uint8List> _sealForBackup((String, String) args) =>
    sealConfigEnvelope(args.$1, args.$2);

/// Thrown by the controller for a failure the user can act on.
class ExternalBackupError implements Exception {
  const ExternalBackupError(this.message);
  final String message;
  @override
  String toString() => 'ExternalBackupError: $message';
}

/// Owns the external copy: the chosen mode, the writes, and the restore probe.
class ExternalConfigBackup extends Notifier<ExternalBackupState> {
  static const _modeKey = 'external_backup_mode';

  /// SHA-256 of the last config we wrote, so an unchanged config is not
  /// re-sealed on every remotes refresh (Argon2id at 64 MiB is not free, and a
  /// pointless rewrite would churn the file the user may be copying).
  static const _digestKey = 'external_backup_digest';

  Future<void>? _loading;

  @override
  ExternalBackupState build() {
    // Any change to the remotes list means the config was mutated — an add,
    // edit, delete, import, or restore all invalidate it. That is the trigger
    // for keeping the external copy current, with the digest check below making
    // a no-op cheap.
    ref.listen(remotesProvider, (_, next) {
      if (next.hasValue && state.enabled) unawaited(refreshIfStale());
    });
    ensureLoaded();
    return const ExternalBackupState();
  }

  /// Awaitable hydration of the persisted mode. Idempotent, and awaited by any
  /// caller that decides something irreversible from the mode.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    if (!backupSupported) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_modeKey);
      final mode = ExternalBackupMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => ExternalBackupMode.off,
      );
      state = state.copyWith(mode: mode);
    } catch (_) {
      // keep the default (off) — failing closed is the safe direction here
    }
  }

  Future<void> _persistMode(ExternalBackupMode mode) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_modeKey, mode.name);
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _persistDigest(String? digest) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (digest == null) {
        await p.remove(_digestKey);
      } else {
        await p.setString(_digestKey, digest);
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<String?> _readDigest() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_digestKey);
    } catch (_) {
      return null;
    }
  }

  // --- Enable / disable ------------------------------------------------------

  /// Turns on the ENCRYPTED backup under [passphrase] and writes it immediately,
  /// so the switch flipping to on always means a file actually exists. Throws
  /// [ExternalBackupError] on failure, leaving the mode off.
  Future<void> enableEncrypted(String passphrase) async {
    if (passphrase.isEmpty) {
      throw const ExternalBackupError('Enter a passphrase.');
    }
    final saved = await ref.read(externalBackupVaultProvider).save(passphrase);
    if (!saved) {
      throw const ExternalBackupError(
        "This device's secure storage refused to hold the passphrase, so the "
        'backup could not be kept up to date automatically.',
      );
    }
    await _enable(ExternalBackupMode.encrypted, passphrase);
  }

  /// Turns on the UNENCRYPTED backup. The caller is responsible for having shown
  /// the danger confirmation first — this method does not ask.
  Future<void> enablePlaintext() async {
    // No passphrase is in play, so nothing should linger in the vault claiming
    // otherwise.
    await ref.read(externalBackupVaultProvider).clear();
    await _enable(ExternalBackupMode.plaintext, null);
  }

  Future<void> _enable(ExternalBackupMode mode, String? passphrase) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      // Writing first means the switch can never report "on" without a file.
      await _write(mode, passphrase);
      // Only one copy may exist: switching modes must not leave the previous
      // file behind — above all a stale PLAINTEXT config after the user moved to
      // an encrypted backup, which would silently keep their secrets exposed.
      await _deleteOtherModes(keep: mode);
      await _persistMode(mode);
      state = state.copyWith(
        mode: mode,
        lastWrittenAt: DateTime.now(),
        busy: false,
      );
    } catch (e) {
      state = state.copyWith(busy: false, error: _message(e));
      rethrow;
    }
  }

  /// Turns the feature off and REMOVES the external file — leaving it behind
  /// would mean the user opted out while their credentials stayed on disk.
  Future<void> disable() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _deleteOtherModes(keep: ExternalBackupMode.off);
      await ref.read(externalBackupVaultProvider).clear();
      await _persistMode(ExternalBackupMode.off);
      await _persistDigest(null);
      state = const ExternalBackupState();
    } catch (e) {
      state = state.copyWith(busy: false, error: _message(e));
      rethrow;
    }
  }

  // --- Writing ---------------------------------------------------------------

  /// Rewrites the backup now, whether or not the config changed.
  Future<void> backupNow() async {
    if (!state.enabled) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _write(state.mode, await _passphraseFor(state.mode));
      state = state.copyWith(lastWrittenAt: DateTime.now(), busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, error: _message(e));
      rethrow;
    }
  }

  /// Rewrites only if the live config differs from what was last written.
  /// Never throws — this runs unattended off the remotes listener, so a failure
  /// is recorded in [ExternalBackupState.error] and the diagnostics log rather
  /// than thrown into whatever triggered the refresh.
  Future<void> refreshIfStale() async {
    if (!state.enabled || state.busy) return;
    try {
      final ini = await _serializeActiveConfig();
      final digest = sha256.convert(utf8.encode(ini)).toString();
      if (digest == await _readDigest()) return;
      await _write(
        state.mode,
        await _passphraseFor(state.mode),
        preSerialized: ini,
      );
      state = state.copyWith(lastWrittenAt: DateTime.now(), clearError: true);
    } catch (e) {
      logDiagnostic(
        DiagLevel.warning,
        'external-backup',
        'Automatic backup refresh failed',
        detail: e,
      );
      state = state.copyWith(error: _message(e));
    }
  }

  Future<String?> _passphraseFor(ExternalBackupMode mode) async {
    if (mode != ExternalBackupMode.encrypted) return null;
    final pass = await ref.read(externalBackupVaultProvider).read();
    if (pass == null || pass.isEmpty) {
      throw const ExternalBackupError(
        'The backup passphrase is no longer available on this device. Turn the '
        'backup off and on again to set a new one.',
      );
    }
    return pass;
  }

  Future<String> _serializeActiveConfig() async {
    final model = await ref
        .read(configTransferControllerProvider)
        .activeConfigModel();
    return serializeIni(model);
  }

  /// Serializes, seals (when encrypted), and writes the file atomically.
  ///
  /// `.part`-then-rename matters more here than usual: this file is the user's
  /// only copy after an uninstall, so a write interrupted by the OS killing the
  /// app must never leave a truncated config where a complete one was.
  Future<void> _write(
    ExternalBackupMode mode,
    String? passphrase, {
    String? preSerialized,
  }) async {
    if (!backupSupported) {
      throw const ExternalBackupError(
        'Keeping a copy outside the app is only available on Android.',
      );
    }
    final ini = preSerialized ?? await _serializeActiveConfig();
    final bytes = mode == ExternalBackupMode.encrypted
        // Off the UI isolate: Argon2id at 64 MiB is pure Dart and takes long
        // enough to drop frames. That is tolerable for a user-initiated export
        // behind a spinner, but this also runs AUTOMATICALLY whenever remotes
        // change — right after an operation whose own progress UI is on screen.
        ? await compute(_sealForBackup, (ini, passphrase!))
        : utf8.encode(ini);

    final dir = Directory(externalBackupDir(androidStorageRoot));
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (e) {
      throw ExternalBackupError(
        "Couldn't create ${dir.path}. Grant Airclone access to all files and "
        'try again. ($e)',
      );
    }
    final target = File(externalBackupPath(dir.path, mode)!);
    final partial = File('${target.path}.part');
    try {
      await partial.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    } catch (e) {
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {
        // best-effort cleanup of the temp file
      }
      throw ExternalBackupError("Couldn't write ${target.path}. ($e)");
    }
    await _persistDigest(sha256.convert(utf8.encode(ini)).toString());
  }

  /// Removes every backup file except [keep]'s (pass [ExternalBackupMode.off] to
  /// remove them all). Best-effort per file, but a failure to delete a PLAINTEXT
  /// file is reported — silently leaving readable credentials behind would
  /// contradict what the UI just told the user.
  Future<void> _deleteOtherModes({required ExternalBackupMode keep}) async {
    final dir = externalBackupDir(androidStorageRoot);
    for (final mode in ExternalBackupMode.values) {
      if (mode == keep || mode == ExternalBackupMode.off) continue;
      final path = externalBackupPath(dir, mode);
      if (path == null) continue;
      final file = File(path);
      try {
        if (await file.exists()) await file.delete();
      } catch (e) {
        if (mode == ExternalBackupMode.plaintext) {
          throw ExternalBackupError(
            "Couldn't remove the unencrypted backup at $path — delete it "
            'yourself; it still contains your credentials. ($e)',
          );
        }
      }
    }
  }

  String _message(Object e) =>
      e is ExternalBackupError ? e.message : e.toString();
}

final externalBackupProvider =
    NotifierProvider<ExternalConfigBackup, ExternalBackupState>(
      ExternalConfigBackup.new,
    );

// --- Restore -----------------------------------------------------------------

/// Looks for a backup left behind by a previous install, newest first when both
/// kinds exist. Returns null when there is none (or off Android).
///
/// Reading here is deliberately independent of the enabled mode: after a
/// reinstall the app has NO settings at all, so the only way to find the file is
/// to look for it.
Future<FoundBackup?> findExternalBackup() async {
  if (!backupSupported) return null;
  final dir = externalBackupDir(androidStorageRoot);
  final candidates = <FoundBackup>[];
  for (final mode in [
    ExternalBackupMode.encrypted,
    ExternalBackupMode.plaintext,
  ]) {
    final path = externalBackupPath(dir, mode)!;
    try {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      candidates.add(
        FoundBackup(
          path: path,
          // Trust the CONTENT, not the filename: a file the user renamed or
          // copied in by hand still classifies correctly.
          encrypted: detectConfigFormat(bytes) == ConfigFormat.aircloneEnvelope,
          modified: (await file.stat()).modified,
          bytes: bytes,
        ),
      );
    } catch (_) {
      // Unreadable (no storage permission yet, or removed mid-probe) — skip it.
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.modified.compareTo(a.modified));
  return candidates.first;
}

/// Whether a backup FILE is on the device, independent of whether the feature is
/// switched on.
///
/// These two genuinely come apart, and the gap matters: the mode lives in
/// SharedPreferences, which uninstall wipes, while the backup file survives. So
/// immediately after a reinstall the setting reads "off" next to a perfectly
/// good backup — and a user who has just restored from it would otherwise
/// believe they are still covered while nothing is being kept up to date.
/// Settings uses this to say so and offer to resume.
final externalBackupFileProvider = FutureProvider<FoundBackup?>((ref) async {
  if (!backupSupported) return null;
  final granted = await ref.watch(allFilesAccessProvider.future);
  if (!granted) return null;
  // Re-probe when the feature's own state changes — enabling writes the file,
  // disabling deletes it.
  ref.watch(externalBackupProvider);
  return findExternalBackup();
});

/// Whether a restorable backup exists AND the live config is empty — i.e. this
/// looks like a fresh install after an uninstall. Drives the "we found your
/// remotes" offer, which is the entire point of the feature: a user who
/// reinstalls should get their remotes back without having to know this setting
/// existed.
///
/// Watches All Files Access as well as the remotes list, and that is
/// load-bearing rather than tidy: a FRESH install has not been granted storage
/// access yet, so the very first probe cannot read shared storage and finds
/// nothing. Re-running when the grant lands is what makes the offer appear for
/// the user it was built for — the one who just reinstalled.
final restorableBackupProvider = FutureProvider<FoundBackup?>((ref) async {
  if (!backupSupported) return null;
  final granted = await ref.watch(allFilesAccessProvider.future);
  if (!granted) return null;
  final remotes = await ref.watch(remotesProvider.future);
  // A config that already has remotes is not a fresh install; never nag.
  if (remotes.any((r) => !r.isLocal)) return null;
  return findExternalBackup();
});
