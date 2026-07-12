import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Locates — and, on first run, downloads + verifies — the `rclone` binary used by
/// the desktop [HttpRcloneClient]. Mirrors the provisioning design in
/// `wiki/core/08-core-architecture.md` (download → SHA256-verify → extract).
class RcloneEngine {
  /// Resolution order for an existing binary:
  ///   1. explicit override (settings) — passed in by the caller,
  ///   2. Android: the engine bundled in the APK (nothing else can exist),
  ///   3. the app-managed engine dir (where an in-app engine update lands),
  ///   4. a binary bundled beside the app (the Microsoft Store MSIX ships one so
  ///      it never auto-downloads executable code — see [bundledDesktopBinary]),
  ///   5. `rclone` on the system PATH.
  ///
  /// The managed dir is checked *before* the bundled one on purpose: a fresh
  /// Store install has no managed binary, so it falls through to the bundled
  /// engine (no download), but a user-initiated "update engine" that lands in
  /// the managed dir then takes precedence on the next launch.
  static Future<String?> findExisting({String? overridePath}) async {
    if (overridePath != null && overridePath.isNotEmpty) {
      if (await File(overridePath).exists()) return overridePath;
    }
    if (Platform.isAndroid) return bundledAndroidBinary();
    final managed = await _managedBinaryPath();
    if (await File(managed).exists()) return managed;

    final bundled = await bundledDesktopBinary();
    if (bundled != null) return bundled;

    final onPath = await _whichRclone();
    return onPath;
  }

  /// A desktop rclone binary that ships *inside* the app package, placed beside
  /// the app executable. Only the Microsoft Store MSIX bundles one (CI drops a
  /// SHA256-verified `rclone.exe` into the packaged build; see release.yml):
  /// Store policy discourages downloading executable code at runtime, so the
  /// Store build carries the engine instead of fetching it on first run. The
  /// portable zip / Inno installer ship no such file, so this returns null for
  /// them and they keep the download-on-first-run + in-app-update behaviour.
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

  /// Downloads the latest official rclone, verifies its SHA-256 (fail-closed —
  /// throws a [StateError] if the checksum can't be fetched, parsed, or matched
  /// rather than installing an unverified engine), and extracts the binary into
  /// the app-managed engine dir (overwriting any existing one). Returns its path.
  static Future<String> downloadLatest({
    void Function(String)? onStatus,
  }) async {
    if (Platform.isAndroid) {
      // No downloadable engine exists for Android (and exec from app storage is
      // forbidden anyway) — the binary must come bundled in the APK.
      throw StateError('The bundled rclone engine is missing from this build.');
    }
    // A build that SHIPS a bundled engine (the Microsoft Store MSIX places one
    // beside the app) must never download + exec rclone at runtime — the Store
    // discourages downloading executable code. Presence of the bundled binary is
    // the runtime signal for "this flavour is engine-managed" (a `--dart-define`
    // wouldn't work: the Store MSIX repackages the already-compiled desktop build
    // via `msix:create --build-windows false`). The engine then updates only when
    // the app itself updates. Portable zip / installer builds ship no bundled
    // binary, so this never triggers for them.
    if (await bundledDesktopBinary() != null) {
      throw StateError(
        'This build bundles the rclone engine — update it by updating the app.',
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
    final destPath = await _managedBinaryPath();
    final out = File(destPath);
    await out.writeAsBytes(entry.content as List<int>, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', destPath]);
    }
    onStatus?.call('Engine ready (rclone $version).');
    return destPath;
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
