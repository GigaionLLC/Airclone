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
    if wantsNoWindow(args) {
      startHeadlessEngine(args)
    }
    super.applicationWillFinishLaunching(notification)
  }

  /// Runs Dart with NO window, for `--webui` and the scheduled-task flags.
  ///
  /// Hiding the window is not enough on macOS, and the reason is worth writing
  /// down: the engine lives inside the window's content view, and AppKit loads
  /// a content view lazily, when the window is about to appear. A window that
  /// never appears is an app that never runs - CI watched `--webui` sit for 90
  /// seconds without serving, having printed nothing at all.
  ///
  /// So a windowless run does not build a window (MainFlutterWindow returns
  /// early) and starts an engine directly instead. `allowHeadlessExecution` is
  /// exactly what that is for. The activation policy keeps it out of the Dock
  /// and off the menu bar, which is what a process serving a web interface
  /// should look like.
  private func startHeadlessEngine(_ args: [String]) {
    NSApplication.shared.setActivationPolicy(.accessory)
    let project = FlutterDartProject()
    // Dart reads these as main(List<String> args); without them --webui would
    // start the ordinary app, headless, with no way to say so.
    project.dartEntrypointArguments = Array(args.dropFirst())
    let engine = FlutterEngine(
      name: "airclone-headless",
      project: project,
      allowHeadlessExecution: true
    )
    engine.run(withEntrypoint: nil)
    RegisterGeneratedPlugins(registry: engine)
    // Hand-written, so it is not in GeneratedPluginRegistrant. A headless run
    // still resolves saved locations, which is what the bookmarks are.
    SecurityScopedBookmarks.register(with: engine.binaryMessenger)
    headlessEngine = engine
  }

  /// Held so ARC does not collect the engine the moment launching finishes.
  private var headlessEngine: FlutterEngine?

  /// Closing the last window quits - unless there was never meant to be one.
  /// A server that stopped because a window it never showed was closed would be
  /// a baffling way to lose a Web UI.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !wantsNoWindow(CommandLine.arguments)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
