import AppKit
import FlutterMacOS

/// Security-scoped bookmarks — the only way a sandboxed macOS app can keep
/// access to a user's folder across launches.
///
/// Under the App Sandbox the app may read a local folder only after the user
/// picks it in an `NSOpenPanel` (the grant arrives through PowerBox, not by us
/// naming a path). That grant dies with the process. A *security-scoped
/// bookmark* is the token that survives, and resolving it re-acquires the grant.
///
/// This is hand-written rather than taken from a package on purpose. The only
/// pub.dev package that does the whole lifecycle (`macos_secure_bookmarks`) has
/// had no commit since 2022, never surfaces `isStale` to Dart — so a caller
/// cannot tell a stale bookmark from a broken one — and lacks Swift Package
/// Manager support, which Flutter already warns about and intends to make an
/// error. Airclone needs all three.
///
/// Registered on the `airclone/native` channel, matching the Android idiom in
/// `MainActivity.kt`. See `state/mac_bookmarks.dart` for the Dart side and
/// `dev/plans/apple-appstore-plan.md` Gate C1.
enum SecurityScopedBookmarks {
  /// Resolved URLs, keyed by the base64 bookmark that produced them.
  ///
  /// This cache is load-bearing, not an optimisation: macOS requires
  /// `startAccessingSecurityScopedResource` and its matching `stop` to be called
  /// on the *same* `URL` instance that came out of the resolve. Re-resolving to
  /// an equal-looking URL and calling `stop` on that silently fails to release
  /// the resource, which leaks a kernel resource that is NOT unlimited.
  private static var resolved: [String: URL] = [:]

  /// Register the handler on an engine's binary messenger.
  static func register(with registrar: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "airclone/native", binaryMessenger: registrar)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "grantFolder": grantFolder(call, result)
      case "resolveBookmark": resolveBookmark(call, result)
      case "startAccess": startAccess(call, result)
      case "stopAccess": stopAccess(call, result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Show the folder picker and return `{path, bookmark}`, or nil if cancelled.
  ///
  /// The start/stop dance below is not redundant. `NSOpenPanel` *implicitly*
  /// calls `startAccessingSecurityScopedResource` for backward compatibility
  /// (unlike iOS's document picker), and these calls are **not reference
  /// counted** — so after taking our own start we must stop twice to leave the
  /// count where we found it. Getting this wrong leaks the resource for the life
  /// of the process.
  private static func grantFolder(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.prompt = "Grant access"
      if let args = call.arguments as? [String: Any],
        let initial = args["initialPath"] as? String, !initial.isEmpty
      {
        panel.directoryURL = URL(fileURLWithPath: initial)
      }

      guard panel.runModal() == .OK, let url = panel.url else {
        result(nil)  // cancelled — not an error
        return
      }

      let started = url.startAccessingSecurityScopedResource()
      defer {
        if started { url.stopAccessingSecurityScopedResource() }
        url.stopAccessingSecurityScopedResource()  // the panel's implicit one
      }

      do {
        let data = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil)
        result(["path": url.path, "bookmark": data.base64EncodedString()])
      } catch {
        result(
          FlutterError(
            code: "bookmark_failed",
            message: "Could not create a bookmark for \(url.path): \(error.localizedDescription)",
            details: nil))
      }
    }
  }

  /// Resolve a stored bookmark back to a path.
  ///
  /// `isStale` is returned rather than swallowed: a stale bookmark still
  /// resolves and still works, but macOS is telling us to re-create and re-store
  /// it. Ignoring that is how a Location quietly stops working after an OS
  /// update — and bookmarks have been observed going invalid across macOS point
  /// releases, so the caller must always be able to fall back to re-prompting.
  private static func resolveBookmark(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let b64 = args["bookmark"] as? String,
      let data = Data(base64Encoded: b64)
    else {
      result(FlutterError(code: "bad_args", message: "bookmark (base64) required", details: nil))
      return
    }
    var stale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale)
      resolved[b64] = url
      result(["path": url.path, "isStale": stale])
    } catch {
      // Distinct from bad_args on purpose: the Dart side maps this to "this
      // Location needs re-granting", which is a different user-facing outcome
      // from a programming error.
      result(
        FlutterError(
          code: "resolve_failed",
          message: "Bookmark could not be resolved: \(error.localizedDescription)",
          details: nil))
    }
  }

  private static func startAccess(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let b64 = args["bookmark"] as? String
    else {
      result(FlutterError(code: "bad_args", message: "bookmark required", details: nil))
      return
    }
    guard let url = resolved[b64] else {
      result(
        FlutterError(
          code: "not_resolved",
          message: "resolveBookmark must be called before startAccess",
          details: nil))
      return
    }
    result(url.startAccessingSecurityScopedResource())
  }

  /// Release a grant. Safe to call for an unknown bookmark — a no-op beats an
  /// exception on a teardown path.
  private static func stopAccess(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    if let args = call.arguments as? [String: Any],
      let b64 = args["bookmark"] as? String,
      let url = resolved[b64]
    {
      url.stopAccessingSecurityScopedResource()
      resolved.removeValue(forKey: b64)
    }
    result(nil)
  }
}
