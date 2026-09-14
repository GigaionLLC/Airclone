import Cocoa
import FlutterMacOS

/// What `--help` prints. Written a third time here - Dart has `usageText` for
/// the flags it answers, Linux has `PrintHelp` in C++ - because these three
/// cannot share a string. `cli_info_test.dart` holds all three to the same list
/// of flags, which is the part that would otherwise rot.
private let macOSUsageText = """

Usage: airclone [options]

With no options, Airclone opens its window.

Options:
  --webui                 Serve the interface to browsers instead of opening a
                          window. Prints its URL and the generated password on
                          first run.
  --webui-bind ADDRESS    Address for --webui to listen on. Default 127.0.0.1
                          (loopback only).
  --webui-port PORT       Port for --webui. Default 5799.

  --run-due               Run every scheduled task that is due, then exit.
  --run-task ID           Run one saved task by id, then exit.

  --log-input             Print one line per key event, and whether a text field
                          had focus to receive it.

  --version               Print the version and exit.
  --help, -h              Print this and exit.
"""

/// The version this build was made from, injected by the Xcode build settings
/// that Flutter generates (`FLUTTER_BUILD_NAME` reaches Info.plist as
/// CFBundleShortVersionString).
private func airCloneVersion() -> String {
  let info = Bundle.main.infoDictionary
  let version = info?["CFBundleShortVersionString"] as? String
  return version.map { "Airclone \($0)" } ?? "Airclone (version unknown)"
}

@main
class AppDelegate: FlutterAppDelegate {
  /// `--version` and `--help`, answered HERE, before the engine exists.
  ///
  /// THE BUG THIS FIXES: `Airclone.app/Contents/MacOS/Airclone --version` never
  /// answered at all. The Dart entrypoint knows these flags (cli_info.dart), but
  /// reaching Dart means starting an engine inside a view inside a window, and a
  /// process launched from a terminal to ask one question sat there instead -
  /// a CI run waited 25 minutes for a version string before it was killed.
  ///
  /// Answering in Swift costs nothing and cannot hang: no nib, no engine, no
  /// window server. Linux answers the same two flags in C++ for the same reason
  /// (linux/runner/my_application.cc).
  override func applicationWillFinishLaunching(_ notification: Notification) {
    let args = CommandLine.arguments
    if args.contains("--version") {
      print(airCloneVersion())
      exit(0)
    }
    if args.contains("--help") || args.contains("-h") {
      print(airCloneVersion())
      print(macOSUsageText)
      exit(0)
    }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
