import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// An executable + its argv. Never a shell string — each element is passed
/// verbatim to the OS, so a filename containing spaces/`&`/`;`/quotes/unicode
/// cannot inject a command.
typedef OsCommand = ({String exe, List<String> args});

/// Seam for spawning a process, so the reveal logic is unit-testable without
/// actually launching anything.
typedef ProcessRunner =
    Future<ProcessResult> Function(String exe, List<String> args);

/// Builds the "reveal/select this file in the native file manager" command for
/// [os], targeting [absPath] (which MUST already be absolute). Pure and
/// unit-testable — it launches nothing. See `os_integration_test.dart`.
///
/// Per-OS, using documented OS commands (no community plugin, no native build):
/// - Windows: `explorer.exe /select,<path>` — the switch and path are ONE argv
///   element joined by the comma (explorer uses its own comma-field parser, not
///   `CommandLineToArgvW`). A path containing `,` or `=` gets the path portion
///   double-quoted.
/// - macOS: `open -R <path>` (Reveal in Finder).
/// - Linux: the freedesktop `org.freedesktop.FileManager1.ShowItems` D-Bus
///   method (selects the file in Nautilus/Dolphin/Nemo/…), via `dbus-send`.
///   Falls back to opening the containing folder — see [revealFallbackCommand].
OsCommand revealCommand(TargetPlatform os, String absPath) {
  switch (os) {
    case TargetPlatform.windows:
      // explorer.exe ONLY understands backslashes; rclone's local fs hands us
      // forward slashes (C:/Users/…), and a forward-slash path makes explorer
      // silently ignore /select and open the default location (the Desktop).
      final win = absPath.replaceAll('/', r'\');
      final needsQuote = win.contains(',') || win.contains('=');
      final pathArg = needsQuote ? '"$win"' : win;
      return (exe: 'explorer.exe', args: ['/select,$pathArg']);
    case TargetPlatform.macOS:
      return (exe: 'open', args: ['-R', absPath]);
    default:
      return (
        exe: 'dbus-send',
        args: [
          '--session',
          '--print-reply',
          '--dest=org.freedesktop.FileManager1',
          '/org/freedesktop/FileManager1',
          'org.freedesktop.FileManager1.ShowItems',
          'array:string:${Uri.file(absPath)}',
          'string:',
        ],
      );
  }
}

/// Linux fallback when the D-Bus FileManager1 service isn't available: open the
/// CONTAINING DIRECTORY (xdg-open on the file itself would *open* it, not reveal
/// it). Does not select the file.
OsCommand revealFallbackCommand(String absPath) =>
    (exe: 'xdg-open', args: [File(absPath).parent.path]);

/// Whether a spawned reveal counts as success, per the per-OS exit-code policy.
///
/// Windows `explorer.exe` returns a NON-ZERO exit code even on success, so its
/// exit code is meaningless — success there means only that the binary launched
/// (no [ProcessException]). macOS/Linux follow normal `0 == success`.
bool isSpawnSuccess(TargetPlatform os, ProcessResult? result, Object? thrown) {
  if (thrown != null || result == null) return false;
  if (os == TargetPlatform.windows) return true; // exit code is unreliable
  return result.exitCode == 0;
}

/// Official, agent-verifiable OS interop for LOCAL files: reveal in the file
/// manager, open with the default app ([url_launcher]), and copy a path to the
/// clipboard ([Clipboard]). No community drag plugin, no native toolchain.
class OsIntegration {
  OsIntegration({
    ProcessRunner? runner,
    TargetPlatform? platform,
    Future<bool> Function(Uri url)? launch,
  }) : _run = runner ?? ((e, a) => Process.run(e, a, runInShell: false)),
       _os = platform ?? defaultTargetPlatform,
       _launch = launch ?? launchUrl;

  final ProcessRunner _run;
  final TargetPlatform _os;
  final Future<bool> Function(Uri url) _launch;

  /// Reveals [path] in the OS file manager (selecting it where supported).
  /// Returns true on apparent success. On Linux, falls back to opening the
  /// containing folder if the FileManager1 D-Bus call fails.
  Future<bool> revealInFileManager(String path) async {
    final abs = File(path).absolute.path;
    final cmd = revealCommand(_os, abs);
    ProcessResult? res;
    Object? err;
    try {
      res = await _run(cmd.exe, cmd.args);
    } catch (e) {
      err = e;
    }
    if (isSpawnSuccess(_os, res, err)) return true;
    if (_os == TargetPlatform.linux) {
      final fb = revealFallbackCommand(abs);
      try {
        final r = await _run(fb.exe, fb.args);
        return r.exitCode == 0;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Opens [path] with its default OS application. Returns false if the file is
  /// missing or the OS rejected the request.
  Future<bool> openWithDefaultApp(String path) async {
    final f = File(path);
    if (!f.existsSync()) return false;
    try {
      return await _launch(Uri.file(f.absolute.path));
    } catch (_) {
      return false;
    }
  }

  /// Copies [text] (a file path) to the OS clipboard as plain text.
  Future<void> copyToClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final osIntegrationProvider = Provider<OsIntegration>((_) => OsIntegration());
