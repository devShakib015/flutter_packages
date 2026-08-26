import 'package:flutter/foundation.dart';

import 'vital_sample.dart';
import 'vital_type.dart';

/// Whether this app may write a given type.
enum WriteAccess {
  /// The user has allowed writing.
  granted,

  /// The user has refused.
  denied,

  /// The user has not been asked yet.
  notDetermined,
}

/// Why this package has no `readAccess()`.
///
/// It is not an oversight. `HKAuthorizationStatus` has exactly three values —
/// `notDetermined`, `sharingDenied`, `sharingAuthorized` — and all three
/// describe *writing*. Apple provides no way to ask whether the user granted
/// read access, deliberately: knowing which health types a person has recorded
/// would itself disclose health information.
///
/// So an API that answers "do I have read permission?" cannot be truthful on
/// iOS. Rather than return a number that is wrong, this package omits the
/// question and offers [VitalsReadProbe] instead.
///
/// The correct pattern is to attempt the read and interpret the result:
///
/// ```dart
/// final steps = await vitals.read(VitalType.steps, from: weekAgo, to: now);
/// if (steps.isEmpty) {
///   // Either permission was refused, or there is genuinely no data.
///   // You cannot tell them apart, and neither can any other package.
///   showEmptyState();
/// }
/// ```
///
/// Android Health Connect *can* report read permission, so
/// [Vitals.readAccessOnAndroid] exposes it there and returns null on iOS —
/// making the asymmetry visible rather than papering over it.
abstract final class VitalsReadProbe {
  /// Documentation-only. Never instantiated.
  const VitalsReadProbe._();
}

/// What was asked for, and what came back.
@immutable
class PermissionRequest {
  /// Creates a request.
  const PermissionRequest({
    this.read = const <VitalType<VitalSample>>{},
    this.write = const <VitalType<VitalSample>>{},
  });

  /// Types to request read access for.
  final Set<VitalType<VitalSample>> read;

  /// Types to request write access for.
  final Set<VitalType<VitalSample>> write;

  /// Every type mentioned.
  Set<VitalType<VitalSample>> get all => <VitalType<VitalSample>>{
    ...read,
    ...write,
  };

  /// Whether anything was actually requested.
  bool get isEmpty => read.isEmpty && write.isEmpty;

  /// Wire representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'read': read.map((VitalType<VitalSample> t) => t.id).toList(),
    'write': write.map((VitalType<VitalSample> t) => t.id).toList(),
  };
}
