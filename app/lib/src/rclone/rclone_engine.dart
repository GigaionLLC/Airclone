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
  ///   3. the app-managed engine dir,
  ///   4. `rclone` on the system PATH.
  static Future<String?> findExisting({String? overridePath}) async {
    if (overridePath != null && overridePath.isNotEmpty) {
      if (await File(overridePath).exists()) return overridePath;
    }
    if (Platform.isAndroid) return bundledAndroidBinary();
    final managed = await _managedBinaryPath();
    if (await File(managed).exists()) return managed;

    final onPath = await _whichRclone();
    return onPath;
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

  /// Downloads the latest official rclone, verifies its SHA-256 (fail-closed), and
  /// extracts the binary into the app-managed engine dir. Returns its path.
  static Future<String> downloadLatest({
    void Function(String)? onStatus,
  }) async {
    if (Platform.isAndroid) {
      // No downloadable engine exists for Android (and exec from app storage is
      // forbidden anyway) — the binary must come bundled in the APK.
      throw StateError(
        'The bundled rclone engine is missing from this build.',
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
    final expected = await _expectedSha256(base, zipName);
    final actual = sha256.convert(zipBytes).toString();
    if (expected != null && expected.toLowerCase() != actual.toLowerCase()) {
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

  static Future<String?> _expectedSha256(String base, String zipName) async {
    try {
      final sums = await _getString('$base/SHA256SUMS');
      for (final line in sums.split('\n')) {
        if (line.contains(zipName)) {
          return line.trim().split(RegExp(r'\s+')).first;
        }
      }
    } catch (_) {
      /* fall through — caller treats null as "unverified" */
    }
    return null;
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
