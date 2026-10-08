/// What the on-device model behind a `ModelUseCase` says about itself.
///
/// Every field is null where the platform can't say, which is not the same as
/// "no": [name] and [capabilities] need iOS 27 or macOS 27 and an app built
/// with Xcode 27; [contextSize] needs an app built with Xcode 27, and works on
/// iOS 26 and macOS 26 as well.
final class ModelInfo {
  /// What a platform reported. Usually read with `AppleFoundationModels.modelInfo`.
  const ModelInfo({this.name, this.capabilities, this.contextSize});

  /// Reads the map the platform sends.
  factory ModelInfo.fromJson(Map<String, Object?> json) {
    final Object? caps = json['capabilities'];
    return ModelInfo(
      name: json['name'] as String?,
      capabilities: caps is List
          ? <ModelCapability>{
              for (final Object? c in caps)
                for (final ModelCapability known in ModelCapability.values)
                  if (known.name == c) known,
            }
          : null,
      contextSize: (json['contextSize'] as num?)?.toInt(),
    );
  }

  /// The model's own name, such as "AFM 3 Core".
  final String? name;

  /// What the model can do. Null means unknown, not none.
  final Set<ModelCapability>? capabilities;

  /// How many tokens one session can hold: instructions, the conversation so
  /// far and the response together. Past it, a request throws
  /// `ContextWindowExceededException`.
  final int? contextSize;

  /// Whether the model reports [capability]. False when that's unknown.
  bool can(ModelCapability capability) =>
      capabilities?.contains(capability) ?? false;

  @override
  bool operator ==(Object other) =>
      other is ModelInfo &&
      other.name == name &&
      other.contextSize == contextSize &&
      _sameSet(other.capabilities, capabilities);

  @override
  int get hashCode => Object.hash(
        name,
        contextSize,
        capabilities == null ? null : Object.hashAllUnordered(capabilities!),
      );

  @override
  String toString() =>
      'ModelInfo(name: $name, capabilities: ${capabilities?.map((ModelCapability c) => c.name).join(', ')}, '
      'contextSize: $contextSize)';

  static bool _sameSet(Set<ModelCapability>? a, Set<ModelCapability>? b) =>
      a == null
          ? b == null
          : b != null && a.length == b.length && a.containsAll(b);
}

/// Something a model can do, as the platform reports it.
enum ModelCapability {
  /// Takes images in a prompt.
  vision,

  /// Works through a problem separately before answering.
  reasoning,

  /// Calls the tools a session registers.
  toolCalling,

  /// Fills a schema for structured output.
  guidedGeneration,
}

/// Tokens a session has used.
///
/// `LanguageModelSession.usage` reports the running total. For a single
/// request, subtract the reading before it from the one after:
///
/// ```dart
/// final TokenUsage? before = await session.usage();
/// await session.respond('Summarise this: $article');
/// final TokenUsage? after = await session.usage();
/// if (before != null && after != null) print((after - before).totalTokens);
/// ```
final class TokenUsage {
  /// Counts as a platform reported them, or as made for a test.
  const TokenUsage({
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.outputTokens,
    required this.reasoningTokens,
  });

  /// Reads the map the platform sends.
  factory TokenUsage.fromJson(Map<String, Object?> json) => TokenUsage(
        inputTokens: (json['input'] as num?)?.toInt() ?? 0,
        cachedInputTokens: (json['cachedInput'] as num?)?.toInt() ?? 0,
        outputTokens: (json['output'] as num?)?.toInt() ?? 0,
        reasoningTokens: (json['reasoning'] as num?)?.toInt() ?? 0,
      );

  /// Tokens sent to the model: instructions, prompts, the conversation so far.
  final int inputTokens;

  /// How many of [inputTokens] the model served from its cache.
  final int cachedInputTokens;

  /// Tokens the model generated.
  final int outputTokens;

  /// Tokens the model spent reasoning. Zero for a model without
  /// [ModelCapability.reasoning].
  final int reasoningTokens;

  /// Input plus output.
  int get totalTokens => inputTokens + outputTokens;

  /// The tokens used between two readings of the same session.
  TokenUsage operator -(TokenUsage earlier) => TokenUsage(
        inputTokens: inputTokens - earlier.inputTokens,
        cachedInputTokens: cachedInputTokens - earlier.cachedInputTokens,
        outputTokens: outputTokens - earlier.outputTokens,
        reasoningTokens: reasoningTokens - earlier.reasoningTokens,
      );

  @override
  bool operator ==(Object other) =>
      other is TokenUsage &&
      other.inputTokens == inputTokens &&
      other.cachedInputTokens == cachedInputTokens &&
      other.outputTokens == outputTokens &&
      other.reasoningTokens == reasoningTokens;

  @override
  int get hashCode => Object.hash(
      inputTokens, cachedInputTokens, outputTokens, reasoningTokens);

  @override
  String toString() =>
      'TokenUsage(input: $inputTokens, cached: $cachedInputTokens, '
      'output: $outputTokens, reasoning: $reasoningTokens)';
}
