import Foundation

// @preconcurrency: Flutter's ObjC types predate Sendable annotations, and
// hopping to the main queue is exactly how they are meant to be used.
#if os(iOS)
  @preconcurrency import Flutter
#elseif os(macOS)
  @preconcurrency import FlutterMacOS
#endif

// Guarded so the plugin still compiles on an Xcode without the iOS 26 SDK.
// Those builds report `osTooOld` rather than failing to build, which keeps the
// package addable to an app that has not moved to Xcode 26 yet.
#if canImport(FoundationModels)
  import FoundationModels
#endif

public class AppleFoundationModelsPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private var methodChannel: FlutterMethodChannel?
  private var eventSink: FlutterEventSink?
  private var sessions: [Int: Any] = [:]
  private var running: [Int: Task<Void, Never>] = [:]
  private var nextSessionId = 0

  // MARK: - Registration

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif

    let instance = AppleFoundationModelsPlugin()
    let method = FlutterMethodChannel(
      name: "dev.shakib/apple_foundation_models", binaryMessenger: messenger)
    let events = FlutterEventChannel(
      name: "dev.shakib/apple_foundation_models/events", binaryMessenger: messenger)

    instance.methodChannel = method
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

  private func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async { self.eventSink?(payload) }
  }

  // MARK: - Dispatch

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    if call.method == "availability" {
      result(availabilityPayload())
      return
    }

    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        handleModern(call.method, args, result)
        return
      }
    #endif
    result(unsupportedError())
  }

  private func availabilityPayload() -> [String: Any] {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
          return ["available": true]
        case .unavailable(let reason):
          return ["available": false, "reason": name(for: reason)]
        @unknown default:
          return ["available": false, "reason": "unknown"]
        }
      }
    #endif
    return ["available": false, "reason": "osTooOld"]
  }

  #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func name(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
      switch reason {
      case .deviceNotEligible: return "deviceNotEligible"
      case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled"
      case .modelNotReady: return "modelNotReady"
      @unknown default: return "unknown"
      }
    }
  #endif

  private func unsupportedError() -> FlutterError {
    FlutterError(
      code: "unavailable",
      message: "Foundation Models needs iOS 26 or macOS 26.",
      details: ["reason": "osTooOld"])
  }

  // MARK: - Modern path

  #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func handleModern(
      _ method: String, _ args: [String: Any], _ result: @escaping FlutterResult
    ) {
      switch method {
      case "session.create":
        createSession(args, result)

      case "session.respond":
        withSession(args, result) { session in
          let response = try await session.respond(
            to: args["prompt"] as? String ?? "",
            options: self.options(from: args["options"]))
          return response.content
        }

      case "session.respondAs":
        withSession(args, result) { session in
          let schema = try self.schema(from: args["schema"])
          let response = try await session.respond(
            to: args["prompt"] as? String ?? "",
            schema: schema,
            includeSchemaInPrompt: args["includeSchemaInPrompt"] as? Bool ?? true,
            options: self.options(from: args["options"]))
          return response.content.jsonString
        }

      case "session.stream":
        startStream(args, result, structured: false)

      case "session.streamAs":
        startStream(args, result, structured: true)

      case "session.prewarm":
        guard let session = session(args) else { return result(missingSession()) }
        session.prewarm()
        result(nil)

      case "session.isResponding":
        guard let session = session(args) else { return result(missingSession()) }
        result(session.isResponding)

      case "session.transcript":
        guard let session = session(args) else { return result(missingSession()) }
        result(transcript(of: session))

      case "session.cancel":
        if let id = args["requestId"] as? Int {
          running.removeValue(forKey: id)?.cancel()
        }
        result(nil)

      case "session.dispose":
        if let id = args["sessionId"] as? Int { sessions.removeValue(forKey: id) }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func createSession(_ args: [String: Any], _ result: @escaping FlutterResult) {
      nextSessionId += 1
      let id = nextSessionId
      do {
        var tools: [any Tool] = []
        for raw in args["tools"] as? [[String: Any]] ?? [] {
          guard let name = raw["name"] as? String else { continue }
          tools.append(
            DartTool(
              name: name,
              description: raw["description"] as? String ?? "",
              parameters: try schema(from: raw["parameters"]),
              sessionId: id,
              plugin: self))
        }

        let instructions = args["instructions"] as? String
        let session: LanguageModelSession =
          instructions.map { LanguageModelSession(tools: tools, instructions: $0) }
          ?? LanguageModelSession(tools: tools)

        sessions[id] = session
        result(id)
      } catch {
        result(flutterError(error))
      }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func session(_ args: [String: Any]) -> LanguageModelSession? {
      guard let id = args["sessionId"] as? Int else { return nil }
      return sessions[id] as? LanguageModelSession
    }

    private func missingSession() -> FlutterError {
      FlutterError(
        code: "sessionMissing", message: "That session has been disposed.", details: nil)
    }

    /// Runs async work against a session and replies once, mapping any throw.
    @available(iOS 26.0, macOS 26.0, *)
    private func withSession(
      _ args: [String: Any],
      _ result: @escaping FlutterResult,
      _ body: @escaping (LanguageModelSession) async throws -> Any?
    ) {
      guard let session = session(args) else { return result(missingSession()) }
      Task {
        do {
          let value = try await body(session)
          DispatchQueue.main.async { result(value) }
        } catch {
          let payload = self.errorPayload(error)
          DispatchQueue.main.async { result(payload.flutterError) }
        }
      }
    }

    /// Streams snapshots over the event channel. Each event carries the whole
    /// response so far, matching the framework rather than inventing deltas.
    @available(iOS 26.0, macOS 26.0, *)
    private func startStream(
      _ args: [String: Any], _ result: @escaping FlutterResult, structured: Bool
    ) {
      guard let session = session(args) else { return result(missingSession()) }
      guard let requestId = args["requestId"] as? Int else {
        return result(
          FlutterError(code: "badRequest", message: "requestId is required", details: nil))
      }

      let prompt = args["prompt"] as? String ?? ""
      let options = self.options(from: args["options"])
      let includeSchema = args["includeSchemaInPrompt"] as? Bool ?? true
      var generationSchema: GenerationSchema?
      if structured {
        do { generationSchema = try schema(from: args["schema"]) } catch {
          return result(flutterError(error))
        }
      }

      // Acknowledge before the first token so Dart knows the request started.
      result(nil)

      running[requestId] = Task { [weak self] in
        guard let self else { return }
        do {
          if let generationSchema {
            let stream = session.streamResponse(
              to: prompt, schema: generationSchema,
              includeSchemaInPrompt: includeSchema, options: options)
            for try await snapshot in stream {
              try Task.checkCancellation()
              self.emit([
                "requestId": requestId, "type": "delta",
                "text": snapshot.rawContent.jsonString,
              ])
            }
          } else {
            let stream = session.streamResponse(to: prompt, options: options)
            for try await snapshot in stream {
              try Task.checkCancellation()
              self.emit(["requestId": requestId, "type": "delta", "text": snapshot.content])
            }
          }
          self.emit(["requestId": requestId, "type": "done"])
        } catch is CancellationError {
          // The listener went away; nothing to report.
        } catch {
          let payload = self.errorPayload(error)
          self.emit([
            "requestId": requestId, "type": "error",
            "code": payload.code, "message": payload.message,
            "details": payload.details ?? [:],
          ])
        }
        self.running.removeValue(forKey: requestId)
      }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func transcript(of session: LanguageModelSession) -> [[String: String]] {
      session.transcript.map { entry in
        switch entry {
        case .instructions(let value):
          return ["role": "instructions", "text": Self.text(of: value.segments)]
        case .prompt(let value):
          return ["role": "prompt", "text": Self.text(of: value.segments)]
        case .response(let value):
          return ["role": "response", "text": Self.text(of: value.segments)]
        case .toolCalls(let calls):
          return ["role": "toolCall", "text": calls.map(\.toolName).joined(separator: ", ")]
        case .toolOutput(let value):
          return ["role": "toolOutput", "text": Self.text(of: value.segments)]
        @unknown default:
          return ["role": "unknown", "text": ""]
        }
      }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func text(of segments: [Transcript.Segment]) -> String {
      segments.map { segment in
        switch segment {
        case .text(let s): return s.content
        case .structure(let s): return s.content.jsonString
        @unknown default: return ""
        }
      }.joined()
    }

    // MARK: - Translation

    @available(iOS 26.0, macOS 26.0, *)
    private func options(from raw: Any?) -> GenerationOptions {
      guard let map = raw as? [String: Any] else { return GenerationOptions() }
      var sampling: GenerationOptions.SamplingMode?
      if let s = map["sampling"] as? [String: Any] {
        let seed = (s["seed"] as? NSNumber)?.uint64Value
        switch s["mode"] as? String {
        case "greedy": sampling = .greedy
        case "topK": sampling = .random(top: s["k"] as? Int ?? 50, seed: seed)
        case "topP":
          sampling = .random(probabilityThreshold: s["threshold"] as? Double ?? 0.9, seed: seed)
        default: sampling = nil
        }
      }
      return GenerationOptions(
        sampling: sampling,
        temperature: map["temperature"] as? Double,
        maximumResponseTokens: map["maximumResponseTokens"] as? Int)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func schema(from raw: Any?) throws -> GenerationSchema {
      guard let map = raw as? [String: Any] else {
        throw SchemaError.invalid("A schema is required.")
      }
      return try GenerationSchema(root: try dynamicSchema(map), dependencies: [])
    }

    /// Rebuilds a Dart-described schema natively.
    ///
    /// This is the whole reason the package can offer typed output: `@Generable`
    /// is a compile-time macro and can never see a type declared in Dart, but
    /// `DynamicGenerationSchema` accepts a shape assembled at runtime.
    @available(iOS 26.0, macOS 26.0, *)
    private func dynamicSchema(_ json: [String: Any]) throws -> DynamicGenerationSchema {
      switch json["type"] as? String ?? "" {
      case "string": return DynamicGenerationSchema(type: String.self)
      case "integer": return DynamicGenerationSchema(type: Int.self)
      case "number": return DynamicGenerationSchema(type: Double.self)
      case "boolean": return DynamicGenerationSchema(type: Bool.self)

      case "enum":
        let values = json["values"] as? [String] ?? []
        guard !values.isEmpty else { throw SchemaError.invalid("An enum needs values.") }
        return DynamicGenerationSchema(
          name: json["name"] as? String ?? "Choice",
          description: json["description"] as? String,
          anyOf: values)

      case "array":
        guard let items = json["items"] as? [String: Any] else {
          throw SchemaError.invalid("An array needs an item schema.")
        }
        return DynamicGenerationSchema(
          arrayOf: try dynamicSchema(items),
          minimumElements: json["minItems"] as? Int,
          maximumElements: json["maxItems"] as? Int)

      case "object":
        var properties: [DynamicGenerationSchema.Property] = []
        for raw in json["properties"] as? [[String: Any]] ?? [] {
          guard let name = raw["name"] as? String,
            let child = raw["schema"] as? [String: Any]
          else { throw SchemaError.invalid("A property needs a name and a schema.") }
          properties.append(
            .init(
              name: name,
              description: child["description"] as? String,
              schema: try dynamicSchema(child),
              isOptional: raw["isOptional"] as? Bool ?? false))
        }
        guard !properties.isEmpty else {
          throw SchemaError.invalid("An object needs at least one property.")
        }
        return DynamicGenerationSchema(
          name: json["name"] as? String ?? "Result",
          description: json["description"] as? String,
          properties: properties)

      default:
        throw SchemaError.invalid("Unknown schema type \(json["type"] ?? "nil").")
      }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func flutterError(_ error: Error) -> FlutterError {
      errorPayload(error).flutterError
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func errorPayload(_ error: Error) -> ErrorPayload {
      if let schemaError = error as? SchemaError {
        return ErrorPayload(code: "schema", message: schemaError.message, details: nil)
      }
      if let toolError = error as? DartToolError {
        return ErrorPayload(
          code: "toolThrew", message: toolError.message, details: ["tool": toolError.tool])
      }
      if let generation = error as? LanguageModelSession.GenerationError {
        let code: String
        switch generation {
        case .exceededContextWindowSize: code = "exceededContextWindowSize"
        case .assetsUnavailable: code = "assetsUnavailable"
        case .guardrailViolation: code = "guardrailViolation"
        case .unsupportedGuide: code = "unsupportedGuide"
        case .unsupportedLanguageOrLocale: code = "unsupportedLanguageOrLocale"
        case .decodingFailure: code = "decodingFailure"
        case .rateLimited: code = "rateLimited"
        case .concurrentRequests: code = "concurrentRequests"
        case .refusal: code = "refusal"
        @unknown default: code = "unknown"
        }
        return ErrorPayload(
          code: code, message: generation.localizedDescription, details: nil)
      }
      return ErrorPayload(code: "unknown", message: "\(error)", details: nil)
    }

    /// Calls back into Dart so the model can reach code it was never trained on.
    @available(iOS 26.0, macOS 26.0, *)
    final class DartTool: Tool, @unchecked Sendable {
      typealias Arguments = GeneratedContent
      typealias Output = String

      let name: String
      let description: String
      let parameters: GenerationSchema
      let includesSchemaInInstructions = true

      private let sessionId: Int
      private weak var plugin: AppleFoundationModelsPlugin?

      init(
        name: String, description: String, parameters: GenerationSchema,
        sessionId: Int, plugin: AppleFoundationModelsPlugin
      ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.sessionId = sessionId
        self.plugin = plugin
      }

      func call(arguments: GeneratedContent) async throws -> String {
        let decoded =
          (try? JSONSerialization.jsonObject(
            with: Data(arguments.jsonString.utf8))) as? [String: Any] ?? [:]

        return try await withCheckedThrowingContinuation { continuation in
          DispatchQueue.main.async { [weak self] in
            guard let self, let channel = self.plugin?.methodChannel else {
              continuation.resume(
                throwing: DartToolError(tool: self?.name ?? "?", message: "Plugin went away."))
              return
            }
            channel.invokeMethod(
              "tool.call",
              arguments: [
                "sessionId": self.sessionId, "name": self.name, "arguments": decoded,
              ]
            ) { response in
              if let error = response as? FlutterError {
                continuation.resume(
                  throwing: DartToolError(
                    tool: self.name, message: error.message ?? "The tool failed."))
              } else if response is NSObject, response as? NSObject == FlutterMethodNotImplemented {
                continuation.resume(
                  throwing: DartToolError(tool: self.name, message: "No Dart handler."))
              } else {
                continuation.resume(returning: response as? String ?? "")
              }
            }
          }
        }
      }
    }
  #endif

  /// Error data in a form that is safe to hand between queues.
  struct ErrorPayload: Sendable {
    let code: String
    let message: String
    let details: [String: String]?

    var flutterError: FlutterError {
      FlutterError(code: code, message: message, details: details)
    }
  }

  struct SchemaError: Error {
    let message: String
    static func invalid(_ message: String) -> SchemaError { SchemaError(message: message) }
  }

  struct DartToolError: Error {
    let tool: String
    let message: String
  }
}
