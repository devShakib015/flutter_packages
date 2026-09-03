import 'package:flutter/foundation.dart';

/// Why the on-device model cannot be used right now.
///
/// Most first runs land on one of these rather than on success, so the reason
/// is surfaced rather than collapsed into a bare `false`.
enum ModelUnavailableReason {
  /// The hardware cannot run the model. Needs Apple Intelligence silicon.
  deviceNotEligible,

  /// The device is capable, but the user has not turned Apple Intelligence on.
  appleIntelligenceNotEnabled,

  /// Enabled, but the model assets are still downloading or preparing.
  modelNotReady,

  /// The OS predates Foundation Models. Needs iOS 26 or macOS 26.
  osTooOld,

  /// Not an Apple platform, so there is nothing to talk to.
  unsupportedPlatform,

  /// The platform reported something this version does not recognise.
  unknown;

  /// A short, user-facing explanation of the state.
  String get explanation => switch (this) {
        deviceNotEligible => 'This device cannot run Apple Intelligence.',
        appleIntelligenceNotEnabled => 'Apple Intelligence is turned off.',
        modelNotReady => 'The on-device model is still being prepared.',
        osTooOld => 'This system is older than iOS 26 / macOS 26.',
        unsupportedPlatform =>
          'Apple Foundation Models only exist on Apple platforms.',
        unknown => 'The on-device model is unavailable.',
      };

  /// What the user could do about it, or null when nothing will help.
  String? get remedy => switch (this) {
        appleIntelligenceNotEnabled =>
          'Turn on Apple Intelligence in Settings.',
        modelNotReady => 'Stay connected to Wi-Fi and try again shortly.',
        osTooOld => 'Update to iOS 26 or macOS 26.',
        deviceNotEligible || unsupportedPlatform || unknown => null,
      };

  /// Whether waiting or a user action could plausibly change this.
  ///
  /// False means it is permanent for this device — fall back to a remote model
  /// or hide the feature rather than prompting.
  bool get isTransient =>
      this == modelNotReady || this == appleIntelligenceNotEnabled;
}

/// Whether the on-device model can be used, and if not, why.
///
/// ```dart
/// switch (await AppleFoundationModels.availability()) {
///   case ModelAvailable():
///     // go ahead
///   case ModelUnavailable(:final reason) when reason.isTransient:
///     showBanner(reason.explanation, action: reason.remedy);
///   case ModelUnavailable():
///     hideTheAiFeatureEntirely();
/// }
/// ```
@immutable
sealed class ModelAvailability {
  const ModelAvailability();

  /// Whether generation can be attempted.
  bool get isAvailable => this is ModelAvailable;
}

/// The model is loaded and ready.
@immutable
final class ModelAvailable extends ModelAvailability {
  /// Creates the available state.
  const ModelAvailable();

  @override
  String toString() => 'ModelAvailable()';

  @override
  bool operator ==(Object other) => other is ModelAvailable;

  @override
  int get hashCode => (ModelAvailable).hashCode;
}

/// The model cannot be used, with the reason attached.
@immutable
final class ModelUnavailable extends ModelAvailability {
  /// Creates the unavailable state.
  const ModelUnavailable(this.reason);

  /// Why it cannot be used.
  final ModelUnavailableReason reason;

  /// A short, user-facing explanation.
  String get explanation => reason.explanation;

  /// What the user could do, or null when nothing will help.
  String? get remedy => reason.remedy;

  @override
  String toString() => 'ModelUnavailable(${reason.name})';

  @override
  bool operator ==(Object other) =>
      other is ModelUnavailable && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}
