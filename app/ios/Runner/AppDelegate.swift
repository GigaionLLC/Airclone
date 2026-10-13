import BackgroundTasks
import Flutter
import QuickLook
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// The file QuickLook is showing (#49). One at a time: a preview is modal.
  private var quickLookItem: URL?

  /// Held while a transfer is queued or running (#52): leaving the app then
  /// gets the extra time iOS allows instead of an immediate suspend.
  private var transferTask: UIBackgroundTaskIdentifier = .invalid

  /// The headless engine of a background run, kept alive until it reports.
  private var dueEngine: FlutterEngine?

  /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
  static let dueTaskId = "com.gigaionllc.airclone.due"
  private static let dueMinutesKey = "airclone.dueMinutes"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Registered before launch finishes, as BGTaskScheduler requires; a run iOS
    // starts after a cold background launch lands here.
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.dueTaskId, using: nil) {
      [weak self] task in
      guard let task = task as? BGProcessingTask else { return }
      self?.runDueTasks(task)
    }
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
      case "transferActive":
        let args = call.arguments as? [String: Any]
        self?.setTransferActive(
          args?["active"] as? Bool ?? false,
          keepScreenOn: args?["keepScreenOn"] as? Bool ?? false)
        result(nil)
      case "scheduleBackgroundRun":
        let minutes = (call.arguments as? [String: Any])?["minutes"] as? Int ?? 15
        UserDefaults.standard.set(minutes, forKey: Self.dueMinutesKey)
        Self.submitDueRequest(minutes: minutes)
        result(nil)
      case "cancelBackgroundRun":
        UserDefaults.standard.removeObject(forKey: Self.dueMinutesKey)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.dueTaskId)
        result(nil)
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

  private func setTransferActive(_ active: Bool, keepScreenOn: Bool) {
    UIApplication.shared.isIdleTimerDisabled = keepScreenOn
    if active, transferTask == .invalid {
      transferTask = UIApplication.shared.beginBackgroundTask(withName: "transfers") {
        [weak self] in self?.endTransferTask()
      }
    } else if !active {
      endTransferTask()
    }
  }

  private func endTransferTask() {
    guard transferTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(transferTask)
    transferTask = .invalid
  }

  /// Asks iOS for a background run no sooner than [minutes] from now. iOS
  /// picks the actual moment (typically charging, on Wi-Fi, idle).
  private static func submitDueRequest(minutes: Int) {
    let request = BGProcessingTaskRequest(identifier: dueTaskId)
    request.requiresNetworkConnectivity = true
    request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(max(minutes, 15) * 60))
    try? BGTaskScheduler.shared.submit(request)
  }

  /// One background run: re-arm the next, then run whatever is due through
  /// the headless entrypoint Android's WorkManager wake uses
  /// (android_work_entrypoint.dart), over the same `airclone/work_bg` contract
  /// as DueTasksWorker.kt.
  private func runDueTasks(_ task: BGProcessingTask) {
    let minutes = UserDefaults.standard.object(forKey: Self.dueMinutesKey) as? Int
    guard let minutes else {
      task.setTaskCompleted(success: true)
      return
    }
    Self.submitDueRequest(minutes: minutes)
    // Open on screen: the in-app scheduler is already running what is due.
    if UIApplication.shared.applicationState == .active || dueEngine != nil {
      task.setTaskCompleted(success: true)
      return
    }
    let engine = FlutterEngine(name: "airclone-due", project: nil, allowHeadlessExecution: true)
    var finished = false
    let finish: (Bool) -> Void = { [weak self] ok in
      guard !finished else { return }
      finished = true
      task.setTaskCompleted(success: ok)
      self?.dueEngine?.destroyContext()
      self?.dueEngine = nil
    }
    let channel = FlutterMethodChannel(
      name: "airclone/work_bg", binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        result(["args": ["--run-due", "--timeout-minutes", "20"]])
      case "log":
        NSLog("airclone due: %@", ((call.arguments as? [String: Any])?["line"] as? String) ?? "")
        result(nil)
      case "done":
        let code = (call.arguments as? [String: Any])?["code"] as? Int ?? 1
        result(nil)
        DispatchQueue.main.async { finish(code == 0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    task.expirationHandler = { DispatchQueue.main.async { finish(false) } }
    dueEngine = engine
    engine.run(
      withEntrypoint: "androidWorkEntrypoint",
      libraryURI: "package:airclone/src/state/android_work_entrypoint.dart")
    GeneratedPluginRegistrant.register(with: engine)
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
