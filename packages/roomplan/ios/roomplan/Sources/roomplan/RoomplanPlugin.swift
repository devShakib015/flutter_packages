import Foundation
@preconcurrency import Flutter
import UIKit

// Guarded so the plugin still compiles on an Xcode without the RoomPlan SDK.
// Those builds report `unsupported` rather than failing to build.
#if canImport(RoomPlan)
  import RoomPlan
#endif

public class RoomplanPlugin: NSObject, FlutterPlugin {
  private var factory: RoomScanViewFactory?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let instance = RoomplanPlugin()
    let channel = FlutterMethodChannel(
      name: "dev.shakib/roomplan", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)

    let factory = RoomScanViewFactory(messenger: messenger)
    instance.factory = factory  // the registrar does not retain it
    registrar.register(factory, withId: "dev.shakib/roomplan/scan")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "support":
      result(Self.support())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Why scanning is or is not possible, told apart rather than lumped into
  /// one boolean — "your phone has no LiDAR" and "your iOS is too old" want
  /// very different things said to the user.
  static func support() -> [String: Any] {
    #if canImport(RoomPlan)
      if #available(iOS 16.0, *) {
        let ok = RoomCaptureSession.isSupported
        return [
          "supported": ok,
          "reason": ok ? "supported" : "noLidar",
        ]
      }
      return ["supported": false, "reason": "osTooOld"]
    #else
      return ["supported": false, "reason": "osTooOld"]
    #endif
  }
}
