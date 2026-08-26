import 'dart:async';
import 'dart:convert';

import 'availability.dart';
import 'bridge.dart';
import 'exceptions.dart';
import 'generation_options.dart';
import 'schema.dart';
import 'tool.dart';
import 'transcript.dart';

/// Entry point for the on-device model.
abstract final class AppleFoundationModels {
  /// Whether the model can be used, and if not, why.
  ///
  /// Cheap enough to call on every screen that needs it. Check this before
  /// showing an AI feature at all — on most devices today the honest answer is
  /// no, and a feature that appears then fails is worse than one that never
  /// appeared.
  static Future<ModelAvailability> availability() async {
    try {
      final Map<String, Object?> result = Bridge.asStringMap(
        await Bridge.invoke<Object?>('availability'),
      );
      if (result['available'] == true) return const ModelAvailable();
      return ModelUnavailable(Bridge.reasonFrom(result));
    } on ModelUnavailableException catch (e) {
      return ModelUnavailable(e.reason);
    }
  }

  /// Whether generation can be attempted right now.
  static Future<bool> get isAvailable async =>
      (await availability()).isAvailable;
}

/// A conversation with the on-device model.
///
/// A session owns a transcript, so successive requests share context. It
/// handles one request at a time — overlapping calls raise
/// [ConcurrentRequestException]. Use separate sessions for parallel work.
///
/// ```dart
/// final session = await LanguageModelSession.create(
///   instructions: 'You summarise text in one sentence. Never add opinions.',
/// );
/// final summary = await session.respond(article);
/// await session.dispose();
/// ```
///
/// Sessions hold native resources. Always [dispose].
class LanguageModelSession {
  LanguageModelSession._(this._id, this._toolCount);

  final int _id;
  final int _toolCount;
  bool _disposed = false;

  /// Opens a session.
  ///
  /// [instructions] are standing guidance the model keeps in view for every
  /// request — a role, a format, a prohibition. They are not a prompt, and
  /// they are not user input: never build them out of untrusted text, since
  /// they carry more weight than anything in a prompt.
  ///
  /// Registering [tools] lets the model call back into Dart mid-generation.
  static Future<LanguageModelSession> create({
    String? instructions,
    List<LanguageModelTool> tools = const <LanguageModelTool>[],
  }) async {
    final Set<String> names = <String>{};
    for (final LanguageModelTool tool in tools) {
      if (!names.add(tool.name)) {
        throw ArgumentError.value(
          tool.name,
          'tools',
          'Two tools share this name; the model could not tell them apart',
        );
      }
    }

    final int id = await Bridge.invoke<int>('session.create', <String, Object?>{
      'instructions': instructions,
      'tools': <Map<String, Object?>>[
        for (final LanguageModelTool t in tools) t.toJson(),
      ],
    });

    Bridge.registerTools(id, <String, LanguageModelTool>{
      for (final LanguageModelTool t in tools) t.name: t,
    });
    return LanguageModelSession._(id, tools.length);
  }

  void _assertUsable() {
    if (_disposed) {
      throw StateError('This LanguageModelSession has been disposed.');
    }
  }

  /// Generates a plain text response.
  Future<String> respond(String prompt, {GenerationOptions? options}) {
    _assertUsable();
    return Bridge.invoke<String>('session.respond', <String, Object?>{
      'sessionId': _id,
      'prompt': prompt,
      'options': options?.toJson(),
    });
  }

  /// Generates a response constrained to [schema], decoded to a map.
  ///
  /// The model is structurally prevented from returning a different shape, so
  /// the result can be read without defensive parsing.
  ///
  /// [includeSchemaInPrompt] shows the schema to the model as well as
  /// enforcing it. Leave it on unless the instructions already describe the
  /// shape, where turning it off saves context.
  Future<Map<String, Object?>> respondAs(
    String prompt, {
    required Schema schema,
    GenerationOptions? options,
    bool includeSchemaInPrompt = true,
  }) async {
    _assertUsable();
    final String raw = await Bridge.invoke<String>(
      'session.respondAs',
      <String, Object?>{
        'sessionId': _id,
        'prompt': prompt,
        'schema': schema.toJson(),
        'includeSchemaInPrompt': includeSchemaInPrompt,
        'options': options?.toJson(),
      },
    );
    return _decode(raw);
  }

  /// Streams the response as it is produced.
  ///
  /// **Each event is the whole response so far, not a delta.** That mirrors
  /// the platform, and it is what a UI wants — assign it straight to your
  /// state. Concatenating these events is the one mistake to avoid; it
  /// produces text that repeats itself.
  Stream<String> stream(String prompt, {GenerationOptions? options}) {
    _assertUsable();
    return _run<String>(
      method: 'session.stream',
      arguments: <String, Object?>{
        'prompt': prompt,
        'options': options?.toJson(),
      },
      decode: (Map<Object?, Object?> event) => event['text'] as String? ?? '',
    );
  }

  /// Streams a schema-constrained response as it fills in.
  ///
  /// Early events hold partially populated objects — fields the model has not
  /// reached yet are absent, so read defensively until the stream closes.
  Stream<Map<String, Object?>> streamAs(
    String prompt, {
    required Schema schema,
    GenerationOptions? options,
    bool includeSchemaInPrompt = true,
  }) {
    _assertUsable();
    return _run<Map<String, Object?>>(
      method: 'session.streamAs',
      arguments: <String, Object?>{
        'prompt': prompt,
        'schema': schema.toJson(),
        'includeSchemaInPrompt': includeSchemaInPrompt,
        'options': options?.toJson(),
      },
      decode: (Map<Object?, Object?> event) {
        final String? text = event['text'] as String?;
        if (text == null || text.isEmpty) return <String, Object?>{};
        try {
          return _decode(text);
        } on DecodingFailureException {
          // A partial snapshot is often not yet valid JSON. Skipping it is
          // correct; the next event supersedes it anyway.
          return <String, Object?>{};
        }
      },
    );
  }

  /// Subscribes to the event stream before starting work, so no early event
  /// is missed, and cancels the native request if the listener goes away.
  Stream<T> _run<T>({
    required String method,
    required Map<String, Object?> arguments,
    required T Function(Map<Object?, Object?> event) decode,
  }) {
    final int requestId = Bridge.nextRequestId();
    late StreamController<T> controller;
    StreamSubscription<Map<Object?, Object?>>? subscription;

    Future<void> stop() async {
      await subscription?.cancel();
      subscription = null;
    }

    controller = StreamController<T>(
      onListen: () async {
        subscription = Bridge.events
            .where(
              (Map<Object?, Object?> e) =>
                  (e['requestId'] as num?)?.toInt() == requestId,
            )
            .listen((Map<Object?, Object?> event) async {
              switch (event['type']) {
                case 'delta':
                  if (!controller.isClosed) controller.add(decode(event));
                case 'done':
                  await stop();
                  if (!controller.isClosed) await controller.close();
                case 'error':
                  if (!controller.isClosed) {
                    controller.addError(
                      Bridge.translate(
                        event['code'] as String? ?? 'unknown',
                        event['message'] as String?,
                        event['details'],
                      ),
                    );
                  }
                  await stop();
                  if (!controller.isClosed) await controller.close();
              }
            });

        try {
          await Bridge.invoke<void>(method, <String, Object?>{
            'sessionId': _id,
            'requestId': requestId,
            ...arguments,
          });
        } catch (error, stack) {
          if (!controller.isClosed) controller.addError(error, stack);
          await stop();
          if (!controller.isClosed) await controller.close();
        }
      },
      onCancel: () async {
        await stop();
        // Best effort: the listener has gone, so a failure here changes
        // nothing the caller can observe.
        try {
          await Bridge.invoke<void>('session.cancel', <String, Object?>{
            'sessionId': _id,
            'requestId': requestId,
          });
        } catch (_) {}
      },
    );
    return controller.stream;
  }

  /// Warms the model so the first real request starts sooner.
  ///
  /// Worth calling when you can predict a request is coming — on entering a
  /// screen, say. Pointless immediately before one.
  Future<void> prewarm({String? promptPrefix}) {
    _assertUsable();
    return Bridge.invoke<void>('session.prewarm', <String, Object?>{
      'sessionId': _id,
      'promptPrefix': promptPrefix,
    });
  }

  /// Whether the session is mid-request.
  Future<bool> get isResponding {
    _assertUsable();
    return Bridge.invoke<bool>('session.isResponding', <String, Object?>{
      'sessionId': _id,
    });
  }

  /// The conversation so far, which is also what fills the context window.
  Future<List<TranscriptEntry>> transcript() async {
    _assertUsable();
    final List<Object?> raw = await Bridge.invoke<List<Object?>>(
      'session.transcript',
      <String, Object?>{'sessionId': _id},
    );
    return <TranscriptEntry>[
      for (final Object? entry in raw)
        TranscriptEntry.fromJson(Bridge.asStringMap(entry)),
    ];
  }

  /// How many tools this session exposes.
  int get toolCount => _toolCount;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Releases the native session.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    Bridge.unregisterTools(_id);
    try {
      await Bridge.invoke<void>('session.dispose', <String, Object?>{
        'sessionId': _id,
      });
    } on ModelUnavailableException {
      // Nothing was ever allocated on an unsupported platform.
    }
  }

  static Map<String, Object?> _decode(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return decoded;
      throw DecodingFailureException(
        'Expected a JSON object from the model, got ${decoded.runtimeType}.',
      );
    } on FormatException catch (e) {
      throw DecodingFailureException('Model output was not valid JSON: $e');
    }
  }
}
