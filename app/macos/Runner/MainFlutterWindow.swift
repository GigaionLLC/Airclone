import Cocoa
import FlutterMacOS
import ServiceManagement
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

/// `--tray` on the command line (#54). A login-item launch is the other way to
/// start hidden; AppDelegate spots that from the launch Apple event.
func wantsTrayLaunch(_ args: [String]) -> Bool {
  return !wantsNoWindow(args) && args.contains("--tray")
}

class MainFlutterWindow: NSWindow {
  /// The one main window, for AppDelegate (Dock click, login launch).
  static weak var main: MainFlutterWindow?

  /// 'airclone/window' (#54). Dart side: lib/src/state/desktop_window.dart.
  private var windowChannel: FlutterMethodChannel?

  /// Set by Dart once the tray icon exists: the close button then asks Dart
  /// (hide to the tray, or quit) instead of closing, which here quits the app.
  private(set) var interceptClose = false

  /// This launch should start in the tray.
  private(set) var startedHidden = false

  /// Held while the window is hidden. A hidden app with no visible window is
  /// what App Nap throttles, and the scheduler and transfers keep time with
  /// Dart timers that must not drift by minutes.
  private var hiddenActivity: NSObjectProtocol?

  /// Starts hidden in the tray. The engine only runs once its view has been on
  /// screen (see AppDelegate.startHeadlessEngine), so the window still goes up,
  /// fully transparent and click-through, and Dart takes it down for real once
  /// the tray icon exists. If there is no tray, Dart shows it instead.
  func beginHidden() {
    startedHidden = true
    alphaValue = 0
    ignoresMouseEvents = true
  }

  func hideToTray() {
    orderOut(nil)
    alphaValue = 1
    ignoresMouseEvents = false
    if hiddenActivity == nil {
      hiddenActivity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiatedAllowingIdleSystemSleep],
        reason: "Airclone keeps transferring and scheduling with its window closed"
      )
    }
  }

  func showFromTray() {
    alphaValue = 1
    ignoresMouseEvents = false
    if let a = hiddenActivity {
      ProcessInfo.processInfo.endActivity(a)
      hiddenActivity = nil
    }
    if isMiniaturized { deminiaturize(nil) }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// The red button and Cmd-W both arrive here. A real quit (Cmd-Q, the tray's
  /// Quit) goes through NSApp.terminate and never does.
  override func performClose(_ sender: Any?) {
    if interceptClose, let channel = windowChannel {
      channel.invokeMethod("closeRequested", arguments: nil)
      return
    }
    super.performClose(sender)
  }

  private func handleWindowCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hide":
      hideToTray()
      result(nil)
    case "show":
      showFromTray()
      result(nil)
    case "startedHidden":
      result(startedHidden)
    case "trayHostAvailable":
      result(true)  // the menu bar is always there
    case "setInterceptClose":
      interceptClose = (call.arguments as? Bool) ?? false
      result(nil)
    case "autostartEnabled":
      if #available(macOS 13.0, *) {
        result(Self.loginItemOn())
      } else {
        result(FlutterMethodNotImplemented)  // reads as "not offered" in Dart
      }
    case "setAutostart":
      guard let on = call.arguments as? Bool else {
        result(FlutterError(code: "bad-args", message: "setAutostart takes a bool", details: nil))
        return
      }
      if #available(macOS 13.0, *) {
        // SMAppService.mainApp registers THIS app bundle and nothing else; it
        // is the sandbox-safe API, so the Mac App Store build can use it too.
        do {
          if on {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
        } catch {
          // Unregistering an item that is not there throws; the status below
          // is the truth either way.
        }
        if on && SMAppService.mainApp.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
        }
        result(Self.loginItemOn())
      } else {
        result(FlutterMethodNotImplemented)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(macOS 13.0, *)
  private static func loginItemOn() -> Bool {
    switch SMAppService.mainApp.status {
    case .enabled, .requiresApproval: return true
    default: return false
    }
  }

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

    MainFlutterWindow.main = self
    let channel = FlutterMethodChannel(
      name: "airclone/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleWindowCall(call, result: result)
    }
    windowChannel = channel
    if wantsTrayLaunch(CommandLine.arguments) { beginHidden() }

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
