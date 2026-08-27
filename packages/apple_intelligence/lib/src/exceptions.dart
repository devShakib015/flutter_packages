/// Base class for everything this package throws.
sealed class AppleIntelligenceException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const AppleIntelligenceException(this.message);

  /// What went wrong, as reported by the system.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The system predates the API, or the app was built without the SDK.
class OsTooOldException extends AppleIntelligenceException {
  /// Creates the exception.
  const OsTooOldException(super.message);
}

/// Apple Intelligence is off, unsupported on this device, or not yet ready.
class GenerationUnavailableException extends AppleIntelligenceException {
  /// Creates the exception.
  const GenerationUnavailableException(super.message);
}

/// The request itself was refused — the prompt, the language, or the source
/// image was something the system will not draw.
class GenerationRefusedException extends AppleIntelligenceException {
  /// Creates the exception.
  const GenerationRefusedException(super.message, this.reason);

  /// Which refusal this was.
  final GenerationRefusal reason;

  @override
  String toString() => 'GenerationRefusedException($reason): $message';
}

/// The specific reason a request was refused.
enum GenerationRefusal {
  /// The language of the prompt is not supported.
  unsupportedLanguage,

  /// The supplied source image cannot be used.
  unsupportedInputImage,

  /// A face in the source image is too small to work from.
  faceTooSmall,

  /// The concepts name a person the system cannot identify.
  conceptsRequirePersonIdentity,

  /// Generation is not allowed while the app is backgrounded.
  backgroundForbidden,
}

/// Generation started but did not finish.
class GenerationFailedException extends AppleIntelligenceException {
  /// Creates the exception.
  const GenerationFailedException(super.message);
}

/// Maps a platform error code onto the matching exception.
AppleIntelligenceException exceptionFor(String code, String message) =>
    switch (code) {
      'osTooOld' => OsTooOldException(message),
      'notSupported' ||
      'unavailable' => GenerationUnavailableException(message),
      'unsupportedLanguage' => GenerationRefusedException(
        message,
        GenerationRefusal.unsupportedLanguage,
      ),
      'unsupportedInputImage' => GenerationRefusedException(
        message,
        GenerationRefusal.unsupportedInputImage,
      ),
      'faceTooSmall' => GenerationRefusedException(
        message,
        GenerationRefusal.faceTooSmall,
      ),
      'conceptsRequirePersonIdentity' => GenerationRefusedException(
        message,
        GenerationRefusal.conceptsRequirePersonIdentity,
      ),
      'backgroundForbidden' => GenerationRefusedException(
        message,
        GenerationRefusal.backgroundForbidden,
      ),
      _ => GenerationFailedException(message),
    };
