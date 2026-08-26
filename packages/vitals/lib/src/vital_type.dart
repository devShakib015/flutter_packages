import 'package:flutter/foundation.dart';

import 'vital_sample.dart';

/// How a series of samples is reduced into one number per bucket.
enum VitalAggregate {
  /// Add the samples together. Right for steps, distance, energy.
  sum,

  /// Take the mean. Right for heart rate, temperature, oxygen saturation.
  average,

  /// The smallest value in the bucket.
  minimum,

  /// The largest value in the bucket.
  maximum,

  /// The most recent value. Right for standing measurements such as weight.
  latest,
}

/// A kind of health data, carrying the Dart type it reads back as.
///
/// The type parameter is what removes casting from the call site:
///
/// ```dart
/// final steps = await vitals.read(VitalType.steps, from: a, to: b);
/// // steps is List<CountSample>; steps.first.count is an int.
///
/// final weight = await vitals.read(VitalType.bodyMass, from: a, to: b);
/// // weight is List<MassSample>; weight.first.value is a Mass.
/// ```
///
/// [defaultAggregate] is the reduction that makes sense for the measurement —
/// summing steps is right, summing heart rates is nonsense — so
/// `statistics()` does the sensible thing without being told.
@immutable
class VitalType<T extends VitalSample> {
  const VitalType._(
    this.id,
    this.decode, {
    required this.defaultAggregate,
    this.writable = true,
  });

  /// Stable identifier shared with the platform side.
  final String id;

  /// Turns a platform map into a typed sample.
  final T Function(Map<Object?, Object?> map) decode;

  /// The reduction that suits this measurement.
  final VitalAggregate defaultAggregate;

  /// Whether the platforms allow an app to write this type.
  final bool writable;

  // ------------------------------------------------------------- activity

  /// Steps taken.
  static const VitalType<CountSample> steps = VitalType<CountSample>._(
    'steps',
    CountSample.decode,
    defaultAggregate: VitalAggregate.sum,
  );

  /// Flights of stairs climbed.
  static const VitalType<CountSample> flightsClimbed = VitalType<CountSample>._(
    'flightsClimbed',
    CountSample.decode,
    defaultAggregate: VitalAggregate.sum,
  );

  /// Distance covered walking or running.
  static const VitalType<LengthSample> distanceWalkingRunning =
      VitalType<LengthSample>._(
        'distanceWalkingRunning',
        LengthSample.decode,
        defaultAggregate: VitalAggregate.sum,
      );

  /// Energy burned through activity, above resting.
  static const VitalType<EnergySample> activeEnergyBurned =
      VitalType<EnergySample>._(
        'activeEnergyBurned',
        EnergySample.decode,
        defaultAggregate: VitalAggregate.sum,
      );

  /// Energy burned at rest.
  static const VitalType<EnergySample> basalEnergyBurned =
      VitalType<EnergySample>._(
        'basalEnergyBurned',
        EnergySample.decode,
        defaultAggregate: VitalAggregate.sum,
      );

  // --------------------------------------------------------------- vitals

  /// Heart rate.
  static const VitalType<RateSample> heartRate = VitalType<RateSample>._(
    'heartRate',
    RateSample.decode,
    defaultAggregate: VitalAggregate.average,
  );

  /// Resting heart rate.
  static const VitalType<RateSample> restingHeartRate = VitalType<RateSample>._(
    'restingHeartRate',
    RateSample.decode,
    defaultAggregate: VitalAggregate.average,
  );

  /// Breaths per minute.
  static const VitalType<RateSample> respiratoryRate = VitalType<RateSample>._(
    'respiratoryRate',
    RateSample.decode,
    defaultAggregate: VitalAggregate.average,
  );

  /// Blood oxygen saturation.
  static const VitalType<PercentSample> oxygenSaturation =
      VitalType<PercentSample>._(
        'oxygenSaturation',
        PercentSample.decode,
        defaultAggregate: VitalAggregate.average,
      );

  /// Body temperature.
  static const VitalType<TemperatureSample> bodyTemperature =
      VitalType<TemperatureSample>._(
        'bodyTemperature',
        TemperatureSample.decode,
        defaultAggregate: VitalAggregate.average,
      );

  /// Systolic blood pressure.
  static const VitalType<PressureSample> bloodPressureSystolic =
      VitalType<PressureSample>._(
        'bloodPressureSystolic',
        PressureSample.decode,
        defaultAggregate: VitalAggregate.average,
      );

  /// Diastolic blood pressure.
  static const VitalType<PressureSample> bloodPressureDiastolic =
      VitalType<PressureSample>._(
        'bloodPressureDiastolic',
        PressureSample.decode,
        defaultAggregate: VitalAggregate.average,
      );

  /// Blood glucose concentration.
  static const VitalType<ConcentrationSample> bloodGlucose =
      VitalType<ConcentrationSample>._(
        'bloodGlucose',
        ConcentrationSample.decode,
        defaultAggregate: VitalAggregate.average,
      );

  // ----------------------------------------------------------------- body

  /// Body weight.
  static const VitalType<MassSample> bodyMass = VitalType<MassSample>._(
    'bodyMass',
    MassSample.decode,
    defaultAggregate: VitalAggregate.latest,
  );

  /// Lean body mass.
  static const VitalType<MassSample> leanBodyMass = VitalType<MassSample>._(
    'leanBodyMass',
    MassSample.decode,
    defaultAggregate: VitalAggregate.latest,
  );

  /// Body fat, as a fraction.
  static const VitalType<PercentSample> bodyFatPercentage =
      VitalType<PercentSample>._(
        'bodyFatPercentage',
        PercentSample.decode,
        defaultAggregate: VitalAggregate.latest,
      );

  /// Height.
  static const VitalType<LengthSample> height = VitalType<LengthSample>._(
    'height',
    LengthSample.decode,
    defaultAggregate: VitalAggregate.latest,
  );

  // ------------------------------------------------------------- lifestyle

  /// Water drunk.
  static const VitalType<VolumeSample> water = VitalType<VolumeSample>._(
    'water',
    VolumeSample.decode,
    defaultAggregate: VitalAggregate.sum,
  );

  /// Time spent in a mindfulness session.
  static const VitalType<DurationSample> mindfulSession =
      VitalType<DurationSample>._(
        'mindfulSession',
        DurationSample.decode,
        defaultAggregate: VitalAggregate.sum,
      );

  /// Sleep, broken into stages.
  static const VitalType<SleepSample> sleep = VitalType<SleepSample>._(
    'sleep',
    SleepSample.decode,
    defaultAggregate: VitalAggregate.sum,
  );

  /// Recorded workouts.
  ///
  /// Not writable here: both platforms want a workout builder rather than a
  /// single sample, which is a larger API than this version covers.
  static const VitalType<WorkoutSample> workout = VitalType<WorkoutSample>._(
    'workout',
    WorkoutSample.decode,
    defaultAggregate: VitalAggregate.sum,
    writable: false,
  );

  /// Every type this version supports.
  static const List<VitalType<VitalSample>> all = <VitalType<VitalSample>>[
    steps,
    flightsClimbed,
    distanceWalkingRunning,
    activeEnergyBurned,
    basalEnergyBurned,
    heartRate,
    restingHeartRate,
    respiratoryRate,
    oxygenSaturation,
    bodyTemperature,
    bloodPressureSystolic,
    bloodPressureDiastolic,
    bloodGlucose,
    bodyMass,
    leanBodyMass,
    bodyFatPercentage,
    height,
    water,
    mindfulSession,
    sleep,
    workout,
  ];

  /// Finds a type by its [id], or null when unrecognised.
  static VitalType<VitalSample>? byId(String id) {
    for (final VitalType<VitalSample> type in all) {
      if (type.id == id) return type;
    }
    return null;
  }

  // Deliberately no `==` override. Every type is a `static const` singleton,
  // so identity equality is already correct — and a class that overrides `==`
  // cannot be an element of a const set, which would break the natural
  // `const PermissionRequest(read: {VitalType.steps})`.

  @override
  String toString() => 'VitalType.$id';
}
