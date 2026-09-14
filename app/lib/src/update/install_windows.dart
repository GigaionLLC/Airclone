/// Installing a verified update on Windows, by running the new installer.
///
/// The Inno Setup installer Airclone ships can install over itself, which makes
/// this the one Windows path that needs no file juggling: hand the verified
/// `airclone-setup-x64.exe` the silent flags, let it replace the installation,
/// and get out of its way.
///
/// WHY THE APP MUST EXIT. Windows holds an open executable locked, so the
/// installer cannot replace `airclone.exe` while it is running. `/CLOSEAPPLICATIONS`
/// asks Restart Manager to close it, but relying on that means racing our own
/// shutdown - unsaved state, a running rclone child, a half-written config. So
/// the installer is started DETACHED and the app closes itself: by the time the
/// files are replaced there is nothing left to close.
///
/// WHAT THIS DOES NOT DO. It does not elevate. A per-machine install in Program
/// Files needs administrator rights, and the installer asks for them itself with
/// the UAC prompt the user already knows - that prompt is the honest place for
/// it, not a dialog of ours explaining why we would like to be an administrator.
///
/// The portable zip is NOT this. It has no installer, and replacing a locked
/// directory tree from inside it needs a helper process; it is handled
/// separately and deliberately later.
library;

import 'dart:io';

/// What happened when the installer was handed over.
enum WindowsInstallOutcome {
  /// The installer is running. The app must exit now.
  started,

  /// Not a Windows installer package.
  notAnInstaller,

  /// The file is missing, or Windows refused to start it.
  failed,
}

class WindowsInstallResult {
  const WindowsInstallResult(this.outcome, {this.detail});

  final WindowsInstallOutcome outcome;
  final String? detail;

  bool get ok => outcome == WindowsInstallOutcome.started;
}

/// The flags the Inno installer is given, and why each one is there.
///
/// Pure, so the command can be asserted rather than described. `/VERYSILENT`
/// rather than `/SILENT`: silent still shows a progress window, which for an
/// update the user already agreed to is a window that appears, steals focus and
/// vanishes.
///
///   * `/VERYSILENT`          - no wizard, no progress window.
///   * `/SUPPRESSMSGBOXES`    - no "are you sure" a nobody is there to answer.
///   * `/NORESTART`           - never reboot the machine. Airclone is a file
///                              manager; nothing it installs needs a restart,
///                              and an updater that reboots a workstation is
///                              one nobody forgives.
///   * `/CLOSEAPPLICATIONS`   - belt and braces. The app exits on its own, but
///                              a pop-out window or a stuck process must not
///                              block the install.
///   * `/RESTARTAPPLICATIONS` - start Airclone again when it is done, so the
///                              user ends where they started.
///   * `/LOG=<path>`          - somewhere to look when an install goes wrong,
///                              since nothing is on screen to read.
List<String> innoSilentArgs({String? logPath}) => [
  '/VERYSILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/CLOSEAPPLICATIONS',
  '/RESTARTAPPLICATIONS',
  if (logPath != null) '/LOG=$logPath',
];

/// True when [path] is the file this flow knows how to run.
///
/// Checked because the alternative is executing whatever was downloaded: the
/// verification upstream proves the file is the release's, and this proves it
/// is the release's INSTALLER rather than its zip, its AppImage or its APK.
bool isWindowsInstaller(String path) =>
    path.toLowerCase().endsWith('setup-x64.exe');

/// Starts the verified installer and returns immediately.
///
/// The caller must then exit the application - see the note above about locked
/// executables. Nothing here waits: the installer outlives this process by
/// design.
Future<WindowsInstallResult> runWindowsInstaller({
  required File verified,
  String? logPath,
}) async {
  if (!isWindowsInstaller(verified.path)) {
    return const WindowsInstallResult(WindowsInstallOutcome.notAnInstaller);
  }
  if (!verified.existsSync()) {
    return const WindowsInstallResult(
      WindowsInstallOutcome.failed,
      detail: 'the verified installer is not where it was left',
    );
  }
  try {
    await Process.start(
      verified.path,
      innoSilentArgs(logPath: logPath),
      // Detached: the installer has to outlive the app it is replacing.
      mode: ProcessStartMode.detached,
    );
    return const WindowsInstallResult(WindowsInstallOutcome.started);
  } catch (e) {
    return WindowsInstallResult(WindowsInstallOutcome.failed, detail: '$e');
  }
}
