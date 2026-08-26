import 'package:flutter/foundation.dart';

/// How fast the indicator itself moves.
///
/// Distinct from `LoadingTiming`, which decides *when* the overlay appears and
/// leaves. This decides how quickly the thing on screen animates once it is
/// there, and it is purely cosmetic — changing it cannot affect the
/// anti-flicker guarantees.
///
/// ```dart
/// LoadingStyle.material.copyWith(motion: LoadingMotion.brisk)
/// LoadingStyle.material.copyWith(
///   motion: const LoadingMotion(spinPeriod: Duration(seconds: 2)),
/// )
/// ```
@immutable
class LoadingMotion {
  /// Creates a motion profile. The defaults match Material's own cadence.
  const LoadingMotion({
    this.spinPeriod = const Duration(milliseconds: 1333),
    this.morphDuration = const Duration(milliseconds: 620),
    this.progressDuration = const Duration(milliseconds: 340),
    this.barSweepPeriod = const Duration(milliseconds: 1400),
    this.crossFadeDuration = const Duration(milliseconds: 260),
  });

  /// One full cycle of the indeterminate indicator.
  ///
  /// Shorter reads as urgent, longer as calm. This is the knob most people
  /// reach for first.
  final Duration spinPeriod;

  /// How long the indicator takes to settle into a check or a cross.
  final Duration morphDuration;

  /// How long determinate progress takes to catch up to a new value.
  ///
  /// This is what turns coarse jumps — 0.2, then 0.4 — into continuous motion.
  /// Setting it to [Duration.zero] makes progress snap.
  final Duration progressDuration;

  /// One full sweep of the indeterminate progress bar.
  final Duration barSweepPeriod;

  /// How long the bar takes to cross-fade into the terminal glyph.
  final Duration crossFadeDuration;

  /// The default cadence.
  static const LoadingMotion standard = LoadingMotion();

  /// Quicker throughout. Suits utilitarian, dense interfaces.
  static const LoadingMotion brisk = LoadingMotion(
    spinPeriod: Duration(milliseconds: 900),
    morphDuration: Duration(milliseconds: 440),
    progressDuration: Duration(milliseconds: 220),
    barSweepPeriod: Duration(milliseconds: 1000),
    crossFadeDuration: Duration(milliseconds: 180),
  );

  /// Slower and softer. Suits editorial or content-led interfaces.
  static const LoadingMotion calm = LoadingMotion(
    spinPeriod: Duration(milliseconds: 1900),
    morphDuration: Duration(milliseconds: 820),
    progressDuration: Duration(milliseconds: 460),
    barSweepPeriod: Duration(milliseconds: 2000),
    crossFadeDuration: Duration(milliseconds: 340),
  );

  /// Returns a copy with the given fields replaced.
  LoadingMotion copyWith({
    Duration? spinPeriod,
    Duration? morphDuration,
    Duration? progressDuration,
    Duration? barSweepPeriod,
    Duration? crossFadeDuration,
  }) {
    return LoadingMotion(
      spinPeriod: spinPeriod ?? this.spinPeriod,
      morphDuration: morphDuration ?? this.morphDuration,
      progressDuration: progressDuration ?? this.progressDuration,
      barSweepPeriod: barSweepPeriod ?? this.barSweepPeriod,
      crossFadeDuration: crossFadeDuration ?? this.crossFadeDuration,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadingMotion &&
          other.spinPeriod == spinPeriod &&
          other.morphDuration == morphDuration &&
          other.progressDuration == progressDuration &&
          other.barSweepPeriod == barSweepPeriod &&
          other.crossFadeDuration == crossFadeDuration;

  @override
  int get hashCode => Object.hash(
    spinPeriod,
    morphDuration,
    progressDuration,
    barSweepPeriod,
    crossFadeDuration,
  );

  @override
  String toString() => 'LoadingMotion(spinPeriod: $spinPeriod)';
}
