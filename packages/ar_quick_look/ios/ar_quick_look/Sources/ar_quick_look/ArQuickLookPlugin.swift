import Foundation
import QuickLook
import UIKit
@preconcurrency import Flutter

public class ArQuickLookPlugin: NSObject, FlutterPlugin {
  /// The presentation in flight. AR Quick Look is modal and full-screen, so
  /// there is at most one.
  private var session: PreviewSession?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.shakib/ar_quick_look", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ArQuickLookPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "canPreview":
      result(Self.canPreview(args["path"] as? String))
    case "present":
      present(args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Whether Quick Look will show this particular file.
  ///
  /// Asked of the file rather than of the OS version, because the answer
  /// depends on the format: a `.usdz` previews, a `.txt` renamed to `.usdz`
  /// does not, and neither does a path that is not there.
  private static func canPreview(_ path: String?) -> Bool {
    guard let path, FileManager.default.fileExists(atPath: path) else {
      return false
    }
    let item = ARQuickLookPreviewItem(fileAt: URL(fileURLWithPath: path))
    return QLPreviewController.canPreview(item)
  }

  private func present(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let paths = args["paths"] as? [String], !paths.isEmpty else {
      return result(
        FlutterError(code: "noItems", message: "No files to preview.", details: nil))
    }
    let missing = paths.filter { !FileManager.default.fileExists(atPath: $0) }
    guard missing.isEmpty else {
      return result(
        FlutterError(
          code: "notFound",
          message: "No file at \(missing.joined(separator: ", ")).",
          details: nil))
    }

    let scaling = args["allowsContentScaling"] as? Bool ?? true
    let webPage = (args["canonicalWebPage"] as? String).flatMap(URL.init(string:))
    let index = args["initialIndex"] as? Int ?? 0

    let items: [ARQuickLookPreviewItem] = paths.map { path in
      let item = ARQuickLookPreviewItem(fileAt: URL(fileURLWithPath: path))
      item.allowsContentScaling = scaling
      // Quick Look shows a Share button; this is where it points.
      item.canonicalWebPageURL = webPage
      return item
    }

    // Every item, not just the first: presentAll existence-checks all of them
    // and the controller opens on initialIndex, so a bad model at any other
    // position sailed past this and failed inside Quick Look instead.
    if let bad = zip(paths, items).first(where: { !QLPreviewController.canPreview($0.1) }) {
      return result(
        FlutterError(
          code: "unsupportedFile",
          message: "Quick Look cannot preview \(bad.0). USDZ and Reality "
            + "files are what AR Quick Look accepts.",
          details: nil))
    }

    // A second present() used to overwrite `session`, deallocating the first.
    // The open viewer went blank — the controller holds its data source
    // weakly — and the first Dart future never completed. Refusing is the
    // honest answer: there is one screen.
    guard session == nil else {
      return result(
        FlutterError(
          code: "alreadyPresenting",
          message: "A preview is already on screen. Wait for it to close "
            + "before presenting another.",
          details: nil))
    }

    DispatchQueue.main.async { [weak self] in
      guard let host = Self.topViewController() else {
        return result(
          FlutterError(
            code: "noHost", message: "No view controller to present from.",
            details: nil))
      }
      let controller = QLPreviewController()
      let session = PreviewSession(items: items) { [weak self] in
        self?.session = nil
        result(nil)
      }
      controller.dataSource = session
      controller.delegate = session
      controller.currentPreviewItemIndex = min(max(index, 0), items.count - 1)
      // Held by the plugin: the controller keeps both of these weakly, and
      // once they are gone the preview shows nothing and never reports back.
      self?.session = session
      host.present(controller, animated: true)
    }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap {
      $0 as? UIWindowScene
    }
    let window =
      scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// Feeds the controller its items and reports when the user closes it.
final class PreviewSession: NSObject, QLPreviewControllerDataSource,
  QLPreviewControllerDelegate
{
  init(items: [ARQuickLookPreviewItem], onDismiss: @escaping () -> Void) {
    self.items = items
    self.onDismiss = onDismiss
  }

  private let items: [ARQuickLookPreviewItem]
  private var onDismiss: (() -> Void)?

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    items.count
  }

  func previewController(
    _ controller: QLPreviewController, previewItemAt index: Int
  ) -> QLPreviewItem {
    items[index]
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    // Fired once; the Dart future completes here rather than on present, so
    // callers can await the whole interaction.
    let callback = onDismiss
    onDismiss = nil
    callback?()
  }
}
