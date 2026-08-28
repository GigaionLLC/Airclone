import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../state/build_flavor.dart';

/// Locates — and, on first run, downloads + verifies — the `rclone` binary used by
/// the desktop [HttpRcloneClient]. Mirrors the provisioning design in
/// `wiki/core/08-core-architecture.md` (download → SHA256-verify → extract).
class RcloneEngine {
  /// Resolution order for an existing binary:
  ///   1. explicit override (settings) — passed in by the caller,
  ///   2. Android: the engine bundled in the APK (nothing else can exist),
  ///   3. the app-managed engine dir (where an in-app engine update lands),
  ///   4. a binary bundled beside the app (every desktop build now ships one —
  ///      see [bundledDesktopBinary]),
  ///   5. `rclone` on the system PATH.
  ///
  /// The managed dir is checked *before* the bundled one on purpose: a fresh
  /// install has only the bundled engine (so first run needs no download), but a
  /// user-initiated "update engine" that lands in the managed dir then takes
  /// precedence on the next launch. Whether an update is even *offered* is a
  /// separate question — see [isStoreManaged] (the Store build never downloads).
  static Future<String?> findExisting({String? overridePath}) async {
    if (overridePath != null && overridePath.isNotEmpty) {
      if (await File(overridePath).exists()) return overridePath;
    }
    if (Platform.isAndroid) return bundledAndroidBinary();
    // A build that may not spawn - Mac App Store, iOS - has no use for a binary
    // it could never execute: resolveEngineMode forces the in-process library
    // for it regardless of what is found. Searching anyway is not merely
    // wasted work. Step 5 below is `Process.run('which', ...)`, and a build
    // whose review notes say it spawns no processes should not be reaching for
    // posix_spawn at startup, sandbox-denied or not.
    if (!subprocessAllowedHere) return null;
    final managed = await _managedBinaryPath();
    if (await File(managed).exists()) return managed;

    final bundled = await bundledDesktopBinary();
    if (bundled != null) return bundled;

    final onPath = await _whichRclone();
    return onPath;
  }

  /// A desktop rclone binary that ships *inside* the app package, placed beside
  /// the app executable. Every desktop build now bundles one (CI drops a
  /// SHA256-verified `rclone.exe` into the Release dir before packaging; see
  /// release.yml), so first run never has to download the engine. This reports
  /// only *whether such a binary is present to use* — it says nothing about
  /// whether an in-app engine update is allowed; that is [isStoreManaged] (the
  /// Store/MSIX build must not download executable code at runtime).
  /// Desktop-only; returns null when absent or on any error.
  static Future<String?> bundledDesktopBinary() async {
    if (Platform.isAndroid || Platform.isIOS) return null;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final name = Platform.isWindows ? 'rclone.exe' : 'rclone';
      final path = '$exeDir${Platform.pathSeparator}$name';
      return await File(path).exists() ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// Whether this is the packaged Microsoft Store (MSIX) build, which must never
  /// download or update the engine at runtime — the Store forbids downloading
  /// executable code, and it refreshes the bundled engine when the app itself
  /// updates. The Inno installer and portable zip share the *identical* compiled
  /// executable with the MSIX (the MSIX just repackages the desktop build via
  /// `msix:create --build-windows false`), so nothing at compile time tells them
  /// apart — but the Windows `GetCurrentPackageFullName` API can: it returns
  /// `APPMODEL_ERROR_NO_PACKAGE` for the unpackaged builds and success for the
  /// MSIX. Non-Windows is never Store-packaged today; a future macOS App Store
  /// (sandboxed) build would need its OWN check added here before it may ship,
  /// since a sandbox likewise forbids downloading + exec'ing an engine. Cached —
  /// packaging state cannot change within a run.
  static bool isStoreManaged() => _storeManaged ??= _detectStoreManaged();

  static bool? _storeManaged;

  static bool _detectStoreManaged() {
    if (!Platform.isWindows) return false;
    const appmodelErrorNoPackage = 15700; // APPMODEL_ERROR_NO_PACKAGE
    try {
      final getCurrentPackageFullName = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            Int32 Function(Pointer<Uint32>, Pointer<Utf16>),
            int Function(Pointer<Uint32>, Pointer<Utf16>)
          >('GetCurrentPackageFullName');
      final length = malloc<Uint32>()..value = 0;
      try {
        // A null name buffer: unpackaged -> APPMODEL_ERROR_NO_PACKAGE; packaged ->
        // ERROR_INSUFFICIENT_BUFFER (122) or ERROR_SUCCESS (0).
        final rc = getCurrentPackageFullName(length, nullptr);
        return rc != appmodelErrorNoPackage;
      } finally {
        malloc.free(length);
      }
    } catch (_) {
      // GetCurrentPackageFullName exists on Windows 8+ (we require 10), so this is
      // unexpected. Default to "not Store-managed": the common case is the
      // unpackaged installer/zip, and an MSIX reliably resolves via the API above.
      return false;
    }
  }

  /// The rclone executable that ships inside the APK as a per-ABI jniLib named
  /// `librclone.so` (see dev/android/build-rclone.ps1). The installer extracts
  /// it to `nativeLibraryDir` — the one location Android permits exec() from —
  /// whose path only the platform side knows.
  static Future<String?> bundledAndroidBinary() async {
    try {
      const channel = MethodChannel('airclone/native');
      final dir = await channel.invokeMethod<String>('nativeLibraryDir');
      if (dir == null || dir.isEmpty) return null;
      final path = '$dir/librclone.so';
      return await File(path).exists() ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// Detects whether the rclone config is encrypted **out-of-band** — by reading the
  /// config file header, never by an RC call (a locked config hangs `config/get` and
  /// `--ask-password=false` crashes rclone). See `wiki/core/15-security.md`.
  ///
  /// When the app manages the config location itself (Android passes `--config`
  /// explicitly), [configPath] skips the `rclone config file` probe and reads
  /// that file directly.
  static Future<bool> isConfigEncrypted(
    String rclonePath, {
    String? configPath,
  }) async {
    if (configPath != null) {
      try {
        final file = File(configPath);
        if (!await file.exists()) return false;
        final head = await file.readAsString();
        return head.contains('Encrypted rclone configuration File');
      } catch (_) {
        return false;
      }
    }
    try {
      final res = await Process.run(rclonePath, ['config', 'file']);
      if (res.exitCode != 0) return false;
      final lines = (res.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) return false;
      final file = File(lines.last); // last line is the config path
      if (!await file.exists()) return false;
      final head = await file.readAsString();
      return head.contains('Encrypted rclone configuration File');
    } catch (_) {
      return false;
    }
  }

  /// Returns a usable rclone path, downloading the verified latest release into the
  /// app-managed engine dir if none is found. [onStatus] receives human-readable steps.
  static Future<String> ensureInstalled({
    String? overridePath,
    void Function(String message)? onStatus,
  }) async {
    final existing = await findExisting(overridePath: overridePath);
    if (existing != null) return existing;
    return downloadLatest(onStatus: onStatus);
  }

  /// Downloads + verifies the latest rclone and installs it as the managed
  /// engine in one step. Safe only when no engine is running from that path —
  /// use it for the FIRST install ([ensureInstalled]). To update a running
  /// engine, stage first, stop it, then [installStaged]; see
  /// `EngineController.updateEngine`.
  static Future<String> downloadLatest({
    void Function(String)? onStatus,
  }) async {
    final staged = await downloadLatestToStaging(onStatus: onStatus);
    final path = await installStaged(staged, onStatus: onStatus);
    onStatus?.call('Engine ready.');
    return path;
  }

  /// Downloads the latest official rclone, verifies its SHA-256 (fail-closed —
  /// throws a [StateError] if the checksum can't be fetched, parsed, or matched
  /// rather than installing an unverified engine), and extracts the binary to a
  /// STAGING path beside the managed engine. Returns that staging path.
  ///
  /// Deliberately does not touch the managed binary: on Windows the running
  /// engine holds its own executable open, so writing it in place fails with
  /// "used by another process" — which is exactly what made the in-app engine
  /// update always fail once an engine had been downloaded.
  static Future<String> downloadLatestToStaging({
    void Function(String)? onStatus,
  }) async {
    if (Platform.isAndroid) {
      // No downloadable engine exists for Android (and exec from app storage is
      // forbidden anyway) — the binary must come bundled in the APK.
      throw StateError('The bundled rclone engine is missing from this build.');
    }
    // The packaged Microsoft Store (MSIX) build must never download + exec rclone
    // at runtime — the Store forbids downloading executable code and refreshes the
    // bundled engine when the app updates. Every desktop build now bundles the
    // engine, so *presence of a bundled binary* is no longer the signal (that
    // would wrongly block the zip/installer from updating too); the signal is "am
    // I the packaged Store build?" ([isStoreManaged], via GetCurrentPackageFullName
    // — the MSIX shares the compiled exe with the installer, so nothing at compile
    // time distinguishes them). Unpackaged builds fall through and may update.
    if (isStoreManaged()) {
      throw StateError(
        'This build is managed by the Microsoft Store — the bundled rclone '
        'engine updates when the app itself updates.',
      );
    }
    final triple = _targetTriple();
    onStatus?.call('Resolving latest rclone version…');
    final version = await _latestVersion();

    final base = 'https://downloads.rclone.org/$version';
    final zipName = 'rclone-$version-$triple.zip';
    final binInZip = Platform.isWindows ? 'rclone.exe' : 'rclone';

    onStatus?.call('Downloading $zipName…');
    final zipBytes = await _getBytes('$base/$zipName');

    onStatus?.call('Verifying checksum…');
    // Fail-closed: an engine we cannot verify is never installed. Any failure
    // to fetch OR parse the official SHA256SUMS aborts the install with an
    // actionable error rather than silently trusting the bytes we just pulled.
    final String sumsBody;
    try {
      sumsBody = await _getString('$base/SHA256SUMS');
    } catch (e) {
      throw StateError(
        'could not verify the download — refusing to install an unverified '
        'engine (fetching the checksum list failed: $e)',
      );
    }
    final expected = parseSha256Sums(sumsBody, zipName);
    if (expected == null) {
      throw StateError(
        'could not verify the download — refusing to install an unverified '
        'engine (no checksum for $zipName in the release SHA256SUMS)',
      );
    }
    final actual = sha256.convert(zipBytes).toString();
    if (expected.toLowerCase() != actual.toLowerCase()) {
      throw StateError(
        'rclone checksum mismatch (expected $expected, got $actual)',
      );
    }

    onStatus?.call('Extracting engine…');
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final entry = archive.files.firstWhere(
      (f) => f.isFile && _basename(f.name) == binInZip,
      orElse: () => throw StateError('rclone binary not found in archive'),
    );

    final destDir = Directory(await _engineDir());
    await destDir.create(recursive: true);
    // Written to a STAGING file, never straight to the managed binary: on
    // Windows a running executable is locked, so overwriting the engine while
    // it is serving would fail with "used by another process". The caller stops
    // the engine and then calls [installStaged].
    final stagedPath = await _stagedBinaryPath();
    final out = File(stagedPath);
    await out.writeAsBytes(entry.content as List<int>, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', stagedPath]);
    }
    onStatus?.call('Downloaded rclone $version.');
    return stagedPath;
  }

  /// Swaps a [downloadLatestToStaging] result into place as the managed engine.
  ///
  /// MUST be called with the engine stopped — Windows will not let a running
  /// executable be replaced. The previous binary is kept as `.old` so
  /// [rollbackEngine] can put it back if the new one fails to start; call
  /// [discardPreviousEngine] once the new engine is up.
  ///
  /// Returns the managed binary path.
  static Future<String> installStaged(
    String stagedPath, {
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('Installing engine…');
    final managed = await _managedBinaryPath();
    await swapEngineBinary(staged: stagedPath, managed: managed);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', managed]);
    }
    return managed;
  }

  /// Restores the binary saved by [installStaged]. Used when the freshly
  /// installed engine fails to start. No-op when there is no backup.
  static Future<void> rollbackEngine() async =>
      restoreEngineBackup(await _managedBinaryPath());

  /// Deletes the [installStaged] backup after the new engine has started.
  static Future<void> discardPreviousEngine() async =>
      discardEngineBackup(await _managedBinaryPath());

  // ── the binary swap, parameterised so it is testable ──────────────────────
  //
  // Split out from the three methods above because those need path_provider to
  // resolve the managed path, which a plain unit test has no plugin for. These
  // take both paths explicitly and so run against real temp files — which
  // matters most for the rollback path, which otherwise only ever executes
  // when a release of rclone is broken.

  /// Moves [staged] into place as [managed], keeping the previous binary as
  /// `<managed>.old` so [restoreEngineBackup] can undo it. If the move fails
  /// the previous binary is put straight back, so a failed swap never leaves
  /// the app with no engine at all.
  @visibleForTesting
  static Future<void> swapEngineBinary({
    required String staged,
    required String managed,
  }) async {
    final backup = File('$managed.old');
    final current = File(managed);

    if (await backup.exists()) await _quietDelete(backup);
    if (await current.exists()) {
      // Rename rather than delete: recoverable if the new engine won't run.
      await _renameWithRetry(current, '$managed.old');
    }
    try {
      await _renameWithRetry(File(staged), managed);
    } catch (_) {
      if (await backup.exists()) {
        try {
          await backup.rename(managed);
        } catch (_) {
          /* nothing more we can do */
        }
      }
      rethrow;
    }
  }

  /// Puts `<managed>.old` back as [managed]. No-op without a backup.
  @visibleForTesting
  static Future<void> restoreEngineBackup(String managed) async {
    final backup = File('$managed.old');
    if (!await backup.exists()) return;
    await _quietDelete(File(managed));
    try {
      await _renameWithRetry(backup, managed);
    } catch (_) {
      // Leave the backup in place; better a stale .old on disk than throwing
      // from a recovery path.
    }
  }

  /// Drops `<managed>.old`.
  @visibleForTesting
  static Future<void> discardEngineBackup(String managed) async =>
      _quietDelete(File('$managed.old'));

  /// Windows can hold a handle on a just-exited process's image for a moment,
  /// so a rename immediately after `quit()` can still fail. Retry briefly
  /// rather than reporting a failure the user can only fix by waiting.
  static Future<void> _renameWithRetry(File from, String to) async {
    Object? last;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        await from.rename(to);
        return;
      } catch (e) {
        last = e;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw StateError('could not replace the engine binary: $last');
  }

  static Future<void> _quietDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Locked or already gone — callers treat this as best-effort.
    }
  }

  static Future<String> _stagedBinaryPath() async {
    final dir = await _engineDir();
    final name = Platform.isWindows ? 'rclone.exe.new' : 'rclone.new';
    return '$dir${Platform.pathSeparator}$name';
  }

  // ── internals ──────────────────────────────────────────────────────────────

  static Future<String> _engineDir() async {
    final support = await getApplicationSupportDirectory();
    return '${support.path}${Platform.pathSeparator}engine';
  }

  static Future<String> _managedBinaryPath() async {
    final dir = await _engineDir();
    final name = Platform.isWindows ? 'rclone.exe' : 'rclone';
    return '$dir${Platform.pathSeparator}$name';
  }

  /// rclone's release triple, e.g. `windows-amd64`, `osx-arm64`, `linux-amd64`.
  static String _targetTriple() {
    final os = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'osx'
        : 'linux';
    final abi = Abi.current().toString(); // e.g. windows_x64, macos_arm64
    final arch = abi.endsWith('arm64')
        ? 'arm64'
        : abi.endsWith('x64')
        ? 'amd64'
        : 'amd64';
    return '$os-$arch';
  }

  static Future<String> _latestVersion() async {
    final body = await _getString('https://downloads.rclone.org/version.txt');
    final m = RegExp(r'v\d+\.\d+\.\d+').firstMatch(body);
    if (m == null) throw StateError('could not parse rclone version: "$body"');
    return m.group(0)!;
  }

  /// The latest official rclone version available for download (e.g. `v1.74.4`).
  /// Wraps the internal `version.txt` probe so callers (the settings "check for
  /// updates" affordance) can query the newest release without downloading it.
  static Future<String> latestAvailableVersion() => _latestVersion();

  /// Extracts the SHA-256 hex digest for [zipName] from an rclone `SHA256SUMS`
  /// file body (lines of `<64-hex>  <filename>`). Pure + network-free so it is
  /// unit-testable. Returns null when the body has no entry for [zipName] or the
  /// matching line is malformed (non-64-hex digest) — [downloadLatest] treats a
  /// null as "unverifiable" and refuses to install (fail-closed).
  static String? parseSha256Sums(String sumsBody, String zipName) {
    for (final line in sumsBody.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      // Second field is the filename; a leading `*` marks binary mode in some
      // sha256sum outputs (rclone's are plain, but tolerate it). Match exactly
      // so a shorter name can't accidentally hit a longer entry.
      final name = parts[1].replaceFirst(RegExp(r'^[*./]+'), '');
      if (name != zipName) continue;
      final hash = parts.first.toLowerCase();
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return hash;
    }
    return null;
  }

  /// The minimum rclone version Airclone supports. Older engines miss RC methods
  /// we rely on and carry the published rclone RC CVEs called out in
  /// `dev/backlog/feature-backlog.md`. The min-version gate refuses to run below
  /// this; keep it in sync with `.github/workflows/release.yml`'s RCLONE_VERSION.
  static const minRcloneVersion = '1.73.5';

  /// Parses a MAJOR.MINOR.PATCH triple out of a reported rclone version string,
  /// tolerating the shapes rclone emits: `v1.74.4`, `rclone v1.74.4`,
  /// `1.74.4-beta.1234.abcdef`. Returns null when no triple can be found.
  static (int, int, int)? _parseVersionTriple(String v) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(v);
    if (m == null) return null;
    return (
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// Compares two rclone version strings by MAJOR.MINOR.PATCH, tolerant of the
  /// `v`/`rclone ` prefixes and `-beta`/`-DEV` suffixes rclone attaches. Returns
  /// `<0` if `a < b`, `0` if equal, `>0` if `a > b`. Unparseable input on either
  /// side yields 0 (callers that must not proceed on garbage should check
  /// parseability first, e.g. via [meetsMinRclone]).
  static int compareRcloneVersions(String a, String b) {
    final pa = _parseVersionTriple(a);
    final pb = _parseVersionTriple(b);
    if (pa == null || pb == null) return 0;
    if (pa.$1 != pb.$1) return pa.$1.compareTo(pb.$1);
    if (pa.$2 != pb.$2) return pa.$2.compareTo(pb.$2);
    return pa.$3.compareTo(pb.$3);
  }

  /// True when [reported] is at least [minRcloneVersion]. An unparseable version
  /// is treated as NOT meeting the minimum (fail-closed — we would rather prompt
  /// an engine update than run a build we cannot vet).
  static bool meetsMinRclone(String reported) {
    if (_parseVersionTriple(reported) == null) return false;
    return compareRcloneVersions(reported, minRcloneVersion) >= 0;
  }

  static Future<String?> _whichRclone() async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final res = await Process.run(cmd, ['rclone']);
      if (res.exitCode == 0) {
        final out = (res.stdout as String).trim();
        if (out.isNotEmpty) return out.split('\n').first.trim();
      }
    } catch (_) {
      /* not on PATH */
    }
    return null;
  }

  static Future<List<int>> _getBytes(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw StateError('GET $url failed (${res.statusCode})');
    }
    return res.bodyBytes;
  }

  static Future<String> _getString(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw StateError('GET $url failed (${res.statusCode})');
    }
    return res.body;
  }

  static String _basename(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}
