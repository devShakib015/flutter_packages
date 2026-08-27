import Foundation
import ImageIO
import CoreGraphics

#if canImport(UniformTypeIdentifiers)
  import UniformTypeIdentifiers
#endif

// @preconcurrency: Flutter's ObjC types predate Sendable annotations, and
// hopping to the main queue is exactly how they are meant to be used.
#if os(iOS)
  @preconcurrency import Flutter
  import UIKit
#elseif os(macOS)
  @preconcurrency import FlutterMacOS
  import AppKit
#endif

// Guarded so the plugin still compiles on an Xcode without the SDK that has
// ImagePlayground. Those builds report `osTooOld` instead of failing to build,
// which keeps the package addable to an app that has not moved Xcode yet.
#if canImport(ImagePlayground)
  import ImagePlayground
#endif

public class AppleIntelligencePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private var eventSink: FlutterEventSink?
  private var running: [Int: Task<Void, Never>] = [:]

  // MARK: - Registration

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif

    let instance = AppleIntelligencePlugin()
    let method = FlutterMethodChannel(
      name: "dev.shakib/apple_intelligence", binaryMessenger: messenger)
    let events = FlutterEventChannel(
      name: "dev.shakib/apple_intelligence/events", binaryMessenger: messenger)

    registrar.addMethodCallDelegate(instance, channel: method)
    events.setStreamHandler(instance)
  }

  public func onListen(withArguments _: Any?, eventSink sink: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = sink
    return nil
  }

  public func onCancel(withArguments _: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Method dispatch

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      result(availabilityPayload())

    case "sheet.present":
      presentSheet(call.arguments as? [String: Any] ?? [:], result: result)

    case "creator.start":
      startCreation(call.arguments as? [String: Any] ?? [:], result: result)

    case "creator.cancel":
      let id = (call.arguments as? [String: Any])?["id"] as? Int ?? -1
      running.removeValue(forKey: id)?.cancel()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Availability

  /// Three separate questions, because a caller needs to tell them apart: is
  /// the OS new enough, can this device generate at all, and can it stream
  /// without the sheet.
  private func availabilityPayload() -> [String: Any] {
    #if canImport(ImagePlayground)
      if #available(iOS 18.1, macOS 15.1, *) {
        var payload: [String: Any] = [
          "sheet": ImagePlaygroundViewController.isAvailable,
          "creator": false,
          "status": ImagePlaygroundViewController.isAvailable ? "available" : "unavailable",
        ]
        if #available(iOS 18.4, macOS 15.4, *) {
          payload["creator"] = ImagePlaygroundViewController.isAvailable
        }
        return payload
      }
      return ["sheet": false, "creator": false, "status": "osTooOld"]
    #else
      return ["sheet": false, "creator": false, "status": "osTooOld"]
    #endif
  }

  // MARK: - The Image Playground sheet

  private func presentSheet(_ args: [String: Any], result: @escaping FlutterResult) {
    #if canImport(ImagePlayground)
      guard #available(iOS 18.1, macOS 15.1, *) else {
        return result(Self.error("osTooOld", "Image Playground needs iOS 18.1 or macOS 15.1."))
      }
      guard ImagePlaygroundViewController.isAvailable else {
        return result(
          Self.error("unavailable", "Image Playground is not available on this device."))
      }
      DispatchQueue.main.async {
        guard let host = Self.hostViewController() else {
          return result(Self.error("noHost", "No view controller to present from."))
        }
        let controller = ImagePlaygroundViewController()
        controller.concepts = Self.concepts(from: args["concepts"] as? [[String: Any]] ?? [])
        // The sheet itself is 18.1, but styles only exist from 18.4, so a
        // device can offer generation and refuse to be told how it should look.
        if #available(iOS 18.4, macOS 15.4, *) {
          if let styles = args["allowedStyles"] as? [String], !styles.isEmpty {
            controller.allowedGenerationStyles = styles.compactMap(Self.style(named:))
          }
          if let name = args["style"] as? String, let s = Self.style(named: name) {
            controller.selectedGenerationStyle = s
          }
        }
        #if os(iOS)
          if let path = args["sourceImagePath"] as? String,
            let image = UIImage(contentsOfFile: path)
          {
            controller.sourceImage = image
          }
        #endif
        let proxy = SheetProxy(result: result)
        controller.delegate = proxy
        proxy.retain(on: controller)
        // UIKit presents modally; AppKit presents as a sheet.
        #if os(iOS)
          host.present(controller, animated: true)
        #else
          host.presentAsSheet(controller)
        #endif
      }
    #else
      result(Self.error("osTooOld", "This build has no ImagePlayground SDK."))
    #endif
  }

  // MARK: - Streaming generation, no UI

  private func startCreation(_ args: [String: Any], result: @escaping FlutterResult) {
    #if canImport(ImagePlayground)
      guard #available(iOS 18.4, macOS 15.4, *) else {
        return result(
          Self.error("osTooOld", "Programmatic generation needs iOS 18.4 or macOS 15.4."))
      }
      let id = args["id"] as? Int ?? 0
      let limit = args["limit"] as? Int ?? 1
      let concepts = Self.concepts(from: args["concepts"] as? [[String: Any]] ?? [])
      let style = Self.style(named: args["style"] as? String ?? "automatic")
        ?? ImagePlaygroundStyle.animation

      guard !concepts.isEmpty else {
        return result(Self.error("noConcepts", "At least one concept is required."))
      }

      running[id] = Task { [weak self] in
        do {
          let creator = try await ImageCreator()
          var index = 0
          for try await created in creator.images(for: concepts, style: style, limit: limit) {
            if Task.isCancelled { break }
            guard let data = Self.png(from: created.cgImage) else { continue }
            self?.emit(["id": id, "type": "image", "index": index, "bytes": FlutterStandardTypedData(bytes: data)])
            index += 1
          }
          if !Task.isCancelled {
            self?.emit(["id": id, "type": "done", "count": index])
          }
        } catch {
          self?.emit(["id": id, "type": "error", "code": Self.code(for: error),
                      "message": error.localizedDescription])
        }
        self?.running.removeValue(forKey: id)
      }
      result(nil)
    #else
      result(Self.error("osTooOld", "This build has no ImagePlayground SDK."))
    #endif
  }

  private func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.eventSink?(payload) }
  }

  // MARK: - Translation helpers

  #if canImport(ImagePlayground)
    @available(iOS 18.1, macOS 15.1, *)
    private static func concepts(from raw: [[String: Any]]) -> [ImagePlaygroundConcept] {
      raw.compactMap { item in
        guard let text = item["text"] as? String else { return nil }
        // `extracted` asks the system to pull concepts out of longer prose,
        // which is a different request from naming a concept outright.
        if (item["extract"] as? Bool) == true {
          return ImagePlaygroundConcept.extracted(from: text, title: item["title"] as? String)
        }
        return ImagePlaygroundConcept.text(text)
      }
    }

    @available(iOS 18.4, macOS 15.4, *)
    private static func style(named name: String) -> ImagePlaygroundStyle? {
      switch name {
      case "animation": return .animation
      case "illustration": return .illustration
      case "sketch": return .sketch
      default: return nil
      }
    }

    /// Maps Apple's error cases onto stable strings so Dart can raise a typed
    /// exception rather than matching on a localized message.
    @available(iOS 18.4, macOS 15.4, *)
    private static func code(for error: Error) -> String {
      guard let e = error as? ImageCreator.Error else { return "creationFailed" }
      switch e {
      case .notSupported: return "notSupported"
      case .unavailable: return "unavailable"
      case .creationCancelled: return "cancelled"
      case .faceInImageTooSmall: return "faceTooSmall"
      case .unsupportedLanguage: return "unsupportedLanguage"
      case .unsupportedInputImage: return "unsupportedInputImage"
      case .backgroundCreationForbidden: return "backgroundForbidden"
      case .conceptsRequirePersonIdentity: return "conceptsRequirePersonIdentity"
      default: return "creationFailed"
      }
    }
  #endif

  private static func png(from image: CGImage) -> Data? {
    let out = NSMutableData()
    let type: CFString
    #if canImport(UniformTypeIdentifiers)
      if #available(iOS 14.0, macOS 11.0, *) {
        type = UTType.png.identifier as CFString
      } else {
        type = "public.png" as CFString
      }
    #else
      type = "public.png" as CFString
    #endif
    guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
  }

  private static func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  #if os(iOS)
    private static func hostViewController() -> UIViewController? {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
      var top = window?.rootViewController
      while let presented = top?.presentedViewController { top = presented }
      return top
    }
  #elseif os(macOS)
    private static func hostViewController() -> NSViewController? {
      NSApplication.shared.keyWindow?.contentViewController
        ?? NSApplication.shared.windows.first?.contentViewController
    }
  #endif
}

#if canImport(ImagePlayground)
  /// Holds the one-shot result and keeps itself alive until the sheet answers.
  @available(iOS 18.1, macOS 15.1, *)
  final class SheetProxy: NSObject, ImagePlaygroundViewController.Delegate {
    private var result: FlutterResult?
    private var anchor: NSObject?

    init(result: @escaping FlutterResult) {
      self.result = result
    }

    /// The controller only holds its delegate weakly, so pin this to it.
    func retain(on controller: NSObject) {
      anchor = self
      objc_setAssociatedObject(
        controller, Unmanaged.passUnretained(self).toOpaque(), self,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func finish(_ value: Any?) {
      let pending = result
      result = nil
      anchor = nil
      pending?(value)
    }

    func imagePlaygroundViewController(
      _ controller: ImagePlaygroundViewController, didCreateImageAt imageURL: URL
    ) {
      Self.dismiss(controller)
      finish(imageURL.path)
    }

    func imagePlaygroundViewControllerDidCancel(_ controller: ImagePlaygroundViewController) {
      Self.dismiss(controller)
      finish(nil)
    }

    private static func dismiss(_ controller: ImagePlaygroundViewController) {
      #if os(iOS)
        controller.dismiss(animated: true)
      #else
        controller.dismiss(nil)
      #endif
    }
  }
#endif
