/// "Start Airclone in the tray when I sign in" (#54).
///
/// One switch, three mechanisms, and a few builds where it is hidden on
/// purpose:
///
///   * Windows (installer, portable): a value under
///     `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, written by the
///     runner (windows/runner/flutter_window.cpp) from the module's own path
///     plus `--tray`. Nothing from Dart reaches the registry string.
///   * macOS 13+, including the Mac App Store build: `SMAppService.mainApp`,
///     which is the sandbox-safe login item API. The user can also see and
///     remove it in System Settings > General > Login Items.
///   * Linux (AppImage, tarball): an XDG autostart entry at
///     `~/.config/autostart/com.gigaionllc.airclone.desktop`, written here.
///
/// Hidden, with the reason in [AutostartSupport.reason]:
///   * Microsoft Store (MSIX): a packaged app cannot use the Run key; it needs
///     a `windows.startupTask` manifest extension plus the WinRT StartupTask
///     API to ask for it, and passing `--tray` there (`uap10:Parameters`)
///     needs Windows 10 2004, above the package's current minimum (1809).
///   * Flatpak: the sandbox cannot write the host's autostart folder; the
///     route is the Background portal, which is not wired up.
///   * Snap: there is no Snap package, and confined snaps declare autostart in
///     snapcraft.yaml, not at runtime.
///   * macOS 10.15-12: SMAppService does not exist yet.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'build_flavor.dart';
import 'desktop_window.dart';
import 'host_platform.dart';
import 'install_source.dart';

/// Whether this build can offer the sign-in launch, and if not, why.
@immutable
class AutostartSupport {
  const AutostartSupport.supported() : supported = true, reason = null;
  const AutostartSupport.unsupported(this.reason) : supported = false;

  final bool supported;
  final String? reason;
}

/// The flag every autostart entry passes, so the launch starts hidden.
const String kTrayLaunchFlag = '--tray';

/// The XDG autostart file name: the app id, so it can never collide with
/// another app's entry and a second write replaces the first.
const String kLinuxAutostartFileName = 'com.gigaionllc.airclone.desktop';

/// Platform decision, kept pure for tests.
AutostartSupport autostartSupportFor({
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
  required bool msix,
  required bool flatpak,
  required bool snap,
  required bool nativeAvailable,
}) {
  if (isWindows) {
    if (msix) {
      return const AutostartSupport.unsupported(
        'Microsoft Store builds start at sign-in only through Windows '
        'Settings > Apps > Startup, which Airclone does not register for yet.',
      );
    }
    return nativeAvailable
        ? const AutostartSupport.supported()
        : const AutostartSupport.unsupported('Not available in this build.');
  }
  if (isMacOS) {
    return nativeAvailable
        ? const AutostartSupport.supported()
        : const AutostartSupport.unsupported('Needs macOS 13 or later.');
  }
  if (isLinux) {
    if (flatpak) {
      return const AutostartSupport.unsupported(
        'The Flatpak sandbox cannot add itself to your startup applications. '
        "Add Airclone in your desktop's startup settings, with --tray.",
      );
    }
    if (snap) {
      return const AutostartSupport.unsupported(
        'Snap builds cannot add themselves to your startup applications.',
      );
    }
    return const AutostartSupport.supported();
  }
  return const AutostartSupport.unsupported('Desktop only.');
}

/// Quotes [path] as one argument of a Desktop Entry `Exec` key, then applies
/// the string-value escaping the file format adds on top.
///
/// Spec (Desktop Entry 1.5, "The Exec key"): an argument with reserved
/// characters is double-quoted, and inside the quotes `"`, `` ` ``, `$` and
/// `\` take a backslash. `%` is a field code everywhere, so a literal one is
/// `%%`. Then, as for any string value, every `\` is written `\\`.
///
/// Throws [ArgumentError] on a control character: a newline would end the key
/// and start another, which is the only way a path could inject an entry.
String desktopExecQuote(String path) {
  if (path.codeUnits.any((u) => u < 0x20 || u == 0x7f)) {
    throw ArgumentError.value(path, 'path', 'contains a control character');
  }
  final quoted = StringBuffer('"');
  for (final ch in path.split('')) {
    switch (ch) {
      case '"':
      case '`':
      case r'$':
      case r'\':
        quoted.write('\\$ch');
      case '%':
        quoted.write('%%');
      default:
        quoted.write(ch);
    }
  }
  quoted.write('"');
  return quoted.toString().replaceAll(r'\', r'\\');
}

/// The whole autostart file for an executable at [executable].
String linuxAutostartEntry(String executable) =>
    '[Desktop Entry]\n'
    'Type=Application\n'
    'Name=Airclone\n'
    'Comment=Start Airclone in the tray\n'
    'Exec=${desktopExecQuote(executable)} $kTrayLaunchFlag\n'
    'Icon=com.gigaionllc.airclone\n'
    'Terminal=false\n'
    'X-GNOME-Autostart-enabled=true\n';

/// The program the Linux entry should launch: the AppImage file itself when
/// running from one (the runtime exports `APPIMAGE`; the binary inside lives
/// on a mount that is gone after this session), otherwise this executable.
/// Only ever this app's own path, and only an existing absolute file.
String? linuxAutostartExecutable(
  Map<String, String> env,
  String resolvedExecutable, {
  bool Function(String path)? exists,
}) {
  final fileExists = exists ?? (p) => File(p).existsSync();
  final appImage = env['APPIMAGE'];
  for (final candidate in [appImage, resolvedExecutable]) {
    if (candidate == null || candidate.isEmpty) continue;
    if (!candidate.startsWith('/')) continue;
    if (!fileExists(candidate)) continue;
    return candidate;
  }
  return null;
}

/// `$XDG_CONFIG_HOME/autostart`, or `~/.config/autostart`.
String? linuxAutostartDir(Map<String, String> env) {
  final xdg = env['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.startsWith('/')) return '$xdg/autostart';
  final home = env['HOME'];
  if (home == null || home.isEmpty) return null;
  return '$home/.config/autostart';
}

/// The current state of the sign-in launch, and the support decision.
@immutable
class AutostartState {
  const AutostartState({
    this.support = const AutostartSupport.unsupported(null),
    this.enabled = false,
    this.busy = false,
  });

  final AutostartSupport support;
  final bool enabled;
  final bool busy;
}

class Autostart extends Notifier<AutostartState> {
  @override
  AutostartState build() {
    if (HostPlatform.isDesktop) _load();
    return const AutostartState();
  }

  Future<void> _load() async {
    final native = (HostPlatform.isWindows || HostPlatform.isMacOS)
        ? await DesktopWindow.nativeAutostartEnabled()
        : null;
    final support = autostartSupportFor(
      isWindows: HostPlatform.isWindows,
      isMacOS: HostPlatform.isMacOS,
      isLinux: HostPlatform.isLinux,
      msix: HostPlatform.isWindows && windowsPackageFamilyName() != null,
      flatpak: kRunningInFlatpak,
      snap: (HostPlatform.environment['SNAP'] ?? '').isNotEmpty,
      nativeAvailable: native != null,
    );
    var enabled = native ?? false;
    if (HostPlatform.isLinux && support.supported) {
      enabled = _linuxFile()?.existsSync() ?? false;
    }
    state = AutostartState(support: support, enabled: enabled);
  }

  File? _linuxFile() {
    final dir = linuxAutostartDir(HostPlatform.environment);
    return dir == null ? null : File('$dir/$kLinuxAutostartFileName');
  }

  /// Turns the sign-in launch on or off. Returns false when it could not be
  /// changed; the state then shows what is really there.
  Future<bool> set(bool enabled) async {
    if (!state.support.supported) return false;
    state = AutostartState(
      support: state.support,
      enabled: state.enabled,
      busy: true,
    );
    var now = state.enabled;
    var ok = false;
    try {
      if (HostPlatform.isLinux) {
        final file = _linuxFile();
        if (file != null) {
          if (enabled) {
            final exe = linuxAutostartExecutable(
              HostPlatform.environment,
              Platform.resolvedExecutable,
            );
            if (exe != null) {
              await file.parent.create(recursive: true);
              await file.writeAsString(linuxAutostartEntry(exe), flush: true);
            }
          } else if (await file.exists()) {
            await file.delete();
          }
          now = await file.exists();
          ok = now == enabled;
        }
      } else {
        final r = await DesktopWindow.setNativeAutostart(enabled);
        if (r != null) {
          now = r;
          ok = r == enabled;
        }
      }
    } catch (_) {
      ok = false;
    }
    state = AutostartState(support: state.support, enabled: now);
    return ok;
  }
}

final autostartProvider = NotifierProvider<Autostart, AutostartState>(
  Autostart.new,
);
