import 'dart:async';

import 'package:flutter/services.dart';

import 'availability.dart';
import 'exceptions.dart';
import 'tool.dart';

/// Platform plumbing. Internal to the package.
///
/// Everything crossing the channel funnels through here so that error mapping
/// and tool dispatch exist in exactly one place.
///
/// Not annotated `@internal`: this lives under `lib/src/` and the barrel never
/// exports it, so it is already unreachable. The annotation only bought a
/// dependency on `package:meta`, whose constraint then blocked resolution on
/// older SDKs.
abstract final class Bridge {
  static const MethodChannel _method = MethodChannel(
    'dev.shakib/apple_foundation_models',
  );
  static const EventChannel _eventChannel = EventChannel(
    'dev.shakib/apple_foundation_models/events',
  );

  static Stream<Map<Object?, Object?>>? _events;
  static final Map<int, Map<String, LanguageModelTool>> _tools =
      <int, Map<String, LanguageModelTool>>{};
  static bool _handlerInstalled = false;
  static int _requestSequence = 0;

  /// A fresh id for correlating a streaming request with its events.
  static int nextRequestId() => ++_requestSequence;

  /// The multiplexed event stream carrying every in-flight generation.
  static Stream<Map<Object?, Object?>> get events => _events ??= _eventChannel
      .receiveBroadcastStream()
      .map((Object? e) => (e as Map<Object?, Object?>?) ?? const {})
      .asBroadcastStream();

  /// Associates a session's tools so the model can call back into Dart.
  static void registerTools(int sessionId, Map<String, LanguageModelTool> t) {
    if (t.isNotEmpty) _tools[sessionId] = t;
    _installHandler();
  }

  /// Forgets a disposed session's tools.
  static void unregisterTools(int sessionId) => _tools.remove(sessionId);

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _method.setMethodCallHandler(_onNativeCall);
  }

  /// Handles the model calling back into Dart mid-generation.
  static Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method != 'tool.call') return null;

    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ?? const {};
    final int sessionId = (args['sessionId'] as num?)?.toInt() ?? -1;
    final String name = args['name'] as String? ?? '';
    final LanguageModelTool? tool = _tools[sessionId]?[name];

    if (tool == null) {
      throw PlatformException(
        code: 'toolMissing',
        message: 'No tool named "$name" is registered on this session.',
      );
    }

    try {
      final Map<String, Object?> parsed = <String, Object?>{
        for (final MapEntry<Object?, Object?> e
            in ((args['arguments'] as Map<Object?, Object?>?) ?? const {})
                .entries)
          e.key.toString(): e.value,
      };
      return await tool.handler(parsed);
    } catch (error) {
      // Surfaced natively as a tool failure so the model is told, rather than
      // silently returning nothing and letting it hallucinate a result.
      throw PlatformException(
        code: 'toolThrew',
        message: '$error',
        details: <String, Object?>{'tool': name},
      );
    }
  }

  /// Invokes a platform method, translating failures into typed exceptions.
  static Future<T> invoke<T>(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      final T? result = await _method.invokeMethod<T>(method, args);
      return result as T;
    } on PlatformException catch (e) {
      throw translate(e.code, e.message, e.details);
    } on MissingPluginException {
      // Android, web, or a build without the plugin: report it the same way
      // an ineligible device does, so callers need one code path.
      throw ModelUnavailableException(
        ModelUnavailableReason.unsupportedPlatform,
      );
    }
  }

  /// Maps a platform error code onto the matching typed exception.
  static FoundationModelsException translate(
    String code,
    String? message,
    Object? details,
  ) {
    final String text = message ?? code;
    return switch (code) {
      'unavailable' => ModelUnavailableException(reasonFrom(details)),
      'exceededContextWindowSize' => ContextWindowExceededException(text),
      'guardrailViolation' => GuardrailViolationException(text),
      'refusal' => RefusalException(text),
      'unsupportedLanguageOrLocale' => UnsupportedLanguageException(text),
      'decodingFailure' => DecodingFailureException(text),
      'assetsUnavailable' => AssetsUnavailableException(text),
      'rateLimited' => RateLimitedException(text),
      'concurrentRequests' => ConcurrentRequestException(text),
      'unsupportedGuide' || 'schema' => SchemaException(text),
      'toolThrew' => ToolCallException(
          (details is Map && details['tool'] is String)
              ? details['tool']! as String
              : 'unknown',
          text,
        ),
      _ => FoundationModelsPlatformException(text, code: code),
    };
  }

  /// Reads an unavailability reason off the wire.
  static ModelUnavailableReason reasonFrom(Object? details) {
    final String? raw = switch (details) {
      final String s => s,
      final Map<Object?, Object?> m => m['reason'] as String?,
      _ => null,
    };
    return ModelUnavailableReason.values.firstWhere(
      (ModelUnavailableReason r) => r.name == raw,
      orElse: () => ModelUnavailableReason.unknown,
    );
  }

  /// Casts a wire map to a Dart map with string keys.
  static Map<String, Object?> asStringMap(Object? value) => <String, Object?>{
        for (final MapEntry<Object?, Object?> e
            in ((value as Map<Object?, Object?>?) ?? const {}).entries)
          e.key.toString(): e.value,
      };
}
