import Flutter
import QuickLook
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// The file QuickLook is showing (#49). One at a time: a preview is modal.
  private var quickLookItem: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AircloneNative")
    else { return }
    // The same channel name Android's NativeChannel.kt answers. Methods iOS
    // does not implement report not-implemented, which Dart sees exactly as it
    // did before this channel existed (a MissingPluginException).
    let channel = FlutterMethodChannel(
      name: "airclone/native", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "quickLook":
        guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "path is required", details: nil))
          return
        }
        self?.presentQuickLook(URL(fileURLWithPath: path), result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Shows [url] in QuickLook, the previewer Files and Mail use: Word, Excel,
  /// PowerPoint, Pages, Numbers, Keynote, RTF, PDF, images and more, with its
  /// own share button. Answers false when QuickLook cannot preview the type, so
  /// Dart offers the share sheet instead.
  private func presentQuickLook(_ url: URL, result: FlutterResult) {
    guard QLPreviewController.canPreview(url as NSURL) else {
      result(false)
      return
    }
    guard let top = Self.topViewController() else {
      result(FlutterError(code: "no_view", message: "Nothing on screen to present from", details: nil))
      return
    }
    quickLookItem = url
    let preview = QLPreviewController()
    preview.dataSource = self
    top.present(preview, animated: true)
    result(true)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
      ?? scene?.windows.first?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

extension AppDelegate: QLPreviewControllerDataSource {
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    quickLookItem == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
    -> QLPreviewItem
  {
    (quickLookItem ?? URL(fileURLWithPath: "/")) as NSURL
  }
}
