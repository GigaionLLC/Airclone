import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../rclone/rclone_client.dart';
import '../rclone/rclone_engine.dart';
import '../rclone/windows_child_job.dart';
import 'cache_crypto.dart';
import 'config_backups.dart';
import 'config_encryption.dart';
import 'config_io.dart';
import 'engine_controller.dart';
import 'jobs_controller.dart';
import 'remotes_provider.dart';
import 'settings_controller.dart';

/// The import/export ORCHESTRATION over the pure config-IO seam (config_io.dart)
/// and the always-on backups (config_backups.dart) — the runtime half of the
/// config-portability wizards (dev/plans/config-portability-plan.md §3/§4). The
/// pure parsing/envelope/closure/planning logic stays in config_io.dart so it is
/// exhaustively unit-tested without an engine; THIS layer wires those results to
/// the live RC seam (config/create, config/dump), the backups ring, the active
/// config file, and the engine restart.
///
/// Design notes:
///  - The genuinely side-effect-heavy steps (the merge loop, the RC-seam replace,
///    the plaintext file overwrite) are extracted as pure top-level functions
///    ([mergeRemotes], [replaceViaRcd], [replaceConfigFile],
///    [rcloneEncryptedDumpCommand]) so their argv/ordering/error-handling is
///    unit-tested WITHOUT a real engine, backups dir, or subprocess.
///  - Secrets (passphrases, an rclone config password) are NEVER logged, never
///    stored in provider state, and never placed on a subprocess argv — the
///    rclone config password is handed to the decrypt subprocess out-of-band via
///    the `RCLONE_CONFIG_PASS` environment variable only.

// --- Errors ------------------------------------------------------------------

/// A user-actionable failure in an import/export step (engine missing, active
/// config not locatable). Carries a friendly [message] the dialogs surface
/// inline; distinct from the crypto-level [WrongPassphrase]/[CorruptEnvelope]
/// (config_io.dart) and [WrongRcloneConfigPassword] below.
class ConfigTransferError implements Exception {
  const ConfigTransferError(this.message);
  final String message;
  @override
  String toString() => 'ConfigTransferError: $message';
}

/// A password-encrypted `rclone.conf` failed to decrypt — a wrong password (or a
/// config this engine can't read). Typed + free of any password text so the
/// import dialog can offer a friendly retry without ever echoing the secret.
class WrongRcloneConfigPassword implements Exception {
  const WrongRcloneConfigPassword();
  @override
  String toString() => 'WrongRcloneConfigPassword';
}

// --- Merge report ------------------------------------------------------------

/// The outcome of a merge-import apply: exactly which remotes were created and
/// which failed, so the UI can report a partial apply honestly rather than
/// claiming success while a remote silently didn't land (plan §3: "never
/// half-apply silently"). [created] holds the FINAL names written (a collision's
/// rename target); [failed] pairs each un-created name with its error.
@immutable
class MergeReport {
  const MergeReport({required this.created, required this.failed});

  final List<String> created;
  final List<({String name, String error})> failed;

  bool get allOk => failed.isEmpty;
}

// --- Pure helpers (extracted for unit tests; no engine/backups/subprocess) ----

/// The subprocess vector for decrypting a password-encrypted `rclone.conf`: run
/// `rclone config dump --config <tempPath>` with the password supplied ONLY via
/// the `RCLONE_CONFIG_PASS` environment variable (never on the argv, never
/// logged). Pure so the exact argv+env is asserted in a unit test without
/// spawning a process. Reuses [configDumpArgs] so it stays identical to the
/// settings pre-flight probe vector.
({List<String> args, Map<String, String> env}) rcloneEncryptedDumpCommand(
  String tempConfigPath,
  String password,
) => (
  args: configDumpArgs(tempConfigPath),
  env: {'RCLONE_CONFIG_PASS': password},
);

/// Builds the `config/create` request body that re-creates one remote from its
/// stored key/values during an import. [targetName] is the final name (a
/// collision's rename target, or the original). [section] is the remote's
/// dumped/parsed config; its `type` becomes the top-level type and every other
/// key becomes a parameter.
///
/// `noObscure: true` is load-bearing: imported password values are ALREADY in
/// rclone's obscured storage form (that is how `config dump`/`rclone.conf` hold
/// them), so re-obscuring them would corrupt them. We store them verbatim.
/// `nonInteractive: true` (and NOT `all`) applies the supplied parameters
/// without triggering the interactive question machine — a bulk import supplies
/// the full parameter set already.
Map<String, dynamic> importCreateBody(
  String targetName,
  Map<String, String> section,
) {
  final params = <String, dynamic>{
    for (final e in section.entries)
      if (e.key != 'type') e.key: e.value,
  };
  return {
    'name': targetName,
    'type': section['type'] ?? '',
    'parameters': params,
    'opt': {'nonInteractive': true, 'noObscure': true},
  };
}

/// Applies a planned merge: snapshots the active config via [backup] FIRST, then
/// re-creates each incoming remote through the RC seam ([client]'s
/// `config/create`). One [ImportDecision] → one create under its final name
/// (`renamedTo ?? name`). Every remote is attempted independently and its
/// outcome recorded, so one bad remote never aborts the rest and the result is a
/// faithful per-remote [MergeReport] (plan §3: report which merged, which
/// failed). A create that returns an rclone `Error`, throws, or comes back
/// wanting interactive setup is counted as a failure — never a silent success.
///
/// Pure of Riverpod/backups/engine wiring (all injected) so the create-per-rename
/// mapping and the backup-before-create ordering are unit-tested directly.
Future<MergeReport> mergeRemotes({
  required RcloneClient client,
  required ConfigModel incoming,
  required List<ImportDecision> plan,
  required Future<void> Function() backup,
}) async {
  // Trust substrate: back up BEFORE any create so a bad merge is one restore away.
  await backup();
  final created = <String>[];
  final failed = <({String name, String error})>[];
  for (final d in plan) {
    final target = d.renamedTo ?? d.name;
    final section = incoming[d.name] ?? const <String, String>{};
    try {
      final res = await client.rpc(
        'config/create',
        importCreateBody(target, section),
      );
      final err = (res['Error'] as String?) ?? '';
      final nextState = res['State'] as String?;
      if (err.isNotEmpty) {
        failed.add((name: target, error: err));
      } else if (nextState != null && nextState.isNotEmpty) {
        // A pending question means the remote wasn't fully configured from the
        // supplied parameters — surface it rather than claim it landed.
        failed.add((
          name: target,
          error: 'needs interactive setup (not supported for import)',
        ));
      } else {
        created.add(target);
      }
    } on RcloneException catch (e) {
      failed.add((name: target, error: e.message));
    } catch (e) {
      failed.add((name: target, error: '$e'));
    }
  }
  return MergeReport(created: created, failed: failed);
}

/// Applies a REPLACE through the live RC seam instead of a raw file write: create
/// every incoming remote, then delete every existing remote that isn't in the
/// incoming set, all via [client] (`config/create` + `config/delete`). This is
/// the path for an ENCRYPTED active config — rcd re-encrypts the config on every
/// save using its held launch password, so replacing an encrypted config keeps
/// it encrypted at rest with ZERO plaintext ever touching disk (a raw file write
/// would downgrade it; and `rclone config encryption set` can't take the new
/// password non-interactively across versions, so the subprocess route is not
/// reliable). Ordering is deliberate: creates run FIRST (a same-named remote is
/// overwritten, so nothing the user wants ever disappears mid-op), then only the
/// now-stale remotes are deleted. [backup] snapshots the (still-encrypted) config
/// FIRST so a bad replace is one restore away. Pure of Riverpod/engine wiring so
/// the create-then-prune ordering + report are unit-tested with a fake client.
Future<MergeReport> replaceViaRcd({
  required RcloneClient client,
  required ConfigModel incoming,
  required List<String> existingNames,
  required Future<void> Function() backup,
}) async {
  // Trust substrate: snapshot the current (encrypted) config before mutating it.
  await backup();
  final created = <String>[];
  final failed = <({String name, String error})>[];
  // Phase 1 — create/overwrite every incoming remote. A plain merge plan (no
  // renames) because Replace means "incoming wins": a collision overwrites.
  final plan = [
    for (final name in incoming.keys)
      ImportDecision(
        name: name,
        type: incoming[name]?['type'] ?? '',
        collision: false,
      ),
  ];
  for (final d in plan) {
    final section = incoming[d.name] ?? const <String, String>{};
    try {
      final res = await client.rpc(
        'config/create',
        importCreateBody(d.name, section),
      );
      final err = (res['Error'] as String?) ?? '';
      final nextState = res['State'] as String?;
      if (err.isNotEmpty) {
        failed.add((name: d.name, error: err));
      } else if (nextState != null && nextState.isNotEmpty) {
        failed.add((
          name: d.name,
          error: 'needs interactive setup (not supported for import)',
        ));
      } else {
        created.add(d.name);
      }
    } on RcloneException catch (e) {
      failed.add((name: d.name, error: e.message));
    } catch (e) {
      failed.add((name: d.name, error: '$e'));
    }
  }
  // Phase 2 — prune remotes that exist now but aren't in the incoming set. Only
  // reached once creates are done, so the destructive step never strands a
  // wanted remote. A delete failure is reported, not fatal (backup covers it).
  final incomingNames = incoming.keys.toSet();
  for (final name in existingNames) {
    if (incomingNames.contains(name)) continue;
    try {
      await client.rpc('config/delete', {'name': name});
    } on RcloneException catch (e) {
      failed.add((name: name, error: 'delete failed: ${e.message}'));
    } catch (e) {
      failed.add((name: name, error: 'delete failed: $e'));
    }
  }
  return MergeReport(created: created, failed: failed);
}

/// The replace-import primitive: snapshot [active] into [backups] FIRST (so the
/// overwrite is reversible), THEN overwrite it with [newBytes], THEN [restart]
/// the engine to load it. The ordering is load-bearing — the backup must precede
/// the overwrite, or a bad replace would be unrecoverable. Takes bytes (not a
/// String) because the payload is plaintext INI for a plaintext config but an
/// rclone-ENCRYPTED blob when the active config is encrypted (the caller
/// re-encrypts first so encryption-at-rest is never silently dropped). Extracted
/// from [ConfigTransferController.applyReplace] so the ordering is unit-tested
/// with a temp file + temp backups dir, no real engine/settings.
Future<void> replaceConfigFile({
  required File active,
  required ConfigBackups backups,
  required List<int> newBytes,
  required Future<void> Function() restart,
}) async {
  await backups.backupActiveConfig(active);
  await active.writeAsBytes(newBytes, flush: true);
  await restart();
}

// --- Controller --------------------------------------------------------------

final _rng = Random.secure();
String _randToken() => List<int>.generate(
  8,
  (_) => _rng.nextInt(16),
).map((n) => n.toRadixString(16)).join();

/// A leading UTF-8 BOM some editors prepend; stripped before a text decode so a
/// BOM'd INI/JSON pick parses cleanly (config_io's sniffer tolerates it too).
const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

String _decodeUtf8(List<int> bytes) {
  final body =
      (bytes.length >= 3 &&
          bytes[0] == _utf8Bom[0] &&
          bytes[1] == _utf8Bom[1] &&
          bytes[2] == _utf8Bom[2])
      ? bytes.sublist(3)
      : bytes;
  return utf8.decode(body);
}

/// Parses a decrypted/plaintext config text (INI or `config dump` JSON) into the
/// shared model — the shape both an envelope's payload and a plaintext pick take.
ConfigModel _parseConfigText(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{')) return parseDumpJson(text);
  return parseIni(text);
}

/// Orchestrates the config import/export flows over the live engine. A plain
/// service behind a [Provider] (not a Notifier) — the wizards own their own step
/// state; this exposes the async operations they drive. Mirrors [CacheCrypto]'s
/// `Provider((ref) => ...)` shape.
class ConfigTransferController {
  ConfigTransferController(this._ref);
  final Ref _ref;

  RcloneClient? get _client => _ref.read(engineControllerProvider).client;

  /// Hydrate persisted settings before this layer reads [SettingsState] fields
  /// (configPathOverride / rclonePathOverride). Idempotent. In practice every
  /// transfer op runs from Settings, which is only reachable after the engine
  /// bootstrapped (and bootstrap awaits ensureLoaded) — but awaiting it here
  /// makes the transfer controller self-contained rather than depending on the
  /// engine having hydrated settings first (matches the headless_runner
  /// rationale in engine_controller._platformSetup). Belt-and-suspenders: a rare
  /// hydration failure is swallowed and we fall through to whatever state is
  /// loaded (no worse than reading the field synchronously).
  Future<void> _ensureSettingsLoaded() async {
    try {
      await _ref.read(settingsControllerProvider.notifier).ensureLoaded();
    } catch (_) {
      // best-effort — proceed with the already-loaded settings state
    }
  }

  /// A freshly-created per-run temp subdirectory, tightened to owner-only (0700)
  /// where the OS supports it, for a short-lived config artifact (encrypted
  /// config bytes) that must not be group/other-readable while it exists. The
  /// caller removes it recursively in a `finally`.
  Future<Directory> _privateTempDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/airclone-cfg-${_randToken()}');
    await dir.create(recursive: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['700', dir.path]);
      } catch (_) {
        // best-effort hardening — a failed chmod doesn't block the operation
      }
    }
    return dir;
  }

  // --- Import ---------------------------------------------------------------

  /// Parses picked [bytes] of the sniffed [format] into a [ConfigModel]:
  ///  - INI / dump-JSON parse directly;
  ///  - [ConfigFormat.aircloneEnvelope] decrypts under [passphrase] (throws
  ///    [WrongPassphrase]/[CorruptEnvelope] from config_io on a bad secret/blob);
  ///  - [ConfigFormat.rcloneEncrypted] decrypts THAT config's [rclonePassword]
  ///    out-of-process via `rclone config dump` (throws [WrongRcloneConfigPassword]).
  Future<ConfigModel> parseImport({
    required List<int> bytes,
    required ConfigFormat format,
    String? passphrase,
    String? rclonePassword,
  }) async {
    switch (format) {
      case ConfigFormat.rcloneIni:
        return parseIni(_decodeUtf8(bytes));
      case ConfigFormat.dumpJson:
        return parseDumpJson(_decodeUtf8(bytes));
      case ConfigFormat.aircloneEnvelope:
        final text = await openConfigEnvelope(bytes, passphrase ?? '');
        return _parseConfigText(text);
      case ConfigFormat.rcloneEncrypted:
        return _decryptRcloneConfig(bytes, rclonePassword ?? '');
      case ConfigFormat.unknown:
        throw const ConfigTransferError(
          "That file isn't a recognised rclone or Airclone config.",
        );
    }
  }

  /// Decrypts a password-encrypted `rclone.conf` [bytes] by writing it to a
  /// short-lived temp file (in an owner-only per-run subdir) and running the
  /// engine rclone's `config dump --config [tempfile]` with `RCLONE_CONFIG_PASS`
  /// set. The password only ever travels via the environment — never the argv,
  /// never a log. Uses [Process.start] (not `Process.run`) so a run that exceeds
  /// the timeout is `kill()`ed and REAPED before the `finally` removes the
  /// directory — otherwise an orphaned child would hold the file open and the
  /// delete would silently fail on Windows. The temp dir is best-effort removed
  /// in the `finally`; on a hard app-kill mid-run only ENCRYPTED bytes (never a
  /// plaintext dump) could linger.
  Future<ConfigModel> _decryptRcloneConfig(
    List<int> bytes,
    String password,
  ) async {
    await _ensureSettingsLoaded();
    final rclone = await RcloneEngine.findExisting(
      overridePath: _ref.read(settingsControllerProvider).rclonePathOverride,
    );
    if (rclone == null) {
      throw const ConfigTransferError('The rclone engine was not found.');
    }
    final tmpDir = await _privateTempDir();
    final tmp = File('${tmpDir.path}/import.conf');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      final cmd = rcloneEncryptedDumpCommand(tmp.path, password);
      final proc = await Process.start(rclone, cmd.args, environment: cmd.env);
      // Windows: no rclone child may outlive us holding rclone.exe open in the
      // install dir (clean-uninstall requirement) — see WindowsChildJob.
      WindowsChildJob.adopt(proc.pid);
      // Collect stdout (the dump); discard stderr unread — it can echo a path,
      // so it is never surfaced. Draining both avoids a full-pipe deadlock.
      final stdoutFuture = proc.stdout.transform(utf8.decoder).join();
      unawaited(proc.stderr.drain<void>());
      int exitCode;
      try {
        exitCode = await proc.exitCode.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        proc.kill(ProcessSignal.sigkill);
        await proc.exitCode; // reap so the file is unlocked before the delete
        throw const WrongRcloneConfigPassword();
      }
      if (exitCode != 0) {
        // Wrong password (or an unreadable config). Deliberately generic — never
        // surface stderr here, and never the password.
        throw const WrongRcloneConfigPassword();
      }
      return parseDumpJson(await stdoutFuture);
    } finally {
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {
        // best-effort cleanup
      }
    }
  }

  /// The live config as a [ConfigModel], read from the RC seam `config/dump` (NOT
  /// by parsing the file) — so it works for an already-unlocked encrypted config
  /// and is the exact set of remotes the running engine knows. Used both as the
  /// "existing" side of [planImport] and as the source for a scoped export.
  Future<ConfigModel> activeConfigModel() async {
    final client = _client;
    if (client == null) {
      throw const ConfigTransferError('The engine is not ready.');
    }
    final dump = await client.rpc('config/dump');
    final model = <String, Map<String, String>>{};
    dump.forEach((name, cfg) {
      final section = <String, String>{};
      if (cfg is Map) {
        cfg.forEach((k, v) => section['$k'] = v == null ? '' : '$v');
      }
      model[name] = section;
    });
    return model;
  }

  /// Merge apply: back up the active config, then `config/create` per decision.
  /// Returns the per-remote [MergeReport] and refreshes the remotes list.
  Future<MergeReport> applyMerge(
    ConfigModel incoming,
    List<ImportDecision> plan,
  ) async {
    final client = _client;
    if (client == null) {
      throw const ConfigTransferError('The engine is not ready.');
    }
    final backups = await _ref.read(configBackupsProvider.future);
    final active = await _activeConfigFile();
    // Fail closed, matching applyReplace/restoreBackup: merge's config/create
    // OVERWRITES a same-named remote, so it must never mutate the live config
    // without a backup first (plan §2: back up before ANY mutating op).
    if (active == null) {
      throw const ConfigTransferError(
        "Couldn't locate the active config file to back up before merging.",
      );
    }
    final report = await mergeRemotes(
      client: client,
      incoming: incoming,
      plan: plan,
      backup: () => backups.backupActiveConfig(active).then((_) {}),
    );
    // The creates wrote straight to the live config; refresh what the app shows.
    _ref.invalidate(remotesProvider);
    return report;
  }

  /// Replace apply: back up, overwrite the active config with [incoming], and
  /// switch the engine onto it. The destructive confirm is the dialog's
  /// responsibility; this performs it.
  ///
  /// Crucially, if the ACTIVE config is rclone-natively encrypted, the
  /// replacement is RE-ENCRYPTED with the held launch password before it reaches
  /// the live file — a plaintext INI is never written over an encrypted config
  /// (that would silently drop encryption-at-rest for every OAuth token/secret).
  /// If we can't re-encrypt (no held password, or the re-encrypt step fails to
  /// produce an encrypted file), we BLOCK with a clear error and leave the
  /// existing encrypted config untouched rather than downgrade it.
  Future<void> applyReplace(ConfigModel incoming) async {
    await _ensureSettingsLoaded();
    final backups = await _ref.read(configBackupsProvider.future);
    final active = await _activeConfigFile();
    if (active == null) {
      throw const ConfigTransferError(
        "Couldn't locate the active config file to replace.",
      );
    }
    // Encryption is a property of the ACTIVE config's contents. The held launch
    // password (cachePassphraseProvider) is non-null exactly for an unlocked
    // encrypted config; also sniff the file header as a backstop.
    final heldPassword = _ref.read(cachePassphraseProvider);
    final encrypted =
        (heldPassword != null && heldPassword.isNotEmpty) ||
        await _fileIsEncrypted(active);

    if (encrypted) {
      // Encrypted active config: NEVER write plaintext to disk. Replace through
      // the running engine — it re-encrypts on save with its held password — so
      // encryption-at-rest is preserved. Requires the engine to be up (it is,
      // because an encrypted config can only be imported into once unlocked).
      final client = _client;
      if (client == null) {
        throw const ConfigTransferError(
          'The engine must be running to replace an encrypted config. Unlock '
          'the config first, then try again.',
        );
      }
      final existing =
          _ref
              .read(remotesProvider)
              .valueOrNull
              ?.map((r) => r.name)
              .toList(growable: false) ??
          const <String>[];
      final report = await replaceViaRcd(
        client: client,
        incoming: incoming,
        existingNames: existing,
        backup: () async {
          final path = await _activeConfigFile();
          if (path != null) await backups.backupActiveConfig(path);
        },
      );
      _ref.invalidate(remotesProvider);
      if (!report.allOk) {
        throw ConfigTransferError(
          'Replaced with issues — ${report.failed.length} of '
          '${report.failed.length + report.created.length} remote(s) failed. '
          'Your previous config was backed up first.',
        );
      }
      return;
    }

    // Plaintext active config: a direct file write is fine (and fast). The
    // switch re-runs the encryption gate against the new file rather than
    // reusing the stale password (restartEngine would).
    await replaceConfigFile(
      active: active,
      backups: backups,
      newBytes: utf8.encode(serializeIni(incoming)),
      restart: () =>
          _ref.read(engineControllerProvider.notifier).switchConfigAndStart(),
    );
    _ref.invalidate(remotesProvider);
  }

  /// True when [file]'s header marks it as an rclone-encrypted config.
  Future<bool> _fileIsEncrypted(File file) async {
    try {
      if (!await file.exists()) return false;
      final head = await file.readAsString();
      return head.contains('Encrypted rclone configuration File');
    } catch (_) {
      return false;
    }
  }

  // --- Export ---------------------------------------------------------------

  /// The [selected] remotes expanded to their dependency closure and projected
  /// back onto [full]'s ordering — a crypt/alias/union drags in the base(s) it
  /// points at so the export isn't broken on arrival (plan §4). Only remotes
  /// actually present in [full] are emitted.
  ConfigModel scopedModel(ConfigModel full, Set<String> selected) {
    final closure = dependencyClosure(full, selected);
    final out = <String, Map<String, String>>{};
    for (final e in full.entries) {
      if (closure.contains(e.key)) out[e.key] = e.value;
    }
    return out;
  }

  /// Seals [model] into the Airclone AES-256-GCM export envelope under
  /// [passphrase] (serialized to INI first). The inverse of [openExport]. [kdf]
  /// overrides the production Argon2id band ONLY for tests (which would otherwise
  /// pay the full memory-hard cost); production callers omit it.
  Future<Uint8List> sealExport(
    ConfigModel model,
    String passphrase, {
    Argon2Params? kdf,
  }) => kdf == null
      ? sealConfigEnvelope(serializeIni(model), passphrase)
      : sealConfigEnvelope(serializeIni(model), passphrase, kdf: kdf);

  /// Opens an Airclone envelope [bytes] under [passphrase] back to a [ConfigModel]
  /// (the round-trip partner of [sealExport]; also the import path for a
  /// `.airclone-config`). Throws [WrongPassphrase]/[CorruptEnvelope].
  Future<ConfigModel> openExport(List<int> bytes, String passphrase) async {
    final text = await openConfigEnvelope(bytes, passphrase);
    return _parseConfigText(text);
  }

  /// Raw-copies the active config file to [destPath] — the "exact copy (stays
  /// rclone-encrypted)" export offered when the whole config is exported and it
  /// is already rclone-natively encrypted (plan §4): the copy still opens with a
  /// plain `rclone` + its password anywhere, byte-for-byte identical.
  ///
  /// TODO(plan §4, optional): a SCOPED export re-encrypted rclone-natively via
  /// `rclone config encryption set` on the temp file. Deferred — the plan marks
  /// it optional and the Airclone envelope covers scoped encrypted export.
  Future<void> exportExactCopy(String destPath) async {
    final active = await _activeConfigFile();
    if (active == null || !await active.exists()) {
      throw const ConfigTransferError(
        "Couldn't locate the active config file to copy.",
      );
    }
    await active.copy(destPath);
  }

  // --- Backups (plan §2 restore surface) ------------------------------------

  /// The current automatic backups, newest first (for the settings "Restore a
  /// backup…" row).
  Future<List<File>> listBackups() async {
    final backups = await _ref.read(configBackupsProvider.future);
    return backups.listBackups();
  }

  /// Restores [backupPath] over the active config (itself snapshotting the
  /// current one first, in [ConfigBackups.restoreBackup]) and restarts the engine.
  Future<void> restoreBackup(String backupPath) async {
    final backups = await _ref.read(configBackupsProvider.future);
    final active = await _activeConfigFile();
    if (active == null) {
      throw const ConfigTransferError(
        "Couldn't locate the active config file to restore over.",
      );
    }
    await backups.restoreBackup(backupPath, active);
    // A restore swaps the config CONTENTS, so re-run the encryption gate against
    // the restored file (the restored config may differ in encryption state from
    // the one currently running) instead of reusing the stale held password.
    await _ref.read(engineControllerProvider.notifier).switchConfigAndStart();
    _ref.invalidate(remotesProvider);
  }

  // --- Native config encryption (set / change / remove) ---------------------

  /// Drives rclone's own config-file encryption ([ConfigEncryptionOp]) on the
  /// ACTIVE config, then restarts the engine against the new state. There is no
  /// RC method for this and setting `RCLONE_CONFIG_PASS` on a plaintext config
  /// does NOT encrypt it on save (both verified against rclone v1.74), so it runs
  /// the `rclone config encryption set/remove` CLI out-of-process — which needs a
  /// real binary (desktop + Android; refused on a pure-FFI engine that has none).
  ///
  /// Safety (each hardened after a 2026-07-11 adversarial review):
  ///  - Refused unless the engine is READY (a running engine is what we quiesce +
  ///    restart around the rewrite) — this also structurally blocks the
  ///    encrypted-but-LOCKED and binary-not-installed states where the cheap state
  ///    guards below could be defeated.
  ///  - Refused while transfers are in flight — the op restarts the engine, which
  ///    would silently abort them; the user is told to finish/pause them first.
  ///  - Encryption state is read from BOTH the held session password AND the file
  ///    header, so an "encrypt" can never run on an already-encrypted file.
  ///  - The running engine is QUIESCED before the CLI touches the file, so rclone's
  ///    own OAuth token auto-save can't race the encryption CLI's atomic rename.
  ///  - For encrypt we do NOT snapshot the (plaintext) config — that would scatter
  ///    a readable copy of the very secrets being encrypted into the backups ring;
  ///    the atomic-rename CLI leaves nothing torn to protect. change/decrypt DO back
  ///    up (an already-encrypted file, safe + useful for undo).
  ///  - A timeout is treated as INDETERMINATE (re-probe the file), not a hard fail.
  ///  - The new password travels via stdin, the current via the environment — never
  ///    the argv/a log.
  Future<void> applyConfigEncryption(
    ConfigEncryptionOp op, {
    String? newPassword,
  }) async {
    await _ensureSettingsLoaded();
    final engine = _ref.read(engineControllerProvider.notifier);

    // The whole flow assumes a running engine to quiesce/restart around the
    // rewrite and to trust the live encryption state. Refuse otherwise.
    if (!_ref.read(engineControllerProvider).isReady) {
      throw const ConfigTransferError(
        'Start the engine before changing config encryption.',
      );
    }
    final rclone = await RcloneEngine.findExisting(
      overridePath: _ref.read(settingsControllerProvider).rclonePathOverride,
    );
    if (rclone == null) {
      throw const ConfigTransferError(
        'The rclone engine binary was not found — config encryption needs it '
        '(it is unavailable on the in-process engine).',
      );
    }
    final active = await _activeConfigFile();
    if (active == null) {
      throw const ConfigTransferError(
        "Couldn't locate the active config file to encrypt.",
      );
    }

    // Refuse while transfers are active — the engine restart would kill them.
    final activeJobs = _ref
        .read(jobsControllerProvider)
        .where((j) => j.isActive)
        .length;
    if (activeJobs > 0) {
      throw const ConfigTransferError(
        'Finish, pause, or cancel active transfers first — changing config '
        'encryption restarts the engine and would interrupt them.',
      );
    }

    // Derive the encryption state from BOTH the held session password AND the file
    // header — never trust a single signal before rewriting the file.
    final current = _ref.read(cachePassphraseProvider);
    final heldEncrypted = current != null && current.isNotEmpty;
    final fileEncrypted = await _fileIsEncrypted(active);
    final isEncrypted = heldEncrypted || fileEncrypted;

    if (op == ConfigEncryptionOp.encrypt && isEncrypted) {
      throw const ConfigTransferError(
        'This config is already encrypted. Use "Change password" or '
        '"Remove encryption" instead.',
      );
    }
    if (op != ConfigEncryptionOp.encrypt && !isEncrypted) {
      throw const ConfigTransferError(
        'This config is not encrypted, so there is nothing to change or remove.',
      );
    }
    // change/decrypt re-encrypt/decrypt with the CURRENT password — we must hold
    // it (a ready engine on an encrypted config always does; this guards the
    // pathological file-encrypted-but-not-unlocked case).
    if (op != ConfigEncryptionOp.encrypt && !heldEncrypted) {
      throw const ConfigTransferError(
        'Unlock the config first — its current password is needed to change or '
        'remove encryption.',
      );
    }

    // Back up before the rewrite — but NOT for encrypt, whose source is plaintext
    // (a snapshot would leave a readable copy of every secret in the ring). The
    // encrypt CLI writes atomically, so nothing is torn to protect.
    if (op != ConfigEncryptionOp.encrypt) {
      final backups = await _ref.read(configBackupsProvider.future);
      await backups.backupActiveConfig(active);
    }

    // The password the config needs AFTER a successful op (null after decrypt),
    // and the one it needs if the op did NOT change the on-disk state.
    final newHeld = op == ConfigEncryptionOp.decrypt ? null : newPassword;
    final priorHeld = heldEncrypted ? current : null;

    // Build the command BEFORE quiescing the engine — a missing-password
    // ArgumentError here must not leave the engine torn down.
    final cmd = buildConfigEncryptionCommand(
      op: op,
      configPath: active.path,
      currentPassword: current,
      newPassword: newPassword,
    );

    // Quiesce the single writer (rcd) before mutating the file.
    await engine.quiesceForConfigOp();

    final int code;
    final String errTail;
    try {
      final r = await _runEncryptionCli(rclone, cmd);
      code = r.$1;
      errTail = r.$2;
    } catch (e) {
      // The CLI couldn't even start — the file is untouched. Restore + report.
      await _restoreEngine(engine, priorHeld);
      throw ConfigTransferError(
        "Couldn't run rclone to change the config encryption: $e",
      );
    }

    if (code == -1) {
      // Timeout — INDETERMINATE: rclone may have committed its atomic rename just
      // before we killed it. Re-probe whether it actually reached the target
      // state; proceed if so, else restore the prior state and report honestly.
      //   - encrypt/decrypt flip the file HEADER (plaintext ⇄ encrypted), so a
      //     header sniff proves the commit.
      //   - changePassword leaves the header identical (encrypted either way), so
      //     the only proof is that the NEW password now loads the config — a
      //     header sniff would falsely "confirm" an uncommitted change and then
      //     reload/vault the WRONG password. Test-load with the new password.
      final bool reachedTarget;
      switch (op) {
        case ConfigEncryptionOp.encrypt:
          reachedTarget = await _fileIsEncrypted(active);
        case ConfigEncryptionOp.decrypt:
          reachedTarget = !await _fileIsEncrypted(active);
        case ConfigEncryptionOp.changePassword:
          reachedTarget = await _configLoadsWith(
            rclone,
            active.path,
            newPassword,
          );
      }
      if (!reachedTarget) {
        await _restoreEngine(engine, priorHeld);
        throw const ConfigTransferError(
          "Timed out and couldn't confirm the change — the config is unchanged. "
          'Please try again.',
        );
      }
    } else if (code != 0) {
      // Real failure — the file is untouched. Bring the engine back as it was.
      await _restoreEngine(engine, priorHeld);
      throw ConfigTransferError(
        "rclone couldn't change the config encryption"
        '${errTail.isEmpty ? '.' : ': $errTail'}',
      );
    }

    // Success (exit 0, or a timeout that reached the target). Restart against the
    // new state — reloadWithConfigPassword reconciles the vault first, so a failed
    // restart still leaves a consistent secret store (and surfaces its own error).
    await engine.reloadWithConfigPassword(newHeld);
    _ref.invalidate(remotesProvider);
  }

  /// Best-effort engine restart used on a failed/aborted config-encryption op to
  /// bring the quiesced engine back in its PRIOR state. Swallows a restart error
  /// so the caller's real (CLI) failure is the one surfaced.
  Future<void> _restoreEngine(EngineController engine, String? password) async {
    try {
      await engine.reloadWithConfigPassword(password);
    } catch (_) {
      // The prior-state restart failed too; the caller reports the primary error.
    }
  }

  /// True when the config at [path] loads with [password] — a `rclone config dump`
  /// that exits 0. Used ONLY to disambiguate a changePassword TIMEOUT, whose file
  /// header can't reveal whether the new password actually took: the new password
  /// loads the config iff the atomic re-encrypt committed. The password travels via
  /// `RCLONE_CONFIG_PASS` (env), never the argv. Null/empty ⇒ test as plaintext.
  Future<bool> _configLoadsWith(
    String rclone,
    String path,
    String? password,
  ) async {
    try {
      final res = await Process.run(
        rclone,
        configDumpArgs(path),
        runInShell: false,
        environment: (password != null && password.isNotEmpty)
            ? {'RCLONE_CONFIG_PASS': password}
            : null,
      ).timeout(const Duration(seconds: 15));
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Spawns the rclone binary for a config-encryption op: writes the new password
  /// to stdin (rclone reads it from a pipe rather than a TTY), then closes stdin
  /// so a `set` doesn't hang on its second prompt. Captures stderr for a failure
  /// message (rclone never echoes the typed password, so the tail is safe to
  /// surface). A run that exceeds the timeout is killed and reaped. Returns the
  /// exit code and the last stderr line.
  Future<(int, String)> _runEncryptionCli(
    String rclone,
    ConfigEncryptionCommand cmd,
  ) async {
    final proc = await Process.start(
      rclone,
      cmd.args,
      runInShell: false,
      environment: cmd.env.isEmpty ? null : cmd.env,
    );
    WindowsChildJob.adopt(proc.pid);
    final err = StringBuffer();
    final drainErr = proc.stderr.transform(utf8.decoder).forEach(err.write);
    // stdout carries nothing we want, but an UNREAD pipe blocks its writer once
    // the (1 KiB, on Windows) buffer fills — draining it is what stops a chatty
    // run from wedging rclone mid-prompt.
    unawaited(proc.stdout.drain<void>());
    final stdinText = cmd.stdin;
    if (stdinText != null) {
      proc.stdin.write(stdinText);
      await proc.stdin.flush();
    }
    // Always close stdin — `remove` reads none, `set` needs EOF after the two
    // password lines or it waits forever.
    try {
      await proc.stdin.close();
    } catch (_) {
      // The child may have already exited (e.g. bad env password) — ignore.
    }
    final code = await proc.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        proc.kill();
        return -1;
      },
    );
    await drainErr.timeout(const Duration(seconds: 2), onTimeout: () {});
    final lines = err
        .toString()
        // rclone writes the interactive "password:"/"Confirm…" prompts to stderr
        // with no trailing newline; a plain split still yields the real error as
        // the last non-empty segment.
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.endsWith('password:'))
        .toList();
    return (code, lines.isEmpty ? '' : lines.last);
  }

  // --- Active config file resolution ----------------------------------------

  /// Resolves the active config file the engine is running against, for backup /
  /// overwrite / raw-copy. Mirrors [resolveConfigPath]'s ANDROID-FIRST ordering
  /// (engine_controller.dart) so backup/replace/restore can never target a
  /// different file than the engine actually runs against:
  ///  - Android always uses its app-private `rclone.conf` (the override picker is
  ///    desktop-only, and the sandbox can't exec/read a config elsewhere);
  ///  - otherwise a persisted config-path override wins (desktop "Use a different
  ///    config");
  ///  - otherwise (desktop default) ask rclone where its config lives via a short
  ///    `rclone config file` subprocess (the same source the engine spawns with).
  /// Null when it can't be determined (no engine binary / probe failed).
  Future<File?> _activeConfigFile() async {
    await _ensureSettingsLoaded();
    if (Platform.isAndroid) {
      final support = await getApplicationSupportDirectory();
      return File('${support.path}/rclone.conf');
    }
    final override = _ref.read(settingsControllerProvider).configPathOverride;
    if (override != null && override.isNotEmpty) return File(override);
    final rclone = await RcloneEngine.findExisting(
      overridePath: _ref.read(settingsControllerProvider).rclonePathOverride,
    );
    if (rclone == null) return null;
    try {
      final res = await Process.run(rclone, const [
        'config',
        'file',
      ]).timeout(const Duration(seconds: 10));
      if (res.exitCode == 0) {
        final lines = (res.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) return File(lines.last); // last line is the path
      }
    } catch (_) {
      // fall through to null — the caller surfaces "couldn't locate the config"
    }
    return null;
  }
}

final configTransferControllerProvider = Provider<ConfigTransferController>(
  (ref) => ConfigTransferController(ref),
);
