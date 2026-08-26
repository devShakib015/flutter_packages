import 'package:flutter/foundation.dart';

import 'units.dart';

/// Where a sample came from.
@immutable
class VitalSource {
  /// Creates a source.
  const VitalSource({required this.name, this.bundleId, this.device});

  /// The app or device that recorded it, as the platform reports it.
  final String name;

  /// The writing app's bundle identifier, when the platform provides one.
  final String? bundleId;

  /// The hardware that produced it, such as `Apple Watch`.
  final String? device;

  /// Reads a source off the platform channel.
  factory VitalSource.fromMap(Map<Object?, Object?> map) => VitalSource(
    name: map['name'] as String? ?? 'unknown',
    bundleId: map['bundleId'] as String?,
    device: map['device'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is VitalSource &&
      other.name == name &&
      other.bundleId == bundleId &&
      other.device == device;

  @override
  int get hashCode => Object.hash(name, bundleId, device);

  @override
  String toString() => device == null ? name : '$name ($device)';
}

/// A single recorded measurement.
///
/// Subclasses carry a value of the right shape — [CountSample.count] is an
/// `int`, [MassSample.value] is a [Mass] — so nothing has to be cast out of a
/// union at the call site.
@immutable
sealed class VitalSample {
  /// Creates a sample.
  const VitalSample({
    required this.start,
    required this.end,
    required this.source,
    this.id,
  });

  /// When the measurement began.
  final DateTime start;

  /// When it ended. Equal to [start] for instantaneous readings.
  final DateTime end;

  /// What recorded it.
  final VitalSource source;

  /// The platform's identifier, where it exposes one. Needed to delete.
  final String? id;

  /// How long the measurement covers.
  Duration get duration => end.difference(start);

  /// Whether the reading is a point rather than an interval.
  bool get isInstantaneous => start == end;

  /// The sample reduced to one number, for aggregation.
  ///
  /// Each shape picks its canonical unit — kilograms, metres, kilocalories,
  /// beats per minute — and interval types report elapsed minutes. Null means
  /// the sample carries nothing summable.
  double? get aggregableValue;
}

/// Fields every sample shares, read off the platform channel.
class _Common {
  const _Common(this.start, this.end, this.source, this.id);
  final DateTime start;
  final DateTime end;
  final VitalSource source;
  final String? id;

  static _Common of(Map<Object?, Object?> m) {
    DateTime at(Object? v) => DateTime.fromMillisecondsSinceEpoch(
      (v as num?)?.toInt() ?? 0,
      isUtc: true,
    ).toLocal();
    return _Common(
      at(m['start']),
      at(m['end'] ?? m['start']),
      VitalSource.fromMap(
        (m['source'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
      ),
      m['id'] as String?,
    );
  }
}

double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

/// A whole-number tally, such as steps or flights climbed.
@immutable
final class CountSample extends VitalSample {
  /// Creates a count sample.
  const CountSample({
    required this.count,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The tally.
  final int count;

  /// Reads one off the platform channel.
  static CountSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return CountSample(
      count: _num(m['value']).round(),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => count.toDouble();

  @override
  String toString() => 'CountSample($count)';
}

/// A body mass reading.
@immutable
final class MassSample extends VitalSample {
  /// Creates a mass sample.
  const MassSample({
    required this.value,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The measured mass.
  final Mass value;

  /// Reads one off the platform channel.
  static MassSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return MassSample(
      value: Mass.kilograms(_num(m['value'])),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => value.kilograms;

  @override
  String toString() => 'MassSample($value)';
}

/// A distance reading.
@immutable
final class LengthSample extends VitalSample {
  /// Creates a length sample.
  const LengthSample({
    required this.value,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The measured length.
  final Length value;

  /// Reads one off the platform channel.
  static LengthSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return LengthSample(
      value: Length.metres(_num(m['value'])),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => value.metres;

  @override
  String toString() => 'LengthSample($value)';
}

/// An energy reading, such as calories burned.
@immutable
final class EnergySample extends VitalSample {
  /// Creates an energy sample.
  const EnergySample({
    required this.value,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The measured energy.
  final Energy value;

  /// Reads one off the platform channel.
  static EnergySample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return EnergySample(
      value: Energy.kilocalories(_num(m['value'])),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => value.kilocalories;

  @override
  String toString() => 'EnergySample($value)';
}

/// A per-minute rate, such as heart rate or respiratory rate.
@immutable
final class RateSample extends VitalSample {
  /// Creates a rate sample.
  const RateSample({
    required this.perMinute,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The rate, in counts per minute.
  final double perMinute;

  /// Reads one off the platform channel.
  static RateSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return RateSample(
      perMinute: _num(m['value']),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => perMinute;

  @override
  String toString() => 'RateSample(${perMinute.toStringAsFixed(0)}/min)';
}

/// A proportion, stored as a fraction from 0 to 1.
///
/// Stored as a fraction rather than a percentage because both platforms do,
/// and converting once at the boundary beats converting at every call site.
@immutable
final class PercentSample extends VitalSample {
  /// Creates a percentage sample.
  const PercentSample({
    required this.fraction,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The proportion, 0.0 to 1.0.
  final double fraction;

  /// The same value as a percentage, 0 to 100.
  double get percent => fraction * 100;

  /// Reads one off the platform channel.
  static PercentSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return PercentSample(
      fraction: _num(m['value']),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => fraction;

  @override
  String toString() => 'PercentSample(${percent.toStringAsFixed(1)}%)';
}

/// A body temperature reading.
@immutable
final class TemperatureSample extends VitalSample {
  /// Creates a temperature sample.
  const TemperatureSample({
    required this.value,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The measured temperature.
  final Temperature value;

  /// Reads one off the platform channel.
  static TemperatureSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return TemperatureSample(
      value: Temperature.celsius(_num(m['value'])),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => value.celsius;

  @override
  String toString() => 'TemperatureSample($value)';
}

/// A blood pressure reading.
@immutable
final class PressureSample extends VitalSample {
  /// Creates a pressure sample.
  const PressureSample({
    required this.value,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The measured pressure.
  final Pressure value;

  /// Reads one off the platform channel.
  static PressureSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return PressureSample(
      value: Pressure.millimetresOfMercury(_num(m['value'])),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => value.millimetresOfMercury;

  @override
  String toString() => 'PressureSample($value)';
}

/// A blood glucose reading.
@immutable
final class ConcentrationSample extends VitalSample {
  /// Creates a concentration sample.
  const ConcentrationSample({
    required this.value,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The measured concentration.
  final Concentration value;

  /// Reads one off the platform channel.
  static ConcentrationSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return ConcentrationSample(
      value: Concentration.millimolesPerLitre(_num(m['value'])),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => value.millimolesPerLitre;

  @override
  String toString() => 'ConcentrationSample($value)';
}

/// A volume reading, such as water intake.
@immutable
final class VolumeSample extends VitalSample {
  /// Creates a volume sample.
  const VolumeSample({
    required this.value,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// The measured volume.
  final Volume value;

  /// Reads one off the platform channel.
  static VolumeSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return VolumeSample(
      value: Volume.litres(_num(m['value'])),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue => value.litres;

  @override
  String toString() => 'VolumeSample($value)';
}

/// Stages of sleep, as both platforms model them.
enum SleepStage {
  /// In bed but not necessarily asleep.
  inBed,

  /// Asleep, stage unspecified.
  asleep,

  /// Light sleep.
  light,

  /// Deep, slow-wave sleep.
  deep,

  /// Rapid eye movement sleep.
  rem,

  /// Awake during a sleep session.
  awake,

  /// A stage this version does not recognise.
  unknown;

  /// Whether this stage counts as actually sleeping.
  bool get isAsleep =>
      this == asleep || this == light || this == deep || this == rem;
}

/// A stretch of sleep.
@immutable
final class SleepSample extends VitalSample {
  /// Creates a sleep sample.
  const SleepSample({
    required this.stage,
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// Which stage this stretch was.
  final SleepStage stage;

  /// Reads one off the platform channel.
  static SleepSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    final String raw = m['stage'] as String? ?? '';
    return SleepSample(
      stage: SleepStage.values.firstWhere(
        (SleepStage s) => s.name == raw,
        orElse: () => SleepStage.unknown,
      ),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue =>
      duration.inMilliseconds / Duration.millisecondsPerMinute;

  @override
  String toString() => 'SleepSample(${stage.name}, $duration)';
}

/// A recorded workout.
@immutable
final class WorkoutSample extends VitalSample {
  /// Creates a workout sample.
  const WorkoutSample({
    required this.activity,
    required super.start,
    required super.end,
    required super.source,
    this.energyBurned,
    this.distance,
    super.id,
  });

  /// The activity, as the platform names it.
  final String activity;

  /// Energy burned, when recorded.
  final Energy? energyBurned;

  /// Distance covered, when recorded.
  final Length? distance;

  /// Reads one off the platform channel.
  static WorkoutSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    final Object? energy = m['energyBurned'];
    final Object? distance = m['distance'];
    return WorkoutSample(
      activity: m['activity'] as String? ?? 'other',
      energyBurned: energy == null ? null : Energy.kilocalories(_num(energy)),
      distance: distance == null ? null : Length.metres(_num(distance)),
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue =>
      duration.inMilliseconds / Duration.millisecondsPerMinute;

  @override
  String toString() => 'WorkoutSample($activity, $duration)';
}

/// A span of time, such as a mindfulness session.
@immutable
final class DurationSample extends VitalSample {
  /// Creates a duration sample.
  const DurationSample({
    required super.start,
    required super.end,
    required super.source,
    super.id,
  });

  /// Reads one off the platform channel.
  static DurationSample decode(Map<Object?, Object?> m) {
    final _Common c = _Common.of(m);
    return DurationSample(
      start: c.start,
      end: c.end,
      source: c.source,
      id: c.id,
    );
  }

  @override
  double? get aggregableValue =>
      duration.inMilliseconds / Duration.millisecondsPerMinute;

  @override
  String toString() => 'DurationSample($duration)';
}
