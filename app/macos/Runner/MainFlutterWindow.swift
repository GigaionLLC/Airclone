import Cocoa
import FlutterMacOS
// desktop_multi_window: register plugins into each pop-out window's engine too.
import desktop_multi_window

/// Flags that run Dart without wanting a window. The Dart entrypoint branches on
/// these before runApp (lib/main.dart), but on macOS the window comes from the
/// nib and AppKit shows it regardless - so `airclone --webui`, meant for a
/// machine you are not sitting at, put an empty window and a Dock icon on screen
/// and left them there for as long as the server ran. Linux had the same bug,
/// from a different cause (linux/runner/my_application.cc).
///
/// `--version` and `--help` are here too, though they never reach Dart at all:
/// AppDelegate answers them and exits. The nib is loaded BEFORE that happens, so
/// without this the view controller would start an engine that is torn down
/// milliseconds later - which printed "'FlutterEngineSendPlatformMessage'
/// returned 'kInvalidArguments'" above the version string, on every ask.
///
/// Kept in step with `WantsWindowlessDart` in the Linux runner and
/// `isHeadlessInvocation`/`isWebUiInvocation` in Dart.
func wantsNoWindow(_ args: [String]) -> Bool {
  for a in args {
    switch a {
    case "--webui", "--run-due", "--run-task", "--update",
      "--version", "--help", "-h":
      return true
    default:
      if a.hasPrefix("--run-task=") { return true }
    }
  }
  return false
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // A windowless run builds NO view controller: AppDelegate has already
    // started a headless engine, and a second one here would run main() twice.
    // The nib still creates this window; nothing ever shows it.
    if wantsNoWindow(CommandLine.arguments) {
      super.awakeFromNib()
      return
    }

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // Hand-written, so it is NOT in GeneratedPluginRegistrant and has to be
    // registered here explicitly.
    SecurityScopedBookmarks.register(with: flutterViewController.engine.binaryMessenger)

    // Every window desktop_multi_window creates (each pop-out image viewer)
    // gets the generated plugins registered on its own engine. The bookmark
    // channel goes on too: a pop-out that called it against an unregistered
    // engine would get notImplemented, which reads as "no access" rather than
    // "wrong engine" and would be miserable to debug.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      SecurityScopedBookmarks.register(with: controller.engine.binaryMessenger)
    }

    super.awakeFromNib()
  }

  // The nib is marked visible at launch, so AppKit orders the window front
  // AFTER awakeFromNib has run - ordering it out up there is not enough on its
  // own. These two are every route to the screen.
  override func makeKeyAndOrderFront(_ sender: Any?) {
    if wantsNoWindow(CommandLine.arguments) { return }
    super.makeKeyAndOrderFront(sender)
  }

  override func orderFront(_ sender: Any?) {
    if wantsNoWindow(CommandLine.arguments) { return }
    super.orderFront(sender)
  }
}
