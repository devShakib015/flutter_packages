import Foundation
@preconcurrency import Flutter
import UIKit

#if canImport(RoomPlan)
  import RoomPlan
#endif

final class RoomScanViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier id: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    RoomScanView(frame: frame, id: id, args: args as? [String: Any] ?? [:],
                 messenger: messenger)
  }
}

/// Hosts Apple's own scanning UI.
///
/// RoomPlan ships `RoomCaptureView`, which draws the live coaching overlay and
/// the wireframe as the room is discovered. Reimplementing that in Flutter
/// would mean redrawing an interface Apple already tuned, so this hosts theirs
/// and passes the result back as data.
final class RoomScanView: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let container = UIView()
  private var isRunning = false

  #if canImport(RoomPlan)
    @available(iOS 16.0, *)
    private var captureView: RoomCaptureView? {
      container.subviews.first as? RoomCaptureView
    }
  #endif

  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "dev.shakib/roomplan/scan/\(id)", binaryMessenger: messenger)
    super.init()
    container.frame = frame
    container.backgroundColor = .black
    install()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  func view() -> UIView { container }

  private func install() {
    #if canImport(RoomPlan)
      if #available(iOS 16.0, *), RoomCaptureSession.isSupported {
        let capture = RoomCaptureView(frame: container.bounds)
        capture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        capture.delegate = self
        container.addSubview(capture)
      }
    #endif
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    #if canImport(RoomPlan)
      guard #available(iOS 16.0, *), let capture = captureView else {
        return result(
          FlutterError(code: "unsupported",
                       message: "RoomPlan needs iOS 16 and a LiDAR device.",
                       details: nil))
      }
      switch call.method {
      case "start":
        guard !isRunning else { return result(nil) }
        isRunning = true
        capture.captureSession.run(configuration: RoomCaptureSession.Configuration())
        result(nil)
      case "stop":
        guard isRunning else { return result(nil) }
        isRunning = false
        // The delegate delivers the finished room; stopping only asks for it.
        capture.captureSession.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    #else
      result(FlutterError(code: "unsupported",
                          message: "This build has no RoomPlan SDK.", details: nil))
    #endif
  }

  // RoomCaptureViewDelegate inherits NSCoding, which is an odd thing to ask of
  // a delegate. Nothing here is ever archived, so these satisfy the protocol
  // and do nothing.
  func encode(with coder: NSCoder) {}

  required init?(coder: NSCoder) { nil }

  fileprivate func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("event", arguments: payload)
    }
  }
}

#if canImport(RoomPlan)
  @available(iOS 16.0, *)
  extension RoomScanView: RoomCaptureViewDelegate {
    /// Returning true lets RoomPlan run its own post-processing pass, which is
    /// what turns a raw scan into squared-off walls with real dimensions.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool {
      // RoomPlan ends the session itself when the user finishes, or when it
      // gives up. Nothing cleared isRunning on that path, so the next Start
      // hit `guard !isRunning` and returned success without starting
      // anything — the preview just sat there.
      isRunning = false
      if let error {
        emit(["type": "error", "message": error.localizedDescription])
        return false
      }
      return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
      isRunning = false
      if let error {
        emit(["type": "error", "message": error.localizedDescription])
        return
      }
      var payload: [String: Any] = ["type": "room"]
      // CapturedRoom is Codable, so the whole parametric model crosses as JSON
      // rather than being hand-marshalled surface by surface.
      if let data = try? JSONEncoder().encode(processedResult),
        let json = String(data: data, encoding: .utf8)
      {
        payload["json"] = json
      }
      if let url = Self.exportUSDZ(processedResult) {
        payload["usdz"] = url.path
      }
      emit(payload)
    }

    @available(iOS 16.0, *)
    static func exportUSDZ(_ room: CapturedRoom) -> URL? {
      let dir = FileManager.default.temporaryDirectory
      let url = dir.appendingPathComponent("room-\(UUID().uuidString).usdz")
      do {
        try room.export(to: url, exportOptions: .mesh)
        return url
      } catch {
        return nil
      }
    }
  }
#endif
