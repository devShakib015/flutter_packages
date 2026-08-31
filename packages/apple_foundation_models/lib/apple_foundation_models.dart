/// Run Apple's on-device language model from Flutter.
///
/// Private, offline, and free — nothing leaves the device and there is no API
/// key. Requires iOS 26 or macOS 26 on Apple Intelligence hardware, so always
/// check [AppleFoundationModels.availability] before showing an AI feature.
///
/// ```dart
/// if (!await AppleFoundationModels.isAvailable) return;
///
/// final session = await LanguageModelSession.create(
///   instructions: 'You summarise text in one sentence.',
/// );
/// print(await session.respond(article));
/// await session.dispose();
/// ```
library;

export 'src/availability.dart'
    show
        ModelAvailability,
        ModelAvailable,
        ModelUnavailable,
        ModelUnavailableReason;
export 'src/exceptions.dart'
    show
        AssetsUnavailableException,
        ConcurrentRequestException,
        ContextWindowExceededException,
        DecodingFailureException,
        FoundationModelsException,
        FoundationModelsPlatformException,
        GuardrailViolationException,
        ModelUnavailableException,
        RateLimitedException,
        RefusalException,
        SchemaException,
        ToolCallException,
        UnsupportedLanguageException;
export 'src/generation_options.dart'
    show
        GenerationOptions,
        GreedySampling,
        SamplingMode,
        TopKSampling,
        TopPSampling;
export 'src/schema.dart' show Schema;
export 'src/session.dart' show AppleFoundationModels, LanguageModelSession;
export 'src/stream_extensions.dart' show LoadingStreamDeltas;
export 'src/tool.dart' show LanguageModelTool, ToolHandler;
export 'src/transcript.dart' show TranscriptEntry, TranscriptRole;
export 'src/use_case.dart' show ModelUseCase;
