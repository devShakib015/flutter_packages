import 'package:flutter/foundation.dart';

/// How the model picks each next token.
@immutable
sealed class SamplingMode {
  const SamplingMode();

  /// Always take the most likely token.
  ///
  /// Deterministic for a given prompt, which makes it the right choice for
  /// extraction, classification, and anything you want to test.
  const factory SamplingMode.greedy() = GreedySampling;

  /// Sample from the [k] most likely tokens.
  const factory SamplingMode.topK(int k, {int? seed}) = TopKSampling;

  /// Sample from the smallest set of tokens whose probabilities sum to
  /// [threshold]. Also known as nucleus or top-p sampling.
  const factory SamplingMode.topP(double threshold, {int? seed}) = TopPSampling;

  /// Wire representation.
  Map<String, Object?> toJson();
}

/// Deterministic sampling. See [SamplingMode.greedy].
@immutable
final class GreedySampling extends SamplingMode {
  /// Creates greedy sampling.
  const GreedySampling();

  @override
  Map<String, Object?> toJson() => const <String, Object?>{'mode': 'greedy'};
}

/// Top-k sampling. See [SamplingMode.topK].
@immutable
final class TopKSampling extends SamplingMode {
  /// Creates top-k sampling over [k] candidates.
  const TopKSampling(this.k, {this.seed});

  /// How many candidate tokens to sample from.
  final int k;

  /// Fixes the random draw, making output reproducible.
  final int? seed;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': 'topK',
    'k': k,
    if (seed != null) 'seed': seed,
  };
}

/// Nucleus sampling. See [SamplingMode.topP].
@immutable
final class TopPSampling extends SamplingMode {
  /// Creates nucleus sampling at [threshold].
  const TopPSampling(this.threshold, {this.seed});

  /// Cumulative probability cutoff, 0.0 to 1.0.
  final double threshold;

  /// Fixes the random draw, making output reproducible.
  final int? seed;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': 'topP',
    'threshold': threshold,
    if (seed != null) 'seed': seed,
  };
}

/// Per-request generation settings.
///
/// ```dart
/// // Reproducible extraction.
/// const GenerationOptions(sampling: SamplingMode.greedy(), temperature: 0);
///
/// // Looser, for drafting prose.
/// const GenerationOptions(temperature: 1.2, maximumResponseTokens: 400);
/// ```
@immutable
class GenerationOptions {
  /// Creates options. Every field falls back to the model's own default.
  const GenerationOptions({
    this.sampling,
    this.temperature,
    this.maximumResponseTokens,
  }) : assert(
         temperature == null || temperature >= 0,
         'temperature must not be negative',
       ),
       assert(
         maximumResponseTokens == null || maximumResponseTokens > 0,
         'maximumResponseTokens must be positive',
       );

  /// Deterministic settings, for extraction and classification.
  static const GenerationOptions deterministic = GenerationOptions(
    sampling: SamplingMode.greedy(),
    temperature: 0,
  );

  /// How the next token is chosen.
  final SamplingMode? sampling;

  /// Higher values loosen the output. Zero is effectively deterministic.
  final double? temperature;

  /// Caps the response length. The request fails rather than truncating
  /// silently if the model needs more room than the context window allows.
  final int? maximumResponseTokens;

  /// Wire representation.
  Map<String, Object?> toJson() => <String, Object?>{
    if (sampling != null) 'sampling': sampling!.toJson(),
    if (temperature != null) 'temperature': temperature,
    if (maximumResponseTokens != null)
      'maximumResponseTokens': maximumResponseTokens,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenerationOptions &&
          other.sampling == sampling &&
          other.temperature == temperature &&
          other.maximumResponseTokens == maximumResponseTokens;

  @override
  int get hashCode => Object.hash(sampling, temperature, maximumResponseTokens);
}
