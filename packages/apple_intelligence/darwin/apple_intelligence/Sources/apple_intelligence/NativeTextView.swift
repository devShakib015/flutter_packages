import Foundation

#if os(iOS)
  @preconcurrency import Flutter
  import UIKit
  typealias PlatformTextView = UITextView
  typealias PlatformColor = UIColor
  typealias PlatformFont = UIFont
#elseif os(macOS)
  @preconcurrency import FlutterMacOS
  import AppKit
  typealias PlatformTextView = NSTextView
  typealias PlatformColor = NSColor
  typealias PlatformFont = NSFont
#endif

/// A real system text view, hosted inside Flutter.
///
/// Flutter draws its own text, which is why Apple's text affordances never
/// appear in a Flutter `TextField`: Writing Tools attaches to a `UIView` and
/// Genmoji is a property of `UITextInput`, and Flutter's text field is neither
/// as far as UIKit is concerned. Rather than reaching into the engine's private
/// text plumbing — which any Flutter release could rename — this hosts the
/// genuine article and lets the system do what it already knows how to do.
final class NativeTextViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  #if os(iOS)
    func create(withFrame frame: CGRect, viewIdentifier id: Int64, arguments args: Any?)
      -> FlutterPlatformView
    {
      NativeTextView(frame: frame, id: id, args: args as? [String: Any] ?? [:],
                     messenger: messenger)
    }
  #elseif os(macOS)
    func create(withViewIdentifier id: Int64, arguments args: Any?) -> NSView {
      let host = NativeTextView(frame: .zero, id: id, args: args as? [String: Any] ?? [:],
                                messenger: messenger)
      let view = host.nsView()
      // iOS retains the FlutterPlatformView itself; macOS retains only the
      // NSView it is handed. Without this the host deallocates the moment
      // this returns, taking its method-channel handler with it, and every
      // call from Dart then hangs with no error anywhere.
      objc_setAssociatedObject(
        view, Unmanaged.passUnretained(host).toOpaque(), host,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      return view
    }
  #endif
}

final class NativeTextView: NSObject {
  /// Guards against echoing a change Dart itself just made.
  private var applyingFromDart = false

  private let textView = PlatformTextView()
  private let channel: FlutterMethodChannel
  #if os(macOS)
    private let scroll = NSScrollView()
  #endif

  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "dev.shakib/apple_intelligence/text/\(id)", binaryMessenger: messenger)
    super.init()

    configure(args)
    textView.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func configure(_ args: [String: Any]) {
    let size = args["fontSize"] as? Double ?? 16
    #if os(iOS)
      textView.font = PlatformFont.systemFont(ofSize: size)
      textView.text = args["text"] as? String ?? ""
      textView.backgroundColor = .clear
      textView.isEditable = args["readOnly"] as? Bool == true ? false : true
      // Genmoji: the property lives on UITextInput, and without it the
      // keyboard's Genmoji button inserts nothing.
      if #available(iOS 18.0, *) {
        textView.supportsAdaptiveImageGlyph = true
      }
      // Writing Tools is automatic on a real text view from iOS 18.
      if #available(iOS 18.0, *) {
        textView.writingToolsBehavior = .complete
      }
    #elseif os(macOS)
      textView.font = PlatformFont.systemFont(ofSize: size)
      textView.string = args["text"] as? String ?? ""
      textView.isEditable = args["readOnly"] as? Bool == true ? false : true
      textView.isRichText = true
      textView.allowsUndo = true
      textView.drawsBackground = false
      if #available(macOS 15.0, *) {
        textView.writingToolsBehavior = .complete
      }
      scroll.documentView = textView
      scroll.hasVerticalScroller = true
      scroll.drawsBackground = false
      textView.autoresizingMask = [.width]
    #endif
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "getText":
      #if os(iOS)
        result(textView.text ?? "")
      #else
        result(textView.string)
      #endif
    case "setText":
      let value = (call.arguments as? [String: Any])?["text"] as? String ?? ""
      applyingFromDart = true
      #if os(iOS)
        textView.text = value
      #else
        textView.string = value
      #endif
      applyingFromDart = false
      result(nil)
    case "capabilities":
      result(capabilities())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// What this text view actually got from the system, asked of the live view
  /// rather than inferred from the OS version.
  private func capabilities() -> [String: Any] {
    var out: [String: Any] = ["writingTools": false, "genmoji": false]
    #if os(iOS)
      if #available(iOS 18.0, *) {
        out["writingTools"] = textView.writingToolsBehavior != .none
        out["genmoji"] = textView.supportsAdaptiveImageGlyph
      }
    #elseif os(macOS)
      if #available(macOS 15.0, *) {
        out["writingTools"] = textView.writingToolsBehavior != .none
        // AppKit exposes Genmoji through the attributed string, not a flag.
        out["genmoji"] = textView.isRichText
      }
    #endif
    return out
  }

  #if os(macOS)
    func nsView() -> NSView { scroll }
  #endif

  fileprivate func textChanged() {
    guard !applyingFromDart else { return }
    #if os(iOS)
      let value = textView.text ?? ""
    #else
      let value = textView.string
    #endif
    channel.invokeMethod("textChanged", arguments: ["text": value])
  }
}

#if os(iOS)
  extension NativeTextView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) { textChanged() }
  }
#elseif os(macOS)
  extension NativeTextView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) { textChanged() }
  }
#endif

#if os(iOS)
  extension NativeTextView: FlutterPlatformView {
    func view() -> UIView { textView }
  }
#endif
