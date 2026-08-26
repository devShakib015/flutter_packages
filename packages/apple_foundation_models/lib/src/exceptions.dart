import 'package:flutter/foundation.dart';

import 'availability.dart';

/// Base class for every failure this package raises.
///
/// The cases mirror the framework's own `GenerationError`, so a caller can
/// respond to each specifically rather than pattern-matching on message text.
@immutable
sealed class FoundationModelsException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const FoundationModelsException(this.message);

  /// A description of what went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Generation was attempted while the model was unavailable.
final class ModelUnavailableException extends FoundationModelsException {
  /// Creates the exception for [reason].
  ModelUnavailableException(this.reason) : super(reason.explanation);

  /// Why the model could not be used.
  final ModelUnavailableReason reason;
}

/// The prompt plus transcript no longer fit in the context window.
///
/// Recover by starting a fresh session, optionally seeded with a summary of
/// the old transcript — the window does not grow.
final class ContextWindowExceededException extends FoundationModelsException {
  /// Creates the exception.
  const ContextWindowExceededException(super.message);
}

/// The prompt or the response tripped Apple's safety guardrails.
final class GuardrailViolationException extends FoundationModelsException {
  /// Creates the exception.
  const GuardrailViolationException(super.message);
}

/// The model declined to answer.
final class RefusalException extends FoundationModelsException {
  /// Creates the exception.
  const RefusalException(super.message);
}

/// The requested language or locale is not supported by the on-device model.
final class UnsupportedLanguageException extends FoundationModelsException {
  /// Creates the exception.
  const UnsupportedLanguageException(super.message);
}

/// The model's output did not conform to the requested schema.
final class DecodingFailureException extends FoundationModelsException {
  /// Creates the exception.
  const DecodingFailureException(super.message);
}

/// A schema was rejected as invalid or unsupported.
final class SchemaException extends FoundationModelsException {
  /// Creates the exception.
  const SchemaException(super.message);
}

/// Too many requests were issued too quickly.
final class RateLimitedException extends FoundationModelsException {
  /// Creates the exception.
  const RateLimitedException(super.message);
}

/// A second request was made while the session was still responding.
///
/// A session handles one request at a time. Await the first, or use a second
/// session.
final class ConcurrentRequestException extends FoundationModelsException {
  /// Creates the exception.
  const ConcurrentRequestException(super.message);
}

/// The model's assets are unavailable, usually mid-download.
final class AssetsUnavailableException extends FoundationModelsException {
  /// Creates the exception.
  const AssetsUnavailableException(super.message);
}

/// A tool invoked by the model threw.
final class ToolCallException extends FoundationModelsException {
  /// Creates the exception for the tool named [toolName].
  const ToolCallException(this.toolName, super.message);

  /// Which tool failed.
  final String toolName;
}

/// Anything the platform reported that does not map to a specific case.
final class FoundationModelsPlatformException
    extends FoundationModelsException {
  /// Creates the exception with an optional platform error [code].
  const FoundationModelsPlatformException(super.message, {this.code});

  /// The raw platform error code, when there was one.
  final String? code;
}
