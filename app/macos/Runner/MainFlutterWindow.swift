import Cocoa
import FlutterMacOS
// desktop_multi_window: register plugins into each pop-out window's engine too.
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
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
}
