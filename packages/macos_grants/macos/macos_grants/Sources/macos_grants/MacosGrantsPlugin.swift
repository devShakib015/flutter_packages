import ApplicationServices
import CoreGraphics
import FlutterMacOS
import Foundation
import Security

/// The three questions macOS will answer about this process, and the one it
/// will only answer about the bundle on disk.
public class MacosGrantsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.shakib/macos_grants", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(MacosGrantsPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "signing": signing(result: result)
    case "accessibility": result(AXIsProcessTrusted())
    case "screenRecording": result(Self.screenRecording())
    default: result(FlutterMethodNotImplemented)
    }
  }

  /// Screen Recording became a privacy grant in macOS 10.15. Before that every
  /// app could capture the screen, so on 10.14 the true answer is yes — and
  /// calling the 10.15 API unguarded would stop the plugin compiling there.
  private static func screenRecording() -> Bool {
    if #available(macOS 10.15, *) {
      return CGPreflightScreenCaptureAccess()
    }
    return true
  }

  /// What macOS makes of this bundle: does it still validate, and whose
  /// identity does it carry.
  ///
  /// Uses the Security framework rather than running `/usr/bin/codesign`,
  /// which does ship with macOS: this is a yes-or-no question with a status
  /// code for an answer, and a subprocess would add a fork and text to parse.
  ///
  /// Every failure path answers `valid: true`. A check that could not run must
  /// not tell somebody their working copy is broken.
  private func signing(result: @escaping FlutterResult) {
    // Hashing a bundle is not instant — tens of megabytes of frameworks — and
    // this is called while the UI is deciding what to tell the user.
    DispatchQueue.global(qos: .userInitiated).async {
      var answer: [String: Any] = [
        "valid": true, "identity": "unknown", "teamId": nil as Any? as Any,
      ]

      var staticCode: SecStaticCode?
      let created = SecStaticCodeCreateWithPath(
        Bundle.main.bundleURL as CFURL, SecCSFlags(), &staticCode)
      guard created == errSecSuccess, let code = staticCode else {
        answer["error"] = "could not read the bundle (OSStatus \(created))"
        DispatchQueue.main.async { result(answer) }
        return
      }

      // kSecCSCheckNestedCode is what catches the case this package exists
      // for: a framework rewritten after the app was sealed. A plain check
      // passes such a bundle at the top level.
      let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate)
      let validity = SecStaticCodeCheckValidity(code, flags, nil)
      answer["valid"] = validity == errSecSuccess
      if validity != errSecSuccess {
        answer["error"] = "nested code is modified or invalid (OSStatus \(validity))"
      }

      var infoRef: CFDictionary?
      let signingFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
      if SecCodeCopySigningInformation(code, signingFlags, &infoRef) == errSecSuccess,
        let info = infoRef as? [String: Any]
      {
        answer["teamId"] = info[kSecCodeInfoTeamIdentifier as String] as? String
        answer["identity"] = Self.identity(from: info)
      }

      DispatchQueue.main.async { result(answer) }
    }
  }

  /// Ad-hoc, Developer ID, App Store or unsigned — the distinction TCC cares
  /// about, because an ad-hoc requirement is the hash of the code itself and
  /// so changes with every build.
  private static func identity(from info: [String: Any]) -> String {
    let flags = info[kSecCodeInfoFlags as String] as? UInt32 ?? 0
    // kSecCodeSignatureAdhoc, without importing the constant by name: bit 1.
    if flags & 0x0000_0002 != 0 { return "adHoc" }

    guard let chain = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
      let leaf = chain.first
    else {
      return flags == 0 ? "unsigned" : "unknown"
    }
    let name = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
    if name.hasPrefix("Developer ID Application") { return "developerId" }
    if name.hasPrefix("Apple Mac OS Application Signing")
      || name.hasPrefix("3rd Party Mac Developer Application")
      || name.hasPrefix("Apple Distribution")
    {
      return "appStore"
    }
    if name.hasPrefix("Apple Development") || name.hasPrefix("Mac Developer") {
      // A development certificate: a real identity, but not one a user's
      // machine will trust the way it trusts Developer ID.
      return "developerId"
    }
    return "unknown"
  }
}
