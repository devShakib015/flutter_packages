import 'package:flutter/foundation.dart';

/// Base class for every failure this package raises.
@immutable
sealed class VitalsException implements Exception {
  /// Creates an exception.
  const VitalsException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A query was made before the user was ever asked for access.
///
/// This is the one permission state iOS *can* report, and it is worth acting
/// on. HealthKit recognises three situations, and only two look alike:
///
/// | State | What a read does |
/// | --- | --- |
/// | Never requested | **throws this** |
/// | Requested, granted | returns data |
/// | Requested, refused | returns empty — indistinguishable from no data |
///
/// So this exception means *you forgot to call
/// `requestPermissions`* — a bug in your app, not a choice by the user. Once
/// the sheet has been shown, reads stop throwing and start coming back empty
/// whether or not anything was allowed.
final class AuthorizationNotDeterminedException extends VitalsException {
  /// Creates the exception.
  const AuthorizationNotDeterminedException(super.message);
}

/// Health data is not usable on this device.
final class HealthDataUnavailableException extends VitalsException {
  /// Creates the exception.
  const HealthDataUnavailableException(super.message);
}

/// The requested type has no equivalent on this platform.
///
/// Health Connect does not model mindfulness at all, and its nearest record to
/// basal energy is a rate rather than an interval total. Both are reported
/// here rather than approximated.
final class UnsupportedVitalTypeException extends VitalsException {
  /// Creates the exception for [typeId].
  const UnsupportedVitalTypeException(this.typeId, super.message);

  /// The type that could not be served.
  final String typeId;
}

/// The platform refused a write, usually because access was denied.
final class VitalsWriteException extends VitalsException {
  /// Creates the exception.
  const VitalsWriteException(super.message);
}

/// Anything the platform reported that does not map to a specific case.
final class VitalsPlatformException extends VitalsException {
  /// Creates the exception with the raw platform [code].
  const VitalsPlatformException(super.message, {this.code});

  /// The platform's own error code.
  final String? code;
}
